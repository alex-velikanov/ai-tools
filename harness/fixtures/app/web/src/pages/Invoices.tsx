import { Link } from 'react-router-dom';

const SEED_INVOICES = [
  { id: 4820, customer: 'Acme GmbH', country: 'DE', total: 285.6 },
  { id: 4821, customer: 'Legacy Customer', country: 'DE', total: 285.6 },
  { id: 4822, customer: 'Widgets Inc', country: 'US', total: 240.0 },
];

export default function Invoices() {
  return (
    <main className="page">
      <h1>Invoices</h1>
      <Link to="/invoices/new">New invoice</Link>
      <table>
        <thead>
          <tr>
            <th>ID</th>
            <th>Customer</th>
            <th>Country</th>
            <th>Total</th>
          </tr>
        </thead>
        <tbody>
          {SEED_INVOICES.map((inv) => (
            <tr key={inv.id}>
              <td>{inv.id}</td>
              <td>{inv.customer}</td>
              <td>{inv.country}</td>
              <td>€{inv.total.toFixed(2)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
