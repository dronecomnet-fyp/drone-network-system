import { useState } from 'react';
import { useCart } from '../cart.jsx';
import { supabase, configured } from '../supabase.js';

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
      setStatus({ ok: false, msg: 'Backend not configured.' });
      return;
    }
    if (!cart.items.length) {
      setStatus({ ok: false, msg: 'Your quote is empty.' });
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
      setStatus({ ok: true, msg: 'Quote request received. We will be in touch.' });
      cart.clear();
    }
  }

  return (
    <>
      <h1>Request a quote</h1>
      {cart.items.length === 0 ? (
        <p>Your quote is empty. Add products from the catalog.</p>
      ) : (
        <table className="quote">
          <thead>
            <tr>
              <th>Product</th>
              <th>Model</th>
              <th>Qty</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {cart.items.map((i) => (
              <tr key={i.id}>
                <td>{i.name}</td>
                <td>{i.model_no}</td>
                <td>{i.qty}</td>
                <td>
                  <button className="link" onClick={() => cart.remove(i.id)}>
                    remove
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <form className="contact" onSubmit={submit}>
        <input
          required
          placeholder="Your name"
          value={contact.name}
          onChange={(e) => setContact({ ...contact, name: e.target.value })}
        />
        <input
          required
          type="email"
          placeholder="Email"
          value={contact.email}
          onChange={(e) => setContact({ ...contact, email: e.target.value })}
        />
        <input
          placeholder="Organisation"
          value={contact.org}
          onChange={(e) => setContact({ ...contact, org: e.target.value })}
        />
        <textarea
          placeholder="Notes (deployment size, timeline)"
          value={contact.note}
          onChange={(e) => setContact({ ...contact, note: e.target.value })}
        />
        <button className="btn" disabled={busy}>
          {busy ? 'Sending…' : 'Send quote request'}
        </button>
      </form>
      {status && (
        <p className={status.ok ? 'ok' : 'error'}>{status.msg}</p>
      )}
    </>
  );
}
