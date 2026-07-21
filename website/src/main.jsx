import React from 'react';
import { createRoot } from 'react-dom/client';
import { HashRouter } from 'react-router-dom';
// model-viewer registers the <model-viewer> web component globally.
import '@google/model-viewer';
import App from './App.jsx';
import './styles.css';

// HashRouter (not BrowserRouter) so deep links and refresh work on GitHub
// Pages without server-side rewrites.
createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <HashRouter>
      <App />
    </HashRouter>
  </React.StrictMode>,
);
