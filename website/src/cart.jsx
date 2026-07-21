import { createContext, useContext, useEffect, useState } from 'react';

// A tiny cart kept in localStorage. This is a request-a-quote flow, not a
// real store: "checkout" writes a row to the quotes table.
const CartContext = createContext(null);

export function CartProvider({ children }) {
  const [items, setItems] = useState(() => {
    try {
      return JSON.parse(localStorage.getItem('cart') || '[]');
    } catch {
      return [];
    }
  });

  useEffect(() => {
    localStorage.setItem('cart', JSON.stringify(items));
  }, [items]);

  const add = (product, qty = 1) =>
    setItems((prev) => {
      const found = prev.find((i) => i.id === product.id);
      if (found) {
        return prev.map((i) =>
          i.id === product.id ? { ...i, qty: i.qty + qty } : i,
        );
      }
      return [
        ...prev,
        { id: product.id, model_no: product.model_no, name: product.name, qty },
      ];
    });

  const remove = (id) => setItems((prev) => prev.filter((i) => i.id !== id));
  const clear = () => setItems([]);
  const count = items.reduce((n, i) => n + i.qty, 0);

  return (
    <CartContext.Provider value={{ items, add, remove, clear, count }}>
      {children}
    </CartContext.Provider>
  );
}

export const useCart = () => useContext(CartContext);
