import React, { useEffect } from 'react';
import { Route, useLocation } from 'wouter';
import { useAuth } from '@/contexts/AuthContext';

interface ProtectedRouteProps {
  path: string;
  component: React.ComponentType<any>;
  adminOnly?: boolean;
}

export function ProtectedRoute({ component: Component, adminOnly = false, path }: ProtectedRouteProps) {
  const { user, isAdmin, isLoading } = useAuth();
  const [, setLocation] = useLocation();

  return (
    <Route path={path}>
      {(params) => {
        if (isLoading) {
          return (
            <div className="min-h-screen w-full flex items-center justify-center" style={{ background: '#0a0a0a' }}>
              <div className="w-8 h-8 border-2 border-t-transparent rounded-full animate-spin" style={{ borderColor: '#c9a84c', borderTopColor: 'transparent' }} />
            </div>
          );
        }

        if (!user) {
          return <RedirectTo to="/login" setLocation={setLocation} />;
        }

        if (adminOnly && !isAdmin) {
          return <RedirectTo to="/" setLocation={setLocation} />;
        }

        return <Component {...params} />;
      }}
    </Route>
  );
}

function RedirectTo({ to, setLocation }: { to: string; setLocation: (to: string) => void }) {
  useEffect(() => {
    setLocation(to);
  }, [to, setLocation]);
  return null;
}
