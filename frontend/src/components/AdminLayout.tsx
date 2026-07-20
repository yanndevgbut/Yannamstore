import React from 'react';
import { Link, useLocation } from 'wouter';
import { useAuth } from '@/contexts/AuthContext';
import { LogOut, LayoutDashboard, Package, Receipt, Tag } from 'lucide-react';

export function AdminLayout({ children }: { children: React.ReactNode }) {
  const [location] = useLocation();
  const { signOut } = useAuth();

  const links = [
    { href: '/admin', label: 'Dashboard', icon: LayoutDashboard },
    { href: '/admin/stocks', label: 'Products & Stock', icon: Package },
    { href: '/admin/transactions', label: 'Transactions', icon: Receipt },
    { href: '/admin/discount-codes', label: 'Kode Diskon', icon: Tag },
  ];

  return (
    <div className="min-h-[100dvh] flex flex-col md:flex-row bg-background selection:bg-primary/30">
      {/* Sidebar */}
      <aside className="w-full md:w-64 border-b md:border-b-0 md:border-r border-border/40 bg-card/50 flex flex-col">
        <div className="p-6 border-b border-border/40 flex items-center justify-between md:justify-start gap-4">
          <Link href="/" className="font-serif text-xl tracking-wide text-primary">
            AM <span className="italic text-foreground">Admin</span>
          </Link>
          <Link href="/" className="md:hidden text-xs uppercase tracking-widest text-muted-foreground">Exit</Link>
        </div>

        <nav className="flex-1 p-4 space-y-2 overflow-x-auto md:overflow-x-hidden flex md:flex-col items-center md:items-stretch hide-scrollbar">
          {links.map((link) => {
            const isActive = location === link.href;
            return (
              <Link
                key={link.href}
                href={link.href}
                className={`flex items-center gap-3 px-4 py-3 text-sm transition-colors whitespace-nowrap ${
                  isActive
                    ? 'bg-primary/10 text-primary border-r-2 border-primary'
                    : 'text-muted-foreground hover:bg-white/5 hover:text-foreground'
                }`}
              >
                <link.icon className="w-4 h-4" />
                {link.label}
              </Link>
            );
          })}
        </nav>

        <div className="p-4 border-t border-border/40 hidden md:block">
          <button
            onClick={signOut}
            className="flex items-center gap-3 px-4 py-3 text-sm text-muted-foreground hover:text-foreground w-full transition-colors"
          >
            <LogOut className="w-4 h-4" />
            Sign Out
          </button>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 overflow-auto bg-background/50">
        <div className="p-4 md:p-8 max-w-7xl mx-auto">
          {children}
        </div>
      </main>
    </div>
  );
}
