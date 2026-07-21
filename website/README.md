# DroneComNet product site (M7c)

A small React (Vite) site for the disaster-mesh comm modules and the AeroSync
system drone. Products, specs, and per-unit IDs live in Supabase; the ground
control app (`gcc_app`) fetches a unit's specs by ID from the same backend and
caches them into a mission so the field stays offline.

- Static frontend, deployable to GitHub Pages (or any static host).
- Real hosted backend + database: Supabase (PostgREST + row-level security).
- 3D product view via `<model-viewer>` (GLB from Supabase Storage).
- Cart is a request-a-quote flow (writes one `quotes` row); no payments.

## One-time backend setup

1. Create a free Supabase project (supabase.com).
2. Apply the schema + seed: open **SQL editor**, paste
   [`supabase/schema.sql`](supabase/schema.sql), run it. (Or apply it with the
   Supabase MCP / CLI.) This creates `products`, `units`, `quotes`, the RLS
   policies, and seeds the real prototype catalogue.
3. (Optional 3D) Generate a placeholder model and host it:
   ```sh
   pip install trimesh numpy
   python tools/make_placeholder_glb.py
   ```
   Create a **public** Storage bucket (e.g. `models`), upload `drone.glb`, and
   set a product's `specs.model_3d_url` (or `products.model_3d_url`) to its
   public URL. Or upload a real GLB.

## Run / build

```sh
cp .env.example .env.local     # fill in VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
npm install
npm run dev                    # local dev
npm run build                  # static build into dist/
```

Find the URL and anon key in Supabase: **Project Settings -> API**. The anon
key is public by design; RLS is the access control. Never put the
`service_role` key in this project.

## Deploy to GitHub Pages

A workflow is provided at
[`.github/workflows/deploy-website.yml`](../.github/workflows/deploy-website.yml).
Add the two values as repository **Actions secrets** (`VITE_SUPABASE_URL`,
`VITE_SUPABASE_ANON_KEY`) and enable Pages (Source: GitHub Actions). The build
uses a relative base path, so it works under a project subpath.

## How the ground control app uses this

`gcc_app` calls `GET {url}/rest/v1/units?unit_id=eq.<ID>&select=...,products(*)`
with the anon key (see `gcc_app/lib/services/product_api.dart`). Enter the same
URL and anon key in the app's Settings; then the Mission tab's "fetch specs"
button pulls a unit's specs and caches them into the mission file.
