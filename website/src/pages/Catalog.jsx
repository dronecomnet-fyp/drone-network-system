import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase, configured, formatBrandText } from '../supabase.js';
import { useCart } from '../cart.jsx';
import { getProductImage } from '../assets/productImages.js';

const FALLBACK_PRODUCTS = [
  {
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
  {
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
  {
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
];

export default function Catalog() {
  const [products, setProducts] = useState(FALLBACK_PRODUCTS);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(configured);
  const [addedId, setAddedId] = useState(null);
  const cart = useCart();

  useEffect(() => {
    if (!configured) {
      setLoading(false);
      return;
    }
    supabase
      .from('products')
      .select('id,model_no,name,description,specs,price_usd')
      .order('model_no')
      .then(({ data, error }) => {
        if (error) {
          setError(error.message);
        } else if (data && data.length > 0) {
          setProducts(data);
        }
        setLoading(false);
      });
  }, []);

  function handleQuickAdd(e, p) {
    e.preventDefault();
    e.stopPropagation();
    cart.add({
      ...p,
      name: formatBrandText(p.name),
    });
    setAddedId(p.id);
    setTimeout(() => setAddedId(null), 2000);
  }

  return (
    <div className="catalog-page">
      <div className="section-header">
        <div className="section-subtitle">HARDWARE CATALOG</div>
        <h1 className="section-title">Communication Modules & Drones</h1>
        <p className="section-lead">
          Attach an Aero-Link module to any drone to instantly extend a disaster-area mesh.
          Each manufactured unit ships with a QR-coded Unit ID that your Ground Control Centre
          app can look up and cache for offline missions.
        </p>
      </div>

      {loading && <p className="loading-text">Loading catalog…</p>}
      {error && <p className="error">Could not load remote products: {error}. Showing cached catalogue.</p>}

      <div className="product-grid">
        {products.map((p) => {
          const imgSrc = getProductImage(p.model_no, p.name);
          const formattedName = formatBrandText(p.name);
          const formattedDesc = formatBrandText(p.description);

          return (
            <div key={p.id} className="product-card">
              <Link to={`/product/${p.id}`} className="card-image-link">
                <div className="card-image-container">
                  <img src={imgSrc} alt={formattedName} className="card-image" />
                  <span className="model-badge">{p.model_no}</span>
                </div>
              </Link>

              <div className="card-content">
                <h3 className="card-title">
                  <Link to={`/product/${p.id}`}>{formattedName}</Link>
                </h3>
                <p className="card-desc">{formattedDesc}</p>

                <div className="spec-pills">
                  {p.specs?.ap_range_m > 0 && (
                    <span className="spec-pill">AP {p.specs.ap_range_m}m</span>
                  )}
                  {p.specs?.mesh_range_m > 0 && (
                    <span className="spec-pill">Mesh {p.specs.mesh_range_m}m</span>
                  )}
                  {p.specs?.lora && (
                    <span className="spec-pill highlight">LoRa Beacon</span>
                  )}
                  {p.specs?.gps && <span className="spec-pill">GPS</span>}
                  {p.specs?.battery_wh > 0 && (
                    <span className="spec-pill">{p.specs.battery_wh}Wh</span>
                  )}
                  {p.specs?.weight_g > 0 && (
                    <span className="spec-pill">{p.specs.weight_g}g</span>
                  )}
                </div>

                <div className="card-footer">
                  {p.price_usd != null && (
                    <div className="price-tag">${p.price_usd}</div>
                  )}
                  <div className="card-actions">
                    <Link to={`/product/${p.id}`} className="btn btn-outline btn-small">
                      Specs
                    </Link>
                    <button
                      className="btn btn-primary btn-small"
                      onClick={(e) => handleQuickAdd(e, p)}
                    >
                      {addedId === p.id ? 'Added ✓' : 'Add to Quote'}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
