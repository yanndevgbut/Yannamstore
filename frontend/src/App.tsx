import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { Toaster } from '@/components/ui/toaster';
import { Route, Switch, Router as WouterRouter } from 'wouter';
import { AuthProvider } from '@/contexts/AuthContext';
import { ProtectedRoute } from '@/components/ProtectedRoute';

import Home from '@/pages/index';
import Login from '@/pages/login';
import Register from '@/pages/register';
import ForgotPassword from '@/pages/forgot-password';
import Contact from '@/pages/contact';
import Products from '@/pages/products';
import Checkout from '@/pages/checkout';
import History from '@/pages/history';
import TransactionDetail from '@/pages/transaction-detail';
import AdminDashboard from '@/pages/admin/dashboard';
import AdminStocks from '@/pages/admin/stocks';
import AdminTransactions from '@/pages/admin/transactions';
import AdminDiscountCodes from '@/pages/admin/discount-codes';
import NotFound from '@/pages/not-found';

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, staleTime: 30_000 } },
});

function Router() {
  return (
    <Switch>
      <Route path="/" component={Home} />
      <Route path="/login" component={Login} />
      <Route path="/register" component={Register} />
      <Route path="/forgot-password" component={ForgotPassword} />
      <Route path="/contact" component={Contact} />
      <ProtectedRoute path="/products" component={Products} />
      <ProtectedRoute path="/checkout/:transactionId" component={Checkout} />
      <ProtectedRoute path="/history" component={History} />
      <ProtectedRoute path="/history/:transactionId" component={TransactionDetail} />
      <ProtectedRoute path="/admin" component={AdminDashboard} adminOnly={true} />
      <ProtectedRoute path="/admin/stocks" component={AdminStocks} adminOnly={true} />
      <ProtectedRoute path="/admin/transactions" component={AdminTransactions} adminOnly={true} />
      <ProtectedRoute path="/admin/discount-codes" component={AdminDiscountCodes} adminOnly={true} />
      <Route component={NotFound} />
    </Switch>
  );
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <WouterRouter>
          <Router />
        </WouterRouter>
        <Toaster />
      </AuthProvider>
    </QueryClientProvider>
  );
}
