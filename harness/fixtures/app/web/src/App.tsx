import { Routes, Route } from 'react-router-dom';
import Home from './pages/Home';
import Pricing from './pages/Pricing';
import Invoices from './pages/Invoices';
import NewInvoice from './pages/NewInvoice';
import './App.css';

function App() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/pricing" element={<Pricing />} />
      <Route path="/invoices" element={<Invoices />} />
      <Route path="/invoices/new" element={<NewInvoice />} />
    </Routes>
  );
}

export default App;
