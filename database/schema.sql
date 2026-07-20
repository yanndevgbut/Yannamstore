-- ============================================================
-- Alight Motion Store — Supabase Database Schema (v1 + v2)
-- Aman untuk dijalankan ulang — semua statement sudah idempotent
-- Jalankan di: Supabase Dashboard → SQL Editor → New Query → Run
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- PROFILES TABLE (extends auth.users)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name       TEXT NOT NULL DEFAULT '',
  email      TEXT NOT NULL DEFAULT '',
  role       TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'admin')),
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================
-- PRODUCTS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.products (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT NOT NULL,
  description TEXT,
  price       NUMERIC(10, 2) NOT NULL CHECK (price > 0),
  is_active   BOOLEAN DEFAULT TRUE NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================
-- ACCOUNT STOCKS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.account_stocks (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id       UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  credentials_data TEXT NOT NULL,
  status           TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'sold')),
  created_at       TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================
-- DISCOUNT CODES TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.discount_codes (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  code       TEXT NOT NULL UNIQUE,
  title      TEXT,
  type       TEXT NOT NULL DEFAULT 'percentage' CHECK (type IN ('percentage', 'fixed')),
  value      NUMERIC(10, 2) NOT NULL CHECK (value > 0),
  is_active  BOOLEAN DEFAULT TRUE NOT NULL,
  expires_at TIMESTAMPTZ,
  max_uses   INTEGER,
  use_count  INTEGER DEFAULT 0 NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  CONSTRAINT chk_percentage_max CHECK (
    type <> 'percentage' OR value <= 100
  )
);

-- ============================================================
-- TRANSACTIONS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.transactions (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id     UUID NOT NULL REFERENCES public.products(id),
  stock_id       UUID REFERENCES public.account_stocks(id),
  quantity       INTEGER NOT NULL DEFAULT 1 CHECK (quantity >= 1 AND quantity <= 50),
  amount         NUMERIC(10, 2) NOT NULL CHECK (amount >= 0),
  discount_code  TEXT,
  discount_amount NUMERIC(10, 2) DEFAULT 0 CHECK (discount_amount >= 0),
  payment_status TEXT NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'expired', 'failed')),
  payment_id     TEXT,
  payment_url    TEXT,
  qr_code_url    TEXT,
  created_at     TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at     TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- ============================================================
-- TRANSACTION_STOCKS TABLE (bulk purchase)
-- Setiap baris = satu akun yang dikirim dalam satu transaksi
-- ============================================================
CREATE TABLE IF NOT EXISTS public.transaction_stocks (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
  stock_id       UUID NOT NULL REFERENCES public.account_stocks(id),
  created_at     TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  UNIQUE (transaction_id, stock_id)  -- Satu stock tidak bisa masuk dua kali dalam satu transaksi
);

-- ============================================================
-- INDICES (performa query)
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_transactions_user_id      ON public.transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_payment_id   ON public.transactions(payment_id);
CREATE INDEX IF NOT EXISTS idx_transactions_status       ON public.transactions(payment_status);
CREATE INDEX IF NOT EXISTS idx_stocks_product_status     ON public.account_stocks(product_id, status);
CREATE INDEX IF NOT EXISTS idx_tx_stocks_tx_id           ON public.transaction_stocks(transaction_id);
CREATE INDEX IF NOT EXISTS idx_tx_stocks_stock_id        ON public.transaction_stocks(stock_id);
CREATE INDEX IF NOT EXISTS idx_discount_codes_code       ON public.discount_codes(code);
CREATE INDEX IF NOT EXISTS idx_profiles_email            ON public.profiles(email);

-- ============================================================
-- AUTO-UPDATE updated_at
-- ============================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS transactions_updated_at ON public.transactions;
CREATE TRIGGER transactions_updated_at
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- AUTO-CREATE PROFILE saat user baru daftar
-- Trigger ini WAJIB untuk memastikan setiap user punya profile
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, name, email, role)
  VALUES (
    NEW.id,
    COALESCE(
      NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), ''),
      split_part(NEW.email, '@', 1)
    ),
    LOWER(NEW.email),
    'customer'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Jangan gagalkan INSERT user meski profile gagal dibuat
  RAISE WARNING 'handle_new_user failed for user %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================
-- HELPER: cek apakah email sudah terdaftar (dipanggil dari client)
-- Tidak mengekspos data sensitif — hanya mengembalikan boolean
-- Search di profiles (bukan auth.users) untuk keamanan
-- ============================================================
CREATE OR REPLACE FUNCTION check_email_exists(check_email TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE email = LOWER(TRIM(check_email))
  );
$$;

-- ============================================================
-- ATOMIC STOCK ASSIGNMENT
-- Digunakan oleh webhook untuk mencegah race condition.
-- SELECT ... FOR UPDATE SKIP LOCKED memastikan hanya satu proses
-- yang bisa meng-claim stock yang sama pada satu waktu.
-- Mengembalikan array UUID stock yang berhasil di-assign.
-- ============================================================
CREATE OR REPLACE FUNCTION assign_stocks_for_transaction(
  p_transaction_id UUID,
  p_product_id     UUID,
  p_quantity       INTEGER
)
RETURNS TABLE(assigned_stock_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock_ids UUID[];
  v_stock_id  UUID;
BEGIN
  -- Kunci baris-baris stok yang dipilih secara eksklusif (SKIP LOCKED = lewati baris yang sedang dikunci)
  SELECT ARRAY_AGG(id ORDER BY created_at)
  INTO v_stock_ids
  FROM (
    SELECT id, created_at
    FROM public.account_stocks
    WHERE product_id = p_product_id
      AND status = 'available'
    ORDER BY created_at
    LIMIT p_quantity
    FOR UPDATE SKIP LOCKED
  ) sub;

  -- Jika tidak ada stok yang bisa dikunci, kembalikan kosong
  IF v_stock_ids IS NULL OR array_length(v_stock_ids, 1) = 0 THEN
    RETURN;
  END IF;

  -- Update semua stok terpilih ke 'sold' sekaligus
  UPDATE public.account_stocks
  SET status = 'sold'
  WHERE id = ANY(v_stock_ids)
    AND status = 'available'; -- Guard tambahan

  -- Insert ke transaction_stocks (ON CONFLICT DO NOTHING = idempotent)
  FOREACH v_stock_id IN ARRAY v_stock_ids LOOP
    INSERT INTO public.transaction_stocks (transaction_id, stock_id)
    VALUES (p_transaction_id, v_stock_id)
    ON CONFLICT (transaction_id, stock_id) DO NOTHING;
  END LOOP;

  -- Kembalikan daftar stock_id yang berhasil di-assign
  RETURN QUERY
    SELECT unnest(v_stock_ids);
END;
$$;

-- ============================================================
-- INCREMENT DISCOUNT USE COUNT (atomik)
-- Dipanggil oleh webhook setelah pembayaran sukses.
-- Hanya increment jika kode masih aktif dan belum melebihi max_uses.
-- ============================================================
CREATE OR REPLACE FUNCTION increment_discount_use_count(p_code TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.discount_codes
  SET use_count = use_count + 1
  WHERE code = UPPER(TRIM(p_code))
    AND is_active = TRUE
    AND (max_uses IS NULL OR use_count < max_uses);
END;
$$;

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================
ALTER TABLE public.profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_stocks     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discount_codes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_stocks ENABLE ROW LEVEL SECURITY;

-- Helper function: cek apakah user saat ini adalah admin
CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

-- ── PROFILES policies ──────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Users can view own profile"     ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile"   ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile"   ON public.profiles;
DROP POLICY IF EXISTS "Admins can manage all profiles" ON public.profiles;

CREATE POLICY "Users can view own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id OR is_admin());

CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    -- User tidak bisa mengubah role sendiri
    AND role = (SELECT role FROM public.profiles WHERE id = auth.uid())
  );

CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id AND role = 'customer');

CREATE POLICY "Admins can manage all profiles"
  ON public.profiles FOR ALL
  USING (is_admin());

-- ── PRODUCTS policies ──────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Anyone can view active products" ON public.products;
DROP POLICY IF EXISTS "Admins can manage products"      ON public.products;

CREATE POLICY "Authenticated users can view active products"
  ON public.products FOR SELECT
  USING (
    (is_active = TRUE AND auth.uid() IS NOT NULL)
    OR is_admin()
  );

CREATE POLICY "Admins can manage products"
  ON public.products FOR ALL
  USING (is_admin());

-- ── ACCOUNT STOCKS policies ────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Admins can manage stocks"                          ON public.account_stocks;
DROP POLICY IF EXISTS "Customers can view stocks from paid transactions"  ON public.account_stocks;

CREATE POLICY "Admins can manage stocks"
  ON public.account_stocks FOR ALL
  USING (is_admin());

-- Pelanggan hanya bisa melihat stok yang memang milik mereka (sudah bayar)
CREATE POLICY "Customers can view own paid stocks"
  ON public.account_stocks FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.transaction_stocks ts
      JOIN public.transactions t ON t.id = ts.transaction_id
      WHERE ts.stock_id = account_stocks.id
        AND t.user_id = auth.uid()
        AND t.payment_status = 'paid'
    )
    OR EXISTS (
      SELECT 1 FROM public.transactions t
      WHERE t.stock_id = account_stocks.id
        AND t.user_id = auth.uid()
        AND t.payment_status = 'paid'
    )
  );

-- ── TRANSACTIONS policies ──────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Users can view own transactions"          ON public.transactions;
DROP POLICY IF EXISTS "Service role can manage all transactions" ON public.transactions;
DROP POLICY IF EXISTS "Admins can view all transactions"         ON public.transactions;

CREATE POLICY "Users can view own transactions"
  ON public.transactions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Admins can view all transactions"
  ON public.transactions FOR SELECT
  USING (is_admin());

-- ── DISCOUNT CODES policies ────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Admins can manage discount codes"        ON public.discount_codes;
DROP POLICY IF EXISTS "Authenticated users can validate codes"  ON public.discount_codes;
DROP POLICY IF EXISTS "Anyone can read active codes"            ON public.discount_codes;

-- Admin: akses penuh
CREATE POLICY "Admins can manage discount codes"
  ON public.discount_codes FOR ALL
  USING (is_admin());

-- User yang sudah login: hanya bisa SELECT kolom yang aman (untuk validasi)
-- Tidak bisa melihat use_count, max_uses, dll lengkap — hanya untuk validasi
CREATE POLICY "Authenticated users can validate active codes"
  ON public.discount_codes FOR SELECT
  USING (auth.uid() IS NOT NULL AND is_active = TRUE);

-- ── TRANSACTION_STOCKS policies ────────────────────────────────────────────────
DROP POLICY IF EXISTS "Admins can manage transaction stocks"  ON public.transaction_stocks;
DROP POLICY IF EXISTS "Users can view own transaction stocks" ON public.transaction_stocks;

CREATE POLICY "Admins can manage transaction stocks"
  ON public.transaction_stocks FOR ALL
  USING (is_admin());

CREATE POLICY "Users can view own transaction stocks"
  ON public.transaction_stocks FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.transactions t
      WHERE t.id = transaction_stocks.transaction_id
        AND t.user_id = auth.uid()
    )
  );

-- ============================================================
-- SEED DATA — Produk contoh (hanya jika belum ada data)
-- ============================================================
INSERT INTO public.products (name, description, price, is_active)
SELECT
  'Alight Motion Premium 1 Tahun',
  'Akun Alight Motion Premium dengan masa aktif 1 tahun penuh. Nikmati semua fitur premium tanpa batas: efek, template, ekspor tanpa watermark, dan masih banyak lagi.',
  99000,
  TRUE
WHERE NOT EXISTS (SELECT 1 FROM public.products LIMIT 1);

-- ============================================================
-- CARA MEMBUAT AKUN ADMIN
-- ============================================================
-- 1. Daftar akun lewat website seperti biasa (/register)
-- 2. Jalankan query ini di SQL Editor:
--
-- UPDATE public.profiles SET role = 'admin' WHERE email = 'email-anda@domain.com';
--
-- ============================================================
