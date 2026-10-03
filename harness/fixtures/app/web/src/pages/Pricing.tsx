const PLANS = [
  { name: 'Free', price: '$0', features: ['1 project', 'Community support'] },
  { name: 'Pro', price: '$20/mo', features: ['Unlimited projects', 'Priority support'] },
  { name: 'Team', price: '$80/mo', features: ['Everything in Pro', 'SSO', 'Audit log'] },
];

export default function Pricing() {
  return (
    <main className="page">
      <h1>Pricing</h1>
      <div className="plans">
        {PLANS.map((plan) => (
          <section key={plan.name} className="plan">
            <h2>{plan.name}</h2>
            <p className="price">{plan.price}</p>
            <ul>
              {plan.features.map((f) => (
                <li key={f}>{f}</li>
              ))}
            </ul>
          </section>
        ))}
      </div>
    </main>
  );
}
