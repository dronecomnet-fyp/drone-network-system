# Offline maps for the GCC (pre-mission step)

There is no internet at a deployment site, so the GCC renders map tiles
from a local MBTiles file prepared BEFORE the mission. This is a headline
feature (file 04): do not skip it, and do not rely on any online tile
source in the field.

## What to produce

One `.mbtiles` file (SQLite container of raster tiles) covering the
operation region at zoom levels 10 to 16. As a sizing guide, a district-
sized area at those zooms is typically tens to a few hundred MB; verify
the actual size for your region when you build it (do not quote these
numbers in the report without measuring; project rule 1).

## How to build it (pick one)

Option A, QGIS (GUI, easiest to reproduce):
1. Install QGIS (free). Add an OSM basemap layer (XYZ tiles).
2. Processing Toolbox > Raster tools > "Generate XYZ tiles (MBTiles)".
3. Set the extent to the operation region, zooms 10-16, output .mbtiles.
4. Respect the tile source's usage policy: for OpenStreetMap-based
   sources, bulk downloading from the public osm.org tile servers is
   against their policy; use a provider that permits offline export or
   render your own tiles from an OSM extract.

Option B, from an OSM extract (fully offline pipeline, more setup):
1. Download the Sri Lanka extract (for example from Geofabrik).
2. Render raster tiles with TileMill/mod_tile or convert through
   tilemaker/planetiler to vector MBTiles, then pre-render raster.
3. Package as .mbtiles.

Record in docs/test_log.md which option was used, the region bounds,
zoom range, file size, and the source and its license/usage terms.

## Loading in the GCC

Settings tab > Offline map > "Load .mbtiles", pick the file. The map
falls back to a blank grid with a warning banner when no file is loaded;
pins still render either way.

## Verification (feeds file 07 T-checks)

With the laptop's WiFi OFF (or joined to a drone AP, which has no
internet), the Map tab must render tiles for the whole operation region
at zooms 10-16 and show live message pins on top (file 04 acceptance 1).
