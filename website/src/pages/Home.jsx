import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase, configured, formatBrandText } from '../supabase.js';
import { useCart } from '../cart.jsx';
import { heroImg, getProductImage } from '../assets/productImages.js';

// Default product fallback data so the landing page looks complete even if offline
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

export default function Home() {
  const [products, setProducts] = useState(FALLBACK_PRODUCTS);
  const [unitInput, setUnitInput] = useState('');
  const [addedId, setAddedId] = useState(null);
  const cart = useCart();
  const navigate = useNavigate();

  useEffect(() => {
    if (!configured) return;
    supabase
      .from('products')
      .select('id,model_no,name,description,specs,price_usd')
      .order('model_no')
      .then(({ data, error }) => {
        if (!error && data && data.length > 0) {
          setProducts(data);
        }
      });
  }, []);

  function handleQuickLookup(e) {
    e.preventDefault();
    if (unitInput.trim()) {
      navigate(`/lookup?id=${encodeURIComponent(unitInput.trim())}`);
    }
  }

  function handleQuickAdd(e, product) {
    e.preventDefault();
    e.stopPropagation();
    cart.add({
      ...product,
      name: formatBrandText(product.name),
    });
    setAddedId(product.id);
    setTimeout(() => setAddedId(null), 2000);
  }

  return (
    <div className="landing-page">
      {/* Hero Section */}
      <section className="hero-section">
        <div className="hero-content">
          <div className="hero-badge">
            <span className="badge-pulse"></span>
            DISASTER-RESPONSE TACTICAL MESH
          </div>
          <h1 className="hero-title">
            Mission-Critical Airborne Connectivity When Infrastructure Fails
          </h1>
          <p className="hero-lead">
            <strong>Aero-Link</strong> deploys self-healing ad-hoc mesh communication nodes
            aboard autonomous drone swarms. Establishing instant field Wi-Fi access for survivors,
            delay-tolerant data relays for first responders, and emergency LoRa fail-safe beacons.
          </p>
          <div className="hero-actions">
            <Link to="/catalog" className="btn btn-primary btn-large">
              Explore Hardware
            </Link>
            <Link to="/lookup" className="btn btn-secondary btn-large">
              Unit ID Lookup
            </Link>
            <Link to="/cart" className="btn btn-outline btn-large">
              Request Deployment Quote
            </Link>
          </div>
        </div>

        <div className="hero-media-wrapper">
          <div className="hero-media-frame">
            <img
              src={heroImg}
              alt="Aero-Link Drone Network System"
              className="hero-image"
            />
            <div className="hero-overlay-tags">
              <div className="hero-tag">
                <span className="tag-dot cyan"></span>
                <span>Swarm Mesh: 2.4 GHz (900m)</span>
              </div>
              <div className="hero-tag">
                <span className="tag-dot green"></span>
                <span>User AP: 5 GHz (300m)</span>
              </div>
              <div className="hero-tag">
                <span className="tag-dot red"></span>
                <span>Emergency LoRa: 3 km Fallback</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Metrics / Key Capabilities Bar */}
      <section className="metrics-bar">
        <div className="metric-item">
          <div className="metric-val">300 m</div>
          <div className="metric-label">Victim Wi-Fi AP Radius</div>
        </div>
        <div className="metric-divider"></div>
        <div className="metric-item">
          <div className="metric-val">900 m</div>
          <div className="metric-label">Inter-Drone Swarm Link</div>
        </div>
        <div className="metric-divider"></div>
        <div className="metric-item">
          <div className="metric-val">3,000 m</div>
          <div className="metric-label">LoRa Fail-Safe Range</div>
        </div>
        <div className="metric-divider"></div>
        <div className="metric-item">
          <div className="metric-val">100%</div>
          <div className="metric-label">Zero-Infrastructure Needed</div>
        </div>
      </section>

      {/* Featured Hardware Section */}
      <section className="section-featured">
        <div className="section-header">
          <div className="section-subtitle">HARDWARE PLATFORM</div>
          <h2 className="section-title">Field-Proven Disaster Response Modules</h2>
          <p className="section-lead">
            Purpose-engineered modular communication payloads compatible with commercial
            and custom airframes. Ready for instant deployment in search and rescue missions.
          </p>
        </div>

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

        <div className="catalog-cta-wrap">
          <Link to="/catalog" className="btn btn-secondary">
            View Complete Specifications & Catalog &rarr;
          </Link>
        </div>
      </section>

      {/* How It Works Section */}
      <section className="section-workflow">
        <div className="section-header">
          <div className="section-subtitle">OPERATIONAL ARCHITECTURE</div>
          <h2 className="section-title">How Aero-Link Connects Disaster Zones</h2>
          <p className="section-lead">
            A 4-tier delay-tolerant mesh architecture designed to operate autonomously
            without relying on cellular towers or satellite links.
          </p>
        </div>

        <div className="workflow-grid">
          <div className="workflow-step">
            <div className="step-number">01</div>
            <h3 className="step-title">Aerial Swarm Deployment</h3>
            <p className="step-text">
              Drones equipped with Aero-Link modules launch over the affected sector.
              Modules boot in under 60 seconds and auto-discover peers via 2.4 GHz ad-hoc links.
            </p>
          </div>

          <div className="workflow-step">
            <div className="step-number">02</div>
            <h3 className="step-title">Zero-Install Field AP</h3>
            <p className="step-text">
              Each module radiates a 5 GHz Wi-Fi hotspot. Victims and responders connect
              directly on standard smartphones to file distress alerts without downloading any app.
            </p>
          </div>

          <div className="workflow-step">
            <div className="step-number">03</div>
            <h3 className="step-title">Delay-Tolerant Sync</h3>
            <p className="step-text">
              Emergency reports, voice notes, and geotagged imagery replicate peer-to-peer
              across drones in flight whenever they cross paths, ensuring zero data loss.
            </p>
          </div>

          <div className="workflow-step">
            <div className="step-number">04</div>
            <h3 className="step-title">Ground Control Uplink</h3>
            <p className="step-text">
              The Ground Control Centre (GCC) pulls synchronized mission logs and telemetry,
              giving commanders an immediate live tactical picture to coordinate rescues.
            </p>
          </div>
        </div>
      </section>

      {/* Quick Unit Lookup Bar */}
      <section className="section-quick-lookup">
        <div className="lookup-card">
          <div className="lookup-text">
            <h3>Have a Physical Aero-Link Unit?</h3>
            <p>
              Scan or enter the QR-coded Unit ID (e.g. <code>DCM-A-0042</code>, <code>DRN-S-0007</code>)
              to inspect factory calibration, batch telemetry, and hardware specifications.
            </p>
          </div>
          <form className="lookup-form" onSubmit={handleQuickLookup}>
            <input
              type="text"
              placeholder="Enter Unit ID (e.g. DCM-A-0042)"
              value={unitInput}
              onChange={(e) => setUnitInput(e.target.value)}
              aria-label="Unit ID input"
            />
            <button type="submit" className="btn btn-primary" disabled={!unitInput.trim()}>
              Check Specs
            </button>
          </form>
        </div>
      </section>

      {/* Final Call to Action */}
      <section className="section-cta">
        <div className="cta-box">
          <h2>Ready to Equip Your Rescue Squad?</h2>
          <p>
            Build your mission payload quote today. Custom swarm configurations,
            mounting brackets, and GCC integrations available for humanitarian response teams.
          </p>
          <div className="cta-buttons">
            <Link to="/cart" className="btn btn-primary btn-large">
              Request Deployment Quote
            </Link>
            <Link to="/about" className="btn btn-outline btn-large">
              Read Mission Technical Report
            </Link>
          </div>
        </div>
      </section>
    </div>
  );
}
