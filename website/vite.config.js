import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Relative base so the built site works under any path (GitHub Pages
// project sites live under /<repo>/). model-viewer is a web component, so
// it is left un-optimized by esbuild.
export default defineConfig({
  base: './',
  plugins: [react()],
});
