import { useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase, configured } from '../supabase.js';

// The same lookup the ground control app performs by unit ID, exposed for
// people to try in a browser: enter a unit ID, get its product + specs.
export default function UnitLookup() {
  const [unitId, setUnitId] = useState('');
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  async function lookup(e) {
    e.preventDefault();
    setError(null);
    setResult(null);
    if (!configured) {
      setError('Backend not configured.');
      return;
    }
    setBusy(true);
    const { data, error } = await supabase
      .from('units')
      .select('unit_id,status,products(id,model_no,name,specs)')
      .eq('unit_id', unitId.trim())
      .maybeSingle();
    setBusy(false);
    if (error) setError(error.message);
    else if (!data) setError(`No unit "${unitId.trim()}" found.`);
    else setResult(data);
  }

  return (
    <>
      <h1>Unit lookup</h1>
      <p className="lead">
        Every unit has an ID printed on it (for example DCM-A-0042). Enter it
        to see exactly what that hardware is. This is the same call the ground
        control app makes to fetch specs into a mission.
      </p>
      <form className="lookup" onSubmit={lookup}>
        <input
          value={unitId}
          onChange={(e) => setUnitId(e.target.value)}
          placeholder="e.g. DCM-A-0042"
          aria-label="unit id"
        />
        <button className="btn" disabled={busy || !unitId.trim()}>
          {busy ? 'Looking…' : 'Look up'}
        </button>
      </form>
      {error && <p className="error">{error}</p>}
      {result && (
        <div className="card">
          <div className="card-title">{result.products?.name}</div>
          <div className="muted">
            {result.products?.model_no} &middot; unit {result.unit_id} &middot;{' '}
            {result.status}
          </div>
          <pre className="json">
            {JSON.stringify(result.products?.specs || {}, null, 2)}
          </pre>
          {result.products?.id && (
            <Link className="btn ghost" to={`/product/${result.products.id}`}>
              View product
            </Link>
          )}
        </div>
      )}
    </>
  );
}
