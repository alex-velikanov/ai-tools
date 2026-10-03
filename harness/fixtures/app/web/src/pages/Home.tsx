import { Link } from 'react-router-dom';

export default function Home() {
  return (
    <main className="page">
      <h1>Test Project</h1>
      <p>Scaffold app for the dev tooling stack: PHP, Go, and this front end.</p>
      <nav>
        <Link to="/pricing">Pricing</Link>
        <Link to="/invoices">Invoices</Link>
      </nav>
    </main>
  );
}
