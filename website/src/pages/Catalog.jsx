import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase, configured } from '../supabase.js';

export default function Catalog() {
  const [products, setProducts] = useState([]);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);

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
        if (error) setError(error.message);
        else setProducts(data || []);
        setLoading(false);
      });
  }, []);

  if (loading) return <p>Loading catalog…</p>;
  if (error) return <p className="error">Could not load products: {error}</p>;
  if (!products.length) return <p>No products yet.</p>;

  return (
    <>
      <h1>Communication modules and drones</h1>
      <p className="lead">
        Attach a module to any drone to extend a disaster-area mesh. Each unit
        ships with a QR-coded ID your ground control app can look up.
      </p>
      <div className="grid">
        {products.map((p) => (
          <Link key={p.id} to={`/product/${p.id}`} className="card">
            <div className="card-title">{p.name}</div>
            <div className="muted">{p.model_no}</div>
            <p>{p.description}</p>
            <div className="specrow">
              {p.specs?.ap_range_m && <span>AP {p.specs.ap_range_m} m</span>}
              {p.specs?.mesh_range_m && (
                <span>mesh {p.specs.mesh_range_m} m</span>
              )}
              {p.specs?.lora && <span>LoRa</span>}
            </div>
            {p.price_usd != null && (
              <div className="price">${p.price_usd}</div>
            )}
          </Link>
        ))}
      </div>
    </>
  );
}
