import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { supabase, configured } from '../supabase.js';
import { useCart } from '../cart.jsx';

// Human labels + units for the spec keys we know about. Unknown keys still
// render (raw key), so adding a spec never needs a code change.
const SPEC_LABELS = {
  wifi_tech: ['Wi-Fi', ''],
  ap_range_m: ['User AP range', 'm'],
  mesh_range_m: ['Mesh range', 'm'],
  battery_wh: ['Battery', 'Wh'],
  lora: ['LoRa fallback', ''],
  weight_g: ['Weight', 'g'],
  gps: ['GPS', ''],
  channels: ['Channels', ''],
};

function SpecTable({ specs }) {
  const entries = Object.entries(specs || {});
  if (!entries.length) return null;
  return (
    <table className="specs">
      <tbody>
        {entries.map(([k, v]) => {
          const [label, unit] = SPEC_LABELS[k] || [k, ''];
          const value = typeof v === 'boolean' ? (v ? 'yes' : 'no') : v;
          return (
            <tr key={k}>
              <th>{label}</th>
              <td>
                {value}
                {unit ? ` ${unit}` : ''}
              </td>
            </tr>
          );
        })}
      </tbody>
    </table>
  );
}

export default function ProductDetail() {
  const { id } = useParams();
  const cart = useCart();
  const [product, setProduct] = useState(null);
  const [units, setUnits] = useState([]);
  const [error, setError] = useState(null);
  const [added, setAdded] = useState(false);

  useEffect(() => {
    if (!configured) return;
    supabase
      .from('products')
      .select('*')
      .eq('id', id)
      .single()
      .then(({ data, error }) => {
        if (error) setError(error.message);
        else setProduct(data);
      });
    supabase
      .from('units')
      .select('unit_id,status')
      .eq('product_id', id)
      .order('unit_id')
      .then(({ data }) => setUnits(data || []));
  }, [id]);

  if (error) return <p className="error">Could not load product: {error}</p>;
  if (!product) return <p>Loading…</p>;

  const model3d = product.specs?.model_3d_url || product.model_3d_url;

  return (
    <>
      <Link to="/">&larr; catalog</Link>
      <div className="detail">
        <div className="viewer">
          {model3d ? (
            <model-viewer
              src={model3d}
              alt={product.name}
              camera-controls
              auto-rotate
              shadow-intensity="1"
              style={{ width: '100%', height: '380px' }}
            ></model-viewer>
          ) : (
            <div className="viewer-empty">
              No 3D model uploaded for this product yet.
            </div>
          )}
        </div>
        <div className="detail-body">
          <h1>{product.name}</h1>
          <div className="muted">{product.model_no}</div>
          <p>{product.description}</p>
          <SpecTable specs={product.specs} />
          {product.price_usd != null && (
            <div className="price big">${product.price_usd}</div>
          )}
          <button
            className="btn"
            onClick={() => {
              cart.add(product);
              setAdded(true);
            }}
          >
            Add to quote
          </button>
          {added && <span className="ok"> added</span>}
          {units.length > 0 && (
            <>
              <h3>Units in this batch</h3>
              <div className="units">
                {units.map((u) => (
                  <span key={u.unit_id} className={`unit ${u.status}`}>
                    {u.unit_id}
                  </span>
                ))}
              </div>
            </>
          )}
        </div>
      </div>
    </>
  );
}
