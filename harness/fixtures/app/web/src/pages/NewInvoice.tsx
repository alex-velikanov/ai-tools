import { useState } from 'react';

type FormState = {
  customerName: string;
  hasBillingAddress: boolean;
  billingAddress: string;
  unitPrice: string;
  quantity: string;
};

type Errors = Partial<Record<keyof FormState, string>>;

const initialState: FormState = {
  customerName: '',
  hasBillingAddress: true,
  billingAddress: '',
  unitPrice: '',
  quantity: '1',
};

export default function NewInvoice() {
  const [form, setForm] = useState<FormState>(initialState);
  const [errors, setErrors] = useState<Errors>({});
  const [submitted, setSubmitted] = useState(false);

  function validate(f: FormState): Errors {
    const next: Errors = {};
    if (!f.customerName.trim()) next.customerName = 'Customer name is required.';
    if (f.hasBillingAddress && !f.billingAddress.trim()) {
      next.billingAddress = 'Billing address is required unless the customer is marked as having none on file.';
    }
    const price = Number(f.unitPrice);
    if (!f.unitPrice || Number.isNaN(price) || price <= 0) {
      next.unitPrice = 'Unit price must be a positive number.';
    }
    const qty = Number(f.quantity);
    if (!f.quantity || !Number.isInteger(qty) || qty <= 0) {
      next.quantity = 'Quantity must be a positive whole number.';
    }
    return next;
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const next = validate(form);
    setErrors(next);
    setSubmitted(Object.keys(next).length === 0);
  }

  if (submitted) {
    return (
      <main className="page">
        <h1>Invoice created</h1>
        <p>
          {form.customerName} — {form.quantity} × ${form.unitPrice}
          {!form.hasBillingAddress && ' (no billing address on file)'}
        </p>
      </main>
    );
  }

  return (
    <main className="page">
      <h1>New invoice</h1>
      <form onSubmit={handleSubmit} noValidate>
        <label>
          Customer name
          <input
            value={form.customerName}
            onChange={(e) => setForm({ ...form, customerName: e.target.value })}
          />
          {errors.customerName && <span className="error">{errors.customerName}</span>}
        </label>

        <label>
          <input
            type="checkbox"
            checked={form.hasBillingAddress}
            onChange={(e) =>
              setForm({ ...form, hasBillingAddress: e.target.checked, billingAddress: '' })
            }
          />
          Customer has a billing address on file
        </label>

        {form.hasBillingAddress && (
          <label>
            Billing address
            <input
              value={form.billingAddress}
              onChange={(e) => setForm({ ...form, billingAddress: e.target.value })}
            />
            {errors.billingAddress && <span className="error">{errors.billingAddress}</span>}
          </label>
        )}

        <label>
          Unit price
          <input
            value={form.unitPrice}
            onChange={(e) => setForm({ ...form, unitPrice: e.target.value })}
          />
          {errors.unitPrice && <span className="error">{errors.unitPrice}</span>}
        </label>

        <label>
          Quantity
          <input
            value={form.quantity}
            onChange={(e) => setForm({ ...form, quantity: e.target.value })}
          />
          {errors.quantity && <span className="error">{errors.quantity}</span>}
        </label>

        <button type="submit">Create invoice</button>
      </form>
    </main>
  );
}
