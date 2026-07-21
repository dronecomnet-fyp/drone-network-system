import { Link, NavLink, Route, Routes } from 'react-router-dom';
import { CartProvider, useCart } from './cart.jsx';
import { configured } from './supabase.js';
import Catalog from './pages/Catalog.jsx';
import ProductDetail from './pages/ProductDetail.jsx';
import UnitLookup from './pages/UnitLookup.jsx';
import Cart from './pages/Cart.jsx';
import About from './pages/About.jsx';

function Nav() {
  const cart = useCart();
  return (
    <header className="nav">
      <Link to="/" className="brand">
        DroneComNet
      </Link>
      <nav>
        <NavLink to="/" end>
          Catalog
        </NavLink>
        <NavLink to="/lookup">Unit lookup</NavLink>
        <NavLink to="/about">About</NavLink>
        <NavLink to="/cart">Quote ({cart.count})</NavLink>
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
          <Route path="/" element={<Catalog />} />
          <Route path="/product/:id" element={<ProductDetail />} />
          <Route path="/lookup" element={<UnitLookup />} />
          <Route path="/cart" element={<Cart />} />
          <Route path="/about" element={<About />} />
        </Routes>
      </main>
      <footer className="footer">
        DroneComNet FYP prototype. Modules and the AeroSync system drone for
        disaster-area delay-tolerant mesh networking.
      </footer>
    </CartProvider>
  );
}
