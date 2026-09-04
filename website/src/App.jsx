import { Link, NavLink, Route, Routes } from 'react-router-dom';
import { CartProvider, useCart } from './cart.jsx';
import { configured } from './supabase.js';
import Home from './pages/Home.jsx';
import Catalog from './pages/Catalog.jsx';
import ProductDetail from './pages/ProductDetail.jsx';
import UnitLookup from './pages/UnitLookup.jsx';
import Cart from './pages/Cart.jsx';
import About from './pages/About.jsx';
import { logoImg } from './assets/productImages.js';

function Nav() {
  const cart = useCart();
  return (
    <header className="nav">
      <Link to="/" className="brand">
        <img src={logoImg} alt="Aero-Link Logo" className="brand-logo" />
        <span className="brand-text">Aero-Link</span>
      </Link>
      <nav>
        <NavLink to="/" end>
          Home
        </NavLink>
        <NavLink to="/catalog">
          Catalog
        </NavLink>
        <NavLink to="/lookup">
          Unit Lookup
        </NavLink>
        <NavLink to="/about">
          About
        </NavLink>
        <NavLink to="/cart" className="nav-quote-btn">
          Quote ({cart.count})
        </NavLink>
      </nav>
    </header>
  );
}

export default function App() {
  return (
    <CartProvider>
      <Nav />
      {!configured && (
        <div className="banner">
          Backend not configured. Copy <code>.env.example</code> to{' '}
          <code>.env.local</code> and set your Supabase URL and anon key.
        </div>
      )}
      <main className="container">
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/catalog" element={<Catalog />} />
          <Route path="/product/:id" element={<ProductDetail />} />
          <Route path="/lookup" element={<UnitLookup />} />
          <Route path="/cart" element={<Cart />} />
          <Route path="/about" element={<About />} />
        </Routes>
      </main>
      <footer className="footer">
        <div className="footer-content">
          <div className="footer-brand">
            <img src={logoImg} alt="Aero-Link" className="footer-logo" />
            <span className="footer-brand-name">Aero-Link</span>
          </div>
          <p className="footer-desc">
            Disaster-mesh airborne communications platform. Modular Wi-Fi access points,
            delay-tolerant swarm relays, and LoRa telemetry for autonomous disaster response.
          </p>
          <div className="footer-links">
            <Link to="/">Home</Link> &middot;{' '}
            <Link to="/catalog">Catalog</Link> &middot;{' '}
            <Link to="/lookup">Unit Lookup</Link> &middot;{' '}
            <Link to="/about">About System</Link> &middot;{' '}
            <Link to="/cart">Request Quote</Link>
          </div>
          <div className="footer-copy">
            &copy; {new Date().getFullYear()} Aero-Link FYP Engineering Project. Designed for Humanitarian Disaster Mesh Networking.
          </div>
        </div>
      </footer>
    </CartProvider>
  );
}
