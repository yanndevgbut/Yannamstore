import React from 'react';
import { Link, useLocation } from 'wouter';
import { useAuth } from '@/contexts/AuthContext';
import { LogOut, Menu, X, ShoppingBag, MessageCircle } from 'lucide-react';

export function Layout({ children }: { children: React.ReactNode }) {
  const { user, isAdmin, signOut } = useAuth();
  const [location] = useLocation();
  const [isMobileMenuOpen, setIsMobileMenuOpen] = React.useState(false);

  const navLinks = [
    { href: '/products', label: 'Products' },
    ...(user ? [{ href: '/history', label: 'History' }] : []),
    ...(isAdmin ? [{ href: '/admin', label: 'Admin' }] : []),
  ];

  return (
    <div className="min-h-[100dvh] flex flex-col bg-background selection:bg-primary/30">
      <header className="sticky top-0 z-50 w-full border-b border-border/40 bg-background/80 backdrop-blur-md">
        <div className="container mx-auto px-4 md:px-8 h-20 flex items-center justify-between">
          <Link href="/" className="flex items-center gap-2 group">
            <div className="w-8 h-8 bg-primary rounded-sm flex items-center justify-center group-hover:bg-primary/90 transition-colors">
              <ShoppingBag className="w-5 h-5 text-primary-foreground" />
            </div>
            <span className="font-serif text-xl font-semibold tracking-wide">
              AM <span className="text-primary italic">Store</span>
            </span>
          </Link>

          {/* Desktop Nav */}
          <nav className="hidden md:flex items-center gap-8">
            {navLinks.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                className={`text-sm tracking-widest uppercase transition-colors hover:text-primary ${
                  location === link.href ? 'text-primary' : 'text-muted-foreground'
                }`}
              >
                {link.label}
              </Link>
            ))}
          </nav>

          <div className="hidden md:flex items-center gap-4">
            {user ? (
              <div className="flex items-center gap-4">
                <span className="text-sm text-muted-foreground hidden lg:inline-block">
                  {user.email}
                </span>
                <button
                  onClick={signOut}
                  className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors"
                  data-testid="button-logout"
                >
                  <LogOut className="w-4 h-4" />
                  <span>Logout</span>
                </button>
              </div>
            ) : (
              <div className="flex items-center gap-4">
                <Link href="/login" className="text-sm tracking-widest uppercase text-muted-foreground hover:text-foreground transition-colors">
                  Login
                </Link>
                <Link href="/register" className="text-sm tracking-widest uppercase bg-primary text-primary-foreground px-6 py-2 hover:bg-primary/90 transition-colors">
                  Register
                </Link>
              </div>
            )}
          </div>

          {/* Mobile Menu Toggle */}
          <button
            className="md:hidden p-2 text-muted-foreground hover:text-foreground"
            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
          >
            {isMobileMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
          </button>
        </div>

        {/* Mobile Nav */}
        {isMobileMenuOpen && (
          <div className="md:hidden border-t border-border/40 bg-background/95 backdrop-blur-md absolute w-full left-0 top-20 flex flex-col p-4 gap-4 animate-in fade-in slide-in-from-top-4">
            {navLinks.map((link) => (
              <Link
                key={link.href}
                href={link.href}
                onClick={() => setIsMobileMenuOpen(false)}
                className={`text-sm tracking-widest uppercase p-4 border border-border/20 ${
                  location === link.href ? 'text-primary border-primary/20' : 'text-muted-foreground'
                }`}
              >
                {link.label}
              </Link>
            ))}

            <div className="h-px w-full bg-border/40 my-2" />

            {user ? (
              <button
                onClick={() => {
                  signOut();
                  setIsMobileMenuOpen(false);
                }}
                className="flex items-center justify-center gap-2 text-sm uppercase tracking-widest p-4 border border-border/20 text-muted-foreground"
              >
                <LogOut className="w-4 h-4" />
                <span>Logout</span>
              </button>
            ) : (
              <div className="flex flex-col gap-4">
                <Link
                  href="/login"
                  onClick={() => setIsMobileMenuOpen(false)}
                  className="text-center text-sm tracking-widest uppercase p-4 border border-border/20 text-muted-foreground"
                >
                  Login
                </Link>
                <Link
                  href="/register"
                  onClick={() => setIsMobileMenuOpen(false)}
                  className="text-center text-sm tracking-widest uppercase bg-primary text-primary-foreground p-4"
                >
                  Register
                </Link>
              </div>
            )}
          </div>
        )}
      </header>

      <main className="flex-1 flex flex-col">
        {children}
      </main>

      <footer className="border-t border-border/40 bg-card/30 mt-auto">
        <div className="container mx-auto px-4 md:px-8 py-12">
          <div className="flex flex-col md:flex-row justify-between items-center gap-8 mb-8">
            <div className="flex items-center gap-2 opacity-50">
              <ShoppingBag className="w-5 h-5" />
              <span className="font-serif text-xl">AM <span className="italic">Store</span></span>
            </div>

            <nav className="flex flex-wrap items-center justify-center gap-6 text-sm text-muted-foreground">
              <Link href="/products" className="hover:text-foreground transition-colors">Products</Link>
              {user && <Link href="/history" className="hover:text-foreground transition-colors">History</Link>}
              <Link href="/contact" className="hover:text-foreground transition-colors flex items-center gap-1">
                <MessageCircle className="w-3.5 h-3.5" />
                Contact Developer
              </Link>
            </nav>
          </div>

          <div className="flex flex-col md:flex-row justify-between items-center gap-4 pt-6 border-t border-border/30">
            <p className="text-sm text-muted-foreground text-center md:text-left">
              © {new Date().getFullYear()} AM Store. The premium digital marketplace. All rights reserved.
            </p>
            <Link
              href="/contact"
              className="text-xs text-muted-foreground hover:text-primary transition-colors uppercase tracking-widest"
            >
              Bantuan & Laporan Bug
            </Link>
          </div>
        </div>
      </footer>
    </div>
  );
}
