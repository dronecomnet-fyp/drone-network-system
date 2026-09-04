import { useState, useEffect } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { supabase, configured, formatBrandText } from '../supabase.js';

// Pre-configured fallback demo units for offline/demo reliability
const DEMO_UNITS = {
  'DCM-A-0042': {
    unit_id: 'DCM-A-0042',
    status: 'in_stock',
    products: {
      id: 'dcm-std',
      model_no: 'DCM-STD',
      name: 'Aero-Link Module (standard)',
      specs: {
        wifi_tech: '802.11a/n dual radio',
        ap_range_m: 300,
        mesh_range_m: 900,
        battery_wh: 40,
        lora: true,
        gps: true,
        weight_g: 220,
      },
    },
  },
  'DCM-B-0043': {
    unit_id: 'DCM-B-0043',
    status: 'in_stock',
    products: {
      id: 'dcm-std',
      model_no: 'DCM-STD',
      name: 'Aero-Link Module (standard)',
      specs: {
        wifi_tech: '802.11a/n dual radio',
        ap_range_m: 300,
        mesh_range_m: 900,
        battery_wh: 40,
        lora: true,
        gps: true,
        weight_g: 220,
      },
    },
  },
  'DCM-AUX-0011': {
    unit_id: 'DCM-AUX-0011',
    status: 'in_stock',
    products: {
      id: 'dcm-aux',
      model_no: 'DCM-AUX',
      name: 'Aero-Link Aux Module',
      specs: {
        wifi_tech: 'none (aux only)',
        ap_range_m: 0,
        mesh_range_m: 0,
        battery_wh: 0,
        lora: true,
        lora_range_m: 3000,
        gps: true,
        weight_g: 60,
      },
    },
  },
  'DRN-S-0007': {
    unit_id: 'DRN-S-0007',
    status: 'in_stock',
    products: {
      id: 'as5',
      model_no: 'AS5',
      name: 'AeroSync 5 System Drone',
      specs: {
        wifi_tech: '802.11a/n dual radio',
        ap_range_m: 300,
        mesh_range_m: 900,
        battery_wh: 90,
        lora: false,
        gps: true,
        weight_g: 750,
        flight_controller: 'CC3D Open Revolution Mini',
      },
    },
  },
};

export default function UnitLookup() {
  const [searchParams] = useSearchParams();
  const [unitId, setUnitId] = useState('');
  const [result, setResult] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const paramId = searchParams.get('id');
    if (paramId) {
      setUnitId(paramId);
      performLookup(paramId);
    }
  }, [searchParams]);

  async function performLookup(idToLookup) {
    const query = idToLookup.trim();
    if (!query) return;

    setError(null);
    setResult(null);

    // Check demo units first for instant response
    if (DEMO_UNITS[query.toUpperCase()]) {
      setResult(DEMO_UNITS[query.toUpperCase()]);
      return;
    }

    if (!configured) {
      setError(`No unit "${query}" found in offline registry.`);
      return;
    }

    setBusy(true);
    const { data, error } = await supabase
      .from('units')
      .select('unit_id,status,products(id,model_no,name,specs)')
      .eq('unit_id', query)
      .maybeSingle();

    setBusy(false);
    if (error) {
      setError(error.message);
    } else if (!data) {
      setError(`No unit "${query}" found.`);
    } else {
      setResult(data);
    }
  }

  function handleSubmit(e) {
    e.preventDefault();
    performLookup(unitId);
  }

  return (
    <div className="lookup-page">
      <div className="section-header">
        <div className="section-subtitle">HARDWARE REGISTRY</div>
        <h1 className="section-title">Unit Specification Lookup</h1>
        <p className="section-lead">
          Every Aero-Link hardware unit has a unique identifier laser-printed or QR-coded onto its enclosure
          (for example <code>DCM-A-0042</code>, <code>DCM-AUX-0011</code>, or <code>DRN-S-0007</code>).
          Enter the ID below to query factory calibration, operational status, and payload capabilities.
        </p>
      </div>

      <div className="lookup-card standalone">
        <form className="lookup-form" onSubmit={handleSubmit}>
          <input
            value={unitId}
            onChange={(e) => setUnitId(e.target.value)}
            placeholder="e.g. DCM-A-0042 or DRN-S-0007"
            aria-label="Unit ID input"
          />
          <button className="btn btn-primary" disabled={busy || !unitId.trim()}>
            {busy ? 'Querying Registry…' : 'Look Up Specs'}
          </button>
        </form>

        <div className="sample-units-row">
          <span className="sample-label">Try sample units:</span>
          {['DCM-A-0042', 'DCM-AUX-0011', 'DRN-S-0007'].map((sample) => (
            <button
              key={sample}
              type="button"
              className="sample-badge"
              onClick={() => {
                setUnitId(sample);
                performLookup(sample);
              }}
            >
              {sample}
            </button>
          ))}
        </div>
      </div>

      {error && <p className="error lookup-error">{error}</p>}

      {result && (
        <div className="lookup-result-card">
          <div className="result-header">
            <div>
              <div className="result-title">{formatBrandText(result.products?.name)}</div>
              <div className="result-meta">
                <span className="meta-pill">{result.products?.model_no}</span>
                <span className="meta-id">Unit ID: {result.unit_id}</span>
                <span className={`meta-status ${result.status}`}>Status: {result.status}</span>
              </div>
            </div>
            {result.products?.id && (
              <Link className="btn btn-outline" to={`/product/${result.products.id}`}>
                View Product Details &rarr;
              </Link>
            )}
          </div>

          <div className="result-specs">
            <h4>Calibrated Payload Profile (JSON)</h4>
            <pre className="json">
              {JSON.stringify(result.products?.specs || {}, null, 2)}
            </pre>
          </div>
        </div>
      )}
    </div>
  );
}
