import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useCart } from '../cart.jsx';
import { supabase, configured, formatBrandText } from '../supabase.js';

// "Checkout" is a request-a-quote: it writes one row to the quotes table
// (anon insert is the only write RLS allows). No payment, by design.
export default function Cart() {
  const cart = useCart();
  const [contact, setContact] = useState({ name: '', email: '', org: '', note: '' });
  const [status, setStatus] = useState(null);
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setStatus(null);
    if (!configured) {
      setStatus({ ok: false, msg: 'Backend not configured. Quotation request simulated successfully.' });
      return;
    }
    if (!cart.items.length) {
      setStatus({ ok: false, msg: 'Your quote request is currently empty.' });
      return;
    }
    setBusy(true);
    const { error } = await supabase.from('quotes').insert({
      contact,
      items: cart.items,
    });
    setBusy(false);
    if (error) {
      setStatus({ ok: false, msg: `Could not send: ${error.message}` });
    } else {
      setStatus({ ok: true, msg: 'Quote request successfully received! The team will reach out promptly.' });
      cart.clear();
    }
  }

  return (
    <div className="quote-page">
      <div className="section-header">
        <div className="section-subtitle">CUSTOM DEPLOYMENT</div>
        <h1 className="section-title">Request a Deployment Quote</h1>
        <p className="section-lead">
          Configure modules and system drones for emergency operations.
          Submit your requirements below and our engineering team will provide custom specs and delivery lead times.
        </p>
      </div>

      {cart.items.length === 0 ? (
        <div className="lookup-card" style={{ marginBottom: '32px' }}>
          <div className="lookup-text">
            <h3>Your Quote List is Empty</h3>
            <p>
              Select communication modules and drones from our hardware catalog to request pricing and availability.
            </p>
          </div>
          <div>
            <Link to="/catalog" className="btn btn-primary">
              Browse Hardware Catalog &rarr;
            </Link>
          </div>
        </div>
      ) : (
        <div style={{ background: 'var(--panel)', border: '1px solid var(--line)', borderRadius: 'var(--radius-lg)', padding: '24px', marginBottom: '32px' }}>
          <table className="quote">
            <thead>
              <tr>
                <th>Hardware Product</th>
                <th>Model</th>
                <th>Qty</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {cart.items.map((i) => (
                <tr key={i.id}>
                  <td>
                    <strong>{formatBrandText(i.name)}</strong>
                  </td>
                  <td><code>{i.model_no}</code></td>
                  <td>{i.qty}</td>
                  <td>
                    <button className="link" onClick={() => cart.remove(i.id)}>
                      Remove
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div style={{ background: 'var(--panel)', border: '1px solid var(--line)', borderRadius: 'var(--radius-lg)', padding: '32px', maxWidth: '600px' }}>
        <h3 style={{ margin: '0 0 16px', color: '#fff' }}>Contact & Deployment Details</h3>
        <form className="contact" onSubmit={submit} style={{ margin: 0, maxWidth: '100%' }}>
          <input
            required
            placeholder="Full Name"
            value={contact.name}
            onChange={(e) => setContact({ ...contact, name: e.target.value })}
          />
          <input
            required
            type="email"
            placeholder="Official Email Address"
            value={contact.email}
            onChange={(e) => setContact({ ...contact, email: e.target.value })}
          />
          <input
            placeholder="Agency / Humanitarian Organisation"
            value={contact.org}
            onChange={(e) => setContact({ ...contact, org: e.target.value })}
          />
          <textarea
            placeholder="Mission Notes (e.g. estimated swarm size, target terrain, deployment timeline)"
            value={contact.note}
            onChange={(e) => setContact({ ...contact, note: e.target.value })}
          />
          <button className="btn btn-primary btn-large" disabled={busy || cart.items.length === 0}>
            {busy ? 'Sending Request…' : 'Submit Quote Request'}
          </button>
        </form>
        {status && (
          <p className={status.ok ? 'ok' : 'error'} style={{ marginTop: '16px', fontWeight: 600 }}>
            {status.msg}
          </p>
        )}
      </div>
    </div>
  );
}
