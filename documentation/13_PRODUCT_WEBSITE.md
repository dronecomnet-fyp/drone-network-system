# 13 The Product Website

The product website presents the hardware as a product line and, more usefully
for the operation, gives every manufactured unit a unique id whose specs the GCC
can look up. It is a React (Vite) site backed by Supabase, and it lives in
`website/`. It is deployed as a static site on GitHub Pages with Supabase as the
real hosted backend.

## Why it exists

Two reasons, one presentational and one functional:

- It is the public face of the project: a catalogue, per-product specs, a 3D
  model view, and a request-a-quote flow. It makes the hardware feel like a real
  product for the thesis and demo.
- It is the **spec source** the GCC uses. When the operator adds a drone or
  module by its unit id, the GCC fetches that unit's specs from this backend and
  caches them into the mission (chapter 12), so coverage circles and the fleet
  battery model use real numbers.

## The stack

- **Frontend**: React + Vite, with `@google/model-viewer` for the GLB 3D view.
  Pages: catalogue, product detail (3D + spec table + configurator), unit lookup,
  request-a-quote, about. `HashRouter` so deep links work on GitHub Pages without
  server rewrites. A relative base path so it works under a project subpath.
- **Backend**: Supabase (managed Postgres + PostgREST + row-level security). No
  server code to maintain; the site talks to Supabase directly with the public
  anon key.

## The database

`website/supabase/schema.sql` (run once in the Supabase SQL editor) creates:

- `products` (model_no, name, description, a `specs` JSON blob with
  ap_range_m, mesh_range_m, battery_wh, lora, weight_g, and so on, a 3D model
  URL, and a price);
- `units` (a text unit_id primary key like `DRN-S-0007`, a product foreign key,
  status, manufacture date);
- `quotes` (contact and items JSON, for the request-a-quote flow).

It also enables **row-level security** with these policies, which are the actual
access control:

- anonymous users can **read** products and units;
- anonymous users can **insert** a quote but cannot read, update, or delete any
  quote;
- nothing else.

The seed data is the real prototype catalogue: the DroneComNet standard module,
the aux module, and the AeroSync 5 system drone, with unit rows whose ids mirror
the physical hardware (for example `DRN-S-0007` is the system drone, and
`DCM-A-0042`/`DCM-B-0043` are comm modules).

## On the anon key being public

The Supabase anon key is designed to be public: it ships in every client bundle
of every Supabase app. Row-level security, not key secrecy, is what protects the
data. So the anon key is safe to embed in the site and the GCC defaults, and it
is committed. The **service_role key is a real secret and is never committed**.
This distinction is important for the next team: do not treat the anon key as a
leak, and never put the service_role key anywhere in the repository.

## How the GCC uses it

`gcc_app/lib/services/product_api.dart` calls the Supabase PostgREST endpoint:

```
GET {SUPABASE_URL}/rest/v1/units?unit_id=eq.<ID>&select=unit_id,status,products(model_no,name,specs)
```

with the anon key in the `apikey` and `Authorization` headers. It returns the
unit joined to its product, and the GCC caches the specs into the mission file so
they resolve offline afterwards. This is online-only (the HQ phase); offline, a
previously-fetched unit still resolves and a never-fetched one is entered
manually.

## Deploying it

- Build config and secrets: the public Supabase URL and anon key are baked into
  `website/src/supabase.js` as defaults (overridable with a local `.env.local`
  for a different project), so the built site works without wiring Actions
  secrets.
- **GitHub Pages must use the "GitHub Actions" source**, not "deploy from a
  branch". A branch deploy just serves the repo files and cannot build a Vite
  app (it would serve the README). The committed workflow
  `.github/workflows/deploy-website.yml` builds `website/` and publishes `dist/`.
- The live site (this project's instance) is at
  `https://dronecomnet-fyp.github.io/drone-network-system/`.

## Optional 3D model

`website/tools/make_placeholder_glb.py` generates a simple placeholder
quadcopter GLB with `trimesh`, for the product 3D view until a real scanned or
CAD model is uploaded to a public Supabase Storage bucket and referenced from a
product's `model_3d_url`.

## Where the code lives

```
website/
  src/                       React app (App, pages, cart, supabase client)
  supabase/schema.sql        tables, RLS, and the seed catalogue
  tools/make_placeholder_glb.py   placeholder 3D model generator
  README.md                  setup + deploy steps
  .github/workflows/deploy-website.yml   (repo root) Pages build+deploy
gcc_app/lib/services/product_api.dart    the GCC spec fetch
```
