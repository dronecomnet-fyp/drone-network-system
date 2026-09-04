import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { supabase, configured, formatBrandText } from '../supabase.js';
import { useCart } from '../cart.jsx';
import { getProductImage } from '../assets/productImages.js';

// Human labels + units for the spec keys we know about. Unknown keys still
// render (raw key), so adding a spec never needs a code change.
const SPEC_LABELS = {
  wifi_tech: ['Wi-Fi Standard', ''],
  ap_range_m: ['Survivor Access Point Range', 'm'],
  mesh_range_m: ['Ad-Hoc Swarm Mesh Range', 'm'],
  battery_wh: ['Battery Capacity', 'Wh'],
  lora: ['LoRa Fallback Beacon', ''],
  lora_range_m: ['LoRa Emergency Range', 'm'],
  weight_g: ['All-Up Payload Weight', 'g'],
  gps: ['Integrated GPS', ''],
  channels: ['Radio Channels', ''],
  flight_controller: ['Flight Controller', ''],
  motors_kv: ['Motor Rating', 'KV'],
};

const FALLBACK_PRODUCTS_MAP = {
  'dcm-std': {
    id: 'dcm-std',
    model_no: 'DCM-STD',
    name: 'Aero-Link Module (standard)',
    description:
      'The core disaster-mesh comm module: Raspberry Pi with a 5 GHz user access point and a 2.4 GHz ad-hoc mesh radio. Attaches to any drone.',
    specs: {
      wifi_tech: '802.11a/n dual radio',
      ap_range_m: 300,
      mesh_range_m: 900,
      battery_wh: 40,
      lora: true,
      gps: true,
      weight_g: 220,
    },
    price_usd: 480,
  },
  'dcm-aux': {
    id: 'dcm-aux',
    model_no: 'DCM-AUX',
    name: 'Aero-Link Aux Module',
    description:
      'Sensor and fallback module: INA3221 battery monitoring, GPS, and a LoRa fallback beacon that keeps the drone locatable if the Pi fails.',
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
    price_usd: 140,
  },
  'as5': {
    id: 'as5',
    model_no: 'AS5',
    name: 'AeroSync 5 System Drone',
    description:
      'A comm module plus a CC3D flight controller the ground control centre commands over MAVLink: the one drone in the fleet that can be flown and repositioned from the ground.',
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
    price_usd: 1650,
  },
};

function formatSpecValue(key, value, unit) {
  if (typeof value === 'boolean') {
    return value ? 'Enabled / Yes' : 'No';
  }
  if (value === 0) {
    if (key === 'battery_wh') return 'Host-powered (Draws from drone)';
    if (key === 'ap_range_m' || key === 'mesh_range_m') return 'N/A (Auxiliary sensor node)';
  }
  return unit ? `${value} ${unit}` : `${value}`;
}

function SpecTable({ specs }) {
  const entries = Object.entries(specs || {});
  if (!entries.length) return null;
  return (
    <table className="specs">
      <tbody>
        {entries.map(([k, v]) => {
          const [label, unit] = SPEC_LABELS[k] || [k.replace(/_/g, ' '), ''];
          return (
            <tr key={k}>
              <th>{label}</th>
              <td>{formatSpecValue(k, v, unit)}</td>
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
  const [viewMode, setViewMode] = useState('photo'); // 'photo' | '3d'

  useEffect(() => {
    // Check fallback first for instant render
    if (FALLBACK_PRODUCTS_MAP[id]) {
      setProduct(FALLBACK_PRODUCTS_MAP[id]);
    }

    if (!configured) return;
    supabase
      .from('products')
      .select('*')
      .eq('id', id)
      .maybeSingle()
      .then(({ data, error }) => {
        if (error) {
          if (!product) setError(error.message);
        } else if (data) {
          setProduct(data);
        }
      });

    supabase
      .from('units')
      .select('unit_id,status')
      .eq('product_id', id)
      .order('unit_id')
      .then(({ data }) => setUnits(data || []));
  }, [id]);

  if (error && !product) return <p className="error">Could not load product: {error}</p>;
  if (!product) return <p className="loading-text">Loading product details…</p>;

  const model3d = product.specs?.model_3d_url || product.model_3d_url;
  const imgSrc = getProductImage(product.model_no, product.name);
  const formattedName = formatBrandText(product.name);
  const formattedDesc = formatBrandText(product.description);

  return (
    <div className="product-detail-page">
      <Link to="/catalog" className="back-link">
        &larr; Back to Catalog
      </Link>

      <div className="detail">
        <div className="viewer-column">
          <div className="viewer-card">
            {model3d && (
              <div className="viewer-tabs">
                <button
                  className={`tab-btn ${viewMode === 'photo' ? 'active' : ''}`}
                  onClick={() => setViewMode('photo')}
                >
                  Product Photo
                </button>
                <button
                  className={`tab-btn ${viewMode === '3d' ? 'active' : ''}`}
                  onClick={() => setViewMode('3d')}
                >
                  Interactive 3D
                </button>
              </div>
            )}

            {viewMode === '3d' && model3d ? (
              <div className="viewer-3d">
                <model-viewer
                  src={model3d}
                  alt={formattedName}
                  camera-controls
                  auto-rotate
                  shadow-intensity="1"
                  style={{ width: '100%', height: '420px' }}
                ></model-viewer>
              </div>
            ) : (
              <div className="viewer-photo">
                <img
                  src={imgSrc}
                  alt={formattedName}
                  className="product-detail-image"
                />
                <span className="viewer-model-badge">{product.model_no}</span>
              </div>
            )}
          </div>
        </div>

        <div className="detail-body">
          <div className="detail-header">
            <span className="badge-category">TACTICAL PAYLOAD</span>
            <h1 className="detail-title">{formattedName}</h1>
            <div className="detail-model-tag">Model: {product.model_no}</div>
          </div>

          <p className="detail-description">{formattedDesc}</p>

          <div className="specs-section">
            <h3>Technical Specifications</h3>
            <SpecTable specs={product.specs} />
          </div>

          <div className="price-and-order">
            {product.price_usd != null && (
              <div className="price big">${product.price_usd} USD</div>
            )}
            <div className="order-actions">
              <button
                className="btn btn-primary btn-large"
                onClick={() => {
                  cart.add({ ...product, name: formattedName });
                  setAdded(true);
                  setTimeout(() => setAdded(false), 2500);
                }}
              >
                {added ? 'Added to Quote ✓' : 'Add to Quote Request'}
              </button>
              {added && <span className="ok-badge">Item added to your quote</span>}
            </div>
          </div>

          {units.length > 0 && (
            <div className="units-section">
              <h3>Manufactured Units in Batch</h3>
              <p className="muted">
                Factory calibrated and tracked in the Aero-Link registry for Ground Control spec fetching:
              </p>
              <div className="units">
                {units.map((u) => (
                  <span key={u.unit_id} className={`unit ${u.status}`}>
                    {u.unit_id} &middot; {u.status.replace('_', ' ')}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
