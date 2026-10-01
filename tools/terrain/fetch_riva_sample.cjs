// Riva del Garda sample: 40.96 km of real data + 199.68 km context, aligned in UTM 32N.
// Phases: node tools/terrain/fetch_riva_sample.cjs fetch | build | all | context | photo | buildings | lidar | relief
// Requires `npm i --no-save sharp` in tools/. Download cache in tools/tiles/riva/,
// outputs in terrain/source/riva_sample/ (both git-ignored). Godot import:
// tools/terrain/build_riva_sample.gd.
//
// Sources (attribution required):
//  - DTM/DBM LiDAR PAT 2014/2018 0.5 m, Provincia autonoma di Trento, CC BY 4.0
//  - Copernicus DEM GLO-30, © DLR/Airbus, provided under COPERNICUS by the EU and ESA
//  - ESA WorldCover 10 m 2021 v200, © ESA, CC BY 4.0
//  - OpenStreetMap, © OpenStreetMap contributors, ODbL
//  - Ortofoto PAT 2015 RGB 20 cm, Provincia autonoma di Trento, CC BY 4.0
//  - Sentinel-2 cloudless 2016 (s2maps.eu) by EOX IT Services GmbH, CC BY 4.0
//    (contains modified Copernicus Sentinel data 2016)
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');
const { execFileSync } = require('child_process');
const assert = require('assert');
sharp.cache(false);

const ROOT = path.resolve(__dirname, '../..');
const TILES = path.join(ROOT, 'tools', 'tiles', 'riva');
const OUT = path.join(ROOT, 'terrain', 'source', 'riva_sample');
fs.mkdirSync(TILES, { recursive: true });
fs.writeFileSync(path.join(TILES, '.gdignore'), ''); // downloads, not project assets
fs.mkdirSync(OUT, { recursive: true });

// World origin (UTM 32N / ETRS89, <1 m apart here). World x = E - CE, world z = CN - N.
const CE = 645120, CN = 5082880;
const CORE_HALF = 20480, CORE_STEP = 4, CORE_N = 10240; // Terrain3D vertices
const MASK_STEP = 8, MASK_N = 5120;                      // land use masks over the core
// Context DEM on the Copernicus 30 m grid; its points stay those of the former 61 km context (x = k * 30 m),
// so the core edge band, blended into it, needs no rebuild. 6656 cells: 13 x 13 mesh chunks of 512.
const CTX_HALF = 99840, CTX_STEP = 30, CTX_N = 6657;
const COVER_STEP = 80, COVER_N = 2 * CTX_HALF / COVER_STEP + 1; // WorldCover rock/snow/water over the context
// Terrain albedo photos: 1 m around Riva (buildings), 2.5 m over the core (16384 px), 8 m over 61 km,
// 25.6 m (Sentinel-2) over the whole context.
const PHOTO_CORE_HALF = 5120, PHOTO_CORE_STEP = 1, PHOTO_WIDE_STEP = 2.5, PHOTO_CTX_HALF = 30720, PHOTO_CTX_STEP = 8;
const PHOTO_FAR_STEP = 25.6;
const BUILDINGS_HALF = 5120; // ponytail: buildings around Riva only, one mesh; chunk it before going wider
const LAKE_LEVEL = 65.0, LAKE_MAX_DEPTH = 300.0;
const EDGE_BLEND = 400.0;  // core -> context DEM over the outer band of the core
const FINE_BLEND = 300.0;  // DTMs (PAT LiDAR, Veneto/Lombardia 5 m) -> Copernicus where they end
const SEAM_BLEND = 100.0;  // PAT LiDAR -> regional 5 m DTMs across the Trentino border

// ---------- UTM zone 32 ----------
const A = 6378137, F = 1 / 298.257223563, K0 = 0.9996, E2 = 2 * F - F * F, EP2 = E2 / (1 - E2);
const LON0 = 9 * Math.PI / 180;
// Transverse Mercator (UTM 32 by default; the Veneto DTM is on the RDN2008 zone 12 grid).
function toTm(lat, lon, lon0 = 9, k0 = K0, fe = 500000) {
  const la = lat * Math.PI / 180, lo = lon * Math.PI / 180;
  const N = A / Math.sqrt(1 - E2 * Math.sin(la) ** 2);
  const T = Math.tan(la) ** 2, C = EP2 * Math.cos(la) ** 2, Aa = Math.cos(la) * (lo - lon0 * Math.PI / 180);
  const M = A * ((1 - E2 / 4 - 3 * E2 * E2 / 64 - 5 * E2 ** 3 / 256) * la
    - (3 * E2 / 8 + 3 * E2 * E2 / 32 + 45 * E2 ** 3 / 1024) * Math.sin(2 * la)
    + (15 * E2 * E2 / 256 + 45 * E2 ** 3 / 1024) * Math.sin(4 * la) - (35 * E2 ** 3 / 3072) * Math.sin(6 * la));
  return [k0 * N * (Aa + (1 - T + C) * Aa ** 3 / 6 + (5 - 18 * T + T * T + 72 * C - 58 * EP2) * Aa ** 5 / 120) + fe,
    k0 * (M + N * Math.tan(la) * (Aa * Aa / 2 + (5 - T + 9 * C + 4 * C * C) * Aa ** 4 / 24
      + (61 - 58 * T + T * T + 600 * C - 330 * EP2) * Aa ** 6 / 720))];
}
const toUtm = (lat, lon) => toTm(lat, lon);
function toLatLon(x, y) {
  const e1 = (1 - Math.sqrt(1 - E2)) / (1 + Math.sqrt(1 - E2));
  x -= 500000;
  const mu = (y / K0) / (A * (1 - E2 / 4 - 3 * E2 * E2 / 64 - 5 * E2 ** 3 / 256));
  const p1 = mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * Math.sin(2 * mu) + (21 * e1 * e1 / 16 - 55 * e1 ** 4 / 32) * Math.sin(4 * mu)
    + (151 * e1 ** 3 / 96) * Math.sin(6 * mu);
  const N1 = A / Math.sqrt(1 - E2 * Math.sin(p1) ** 2), T1 = Math.tan(p1) ** 2, C1 = EP2 * Math.cos(p1) ** 2;
  const R1 = A * (1 - E2) / (1 - E2 * Math.sin(p1) ** 2) ** 1.5, D = x / (N1 * K0);
  const lat = p1 - (N1 * Math.tan(p1) / R1) * (D * D / 2 - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * EP2) * D ** 4 / 24
    + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1 - 252 * EP2 - 3 * C1 * C1) * D ** 6 / 720);
  const lon = LON0 + (D - (1 + 2 * T1 + C1) * D ** 3 / 6 + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1 + 8 * EP2 + 24 * T1 * T1) * D ** 5 / 120) / Math.cos(p1);
  return [lat * 180 / Math.PI, lon * 180 / Math.PI];
}

// ---------- fetch with cache/retry ----------
async function get(url, file, opts = {}) {
  const target = path.join(TILES, file);
  if (fs.existsSync(target) && fs.statSync(target).size > 0) return fs.readFileSync(target);
  for (let i = 1; i <= 4; i++) {
    try {
      const r = await fetch(url, { ...opts, headers: { 'User-Agent': 'aero-demons-terrain-sample/1.0', Accept: '*/*', ...(opts.headers || {}) },
        signal: AbortSignal.timeout(900000) });
      if (!r.ok) throw new Error(`HTTP ${r.status} ${(await r.text().catch(() => '')).slice(0, 200)}`);
      const b = Buffer.from(await r.arrayBuffer());
      fs.writeFileSync(target, b);
      console.log(`  ${file} ${(b.length / 1048576).toFixed(1)} MB`);
      return b;
    } catch (e) {
      console.log(`  ${file} attempt ${i}: ${e.message}`);
      if (i === 4) throw e;
      await new Promise(r => setTimeout(r, 15000 * i));
    }
  }
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ---------- fetch phase ----------
const STEM = 'https://siat.provincia.tn.it';
// kind: dtm (terrain, in lidar/) or dbm (terrain + buildings, in lidar_dbm/); want filters the 500 m tiles.
async function fetchLidar(kind = 'dtm', want = () => true) {
  // Tile index from the province WFS; download through the public STEM merge service.
  const e0 = CE - CORE_HALF, n0 = CN - CORE_HALF;
  const name = kind === 'dtm' ? 'lidar' : `lidar_${kind}`;
  const index = await get(`${STEM}/geoserver/stem/wfs?service=WFS&version=2.0.0&request=GetFeature`
    + `&typeNames=stem:inqlid2014_${kind}_asc&outputFormat=application/json`
    + `&bbox=${e0 - 1},${n0 - 1},${e0 + 2 * CORE_HALF + 1},${n0 + 2 * CORE_HALF + 1},urn:ogc:def:crs:EPSG::25832`, `${name}_index.json`);
  const features = JSON.parse(index).features.filter(want);
  const ext = kind === 'dtm' ? '.f32' : '.asc'; // the DTM is kept as 2 m block means (shrinkDtm)
  const missing = features.filter(f => !fs.existsSync(path.join(TILES, name, `${f.properties.n_tavola}${ext}`)));
  console.log(`LiDAR ${kind}: ${features.length} tiles, ${missing.length} to download`);
  fs.mkdirSync(path.join(TILES, name), { recursive: true });
  const dir = path.join(TILES, name);
  for (let i = 0; i < missing.length; i += 80) {
    const batch = missing.slice(i, i + 80), zip = path.join(TILES, `${name}_batch_${i}.zip`);
    // The merge service now and then serves a truncated zip: ask for the batch again.
    for (let attempt = 1; ; attempt++) {
      const r = await fetch(`${STEM}/stem/services/merge`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ files: batch.map(f => f.properties.location) }) });
      const job = await r.json();
      if (!job.success) throw new Error('STEM merge failed ' + JSON.stringify(job));
      for (;;) {
        const info = await (await fetch(`${STEM}/stem/services/file/info?id=${job.id}&token=${job.token}`)).json();
        if (info.state !== 0) break;
        await sleep(5000);
      }
      fs.rmSync(zip, { force: true });
      await get(`${STEM}/stem/services/file?id=${job.id}&token=${job.token}`, path.basename(zip));
      try {
        execFileSync('unzip', ['-o', '-q', zip, '-d', dir]);
        for (const inner of fs.readdirSync(dir).filter(f => f.endsWith('.zip'))) {
          execFileSync('unzip', ['-o', '-q', path.join(dir, inner), '-d', dir]);
          fs.rmSync(path.join(dir, inner));
        }
        break;
      } catch (e) {
        for (const inner of fs.readdirSync(dir).filter(f => f.endsWith('.zip'))) fs.rmSync(path.join(dir, inner));
        if (attempt === 3) throw e;
        console.log(`  LiDAR ${kind} batch ${i / 80 + 1}: bad zip, again`);
      }
    }
    for (const asc of fs.readdirSync(dir).filter(f => /_(DTM|DBM)\.asc$/.test(f)))
      fs.renameSync(path.join(dir, asc), path.join(dir, asc.replace(/_(DTM|DBM)\.asc$/, '.asc')));
    if (kind === 'dtm') shrinkDtm(dir);
    fs.rmSync(zip);
    console.log(`  LiDAR ${kind} batch ${i / 80 + 1}/${Math.ceil(missing.length / 80)} done`);
  }
  return features;
}

function contextLatLonBounds(half = CTX_HALF) {
  let s = 90, n = -90, w = 180, e = -180;
  for (const [dx, dy] of [[-1, -1], [1, -1], [-1, 1], [1, 1], [0, -1], [0, 1], [-1, 0], [1, 0]]) {
    const [la, lo] = toLatLon(CE + dx * half, CN + dy * half);
    s = Math.min(s, la); n = Math.max(n, la); w = Math.min(w, lo); e = Math.max(e, lo);
  }
  return { s: s - 0.01, n: n + 0.01, w: w - 0.01, e: e + 0.01 };
}

async function fetchCopernicus() {
  const b = contextLatLonBounds();
  for (let lat = Math.floor(b.s); lat <= Math.floor(b.n); lat++)
    for (let lon = Math.floor(b.w); lon <= Math.floor(b.e); lon++) {
      const name = `Copernicus_DSM_COG_10_N${lat}_00_E${String(lon).padStart(3, '0')}_00_DEM`;
      await get(`https://copernicus-dem-30m.s3.amazonaws.com/${name}/${name}.tif`, `${name}.tif`);
    }
}

// WorldCover comes in 3 x 3 degree tiles named by their south-west corner.
function worldCoverTiles(b) {
  const tiles = [];
  for (let lat = Math.floor(b.s / 3) * 3; lat <= b.n; lat += 3)
    for (let lon = Math.floor(b.w / 3) * 3; lon <= b.e; lon += 3)
      tiles.push({ lat, lon, file: `ESA_WorldCover_10m_2021_v200_N${lat}E${String(lon).padStart(3, '0')}_Map.tif` });
  return tiles;
}
async function fetchWorldCover() {
  for (const { file } of worldCoverTiles(contextLatLonBounds()))
    await get(`https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/${file}`, file);
}

function utmLatLonBounds(e0, n0, e1, n1) {
  const c = [[e0, n0], [e1, n0], [e0, n1], [e1, n1]].map(([e, n]) => toLatLon(e, n));
  return { s: Math.min(...c.map(p => p[0])), n: Math.max(...c.map(p => p[0])), w: Math.min(...c.map(p => p[1])), e: Math.max(...c.map(p => p[1])) };
}

// Overpass in 4 x 4 tiles of the core (a 40 km query is ~1 GB); forEachOsm drops the duplicates.
const OSM_TILES = 4;
async function fetchOsm() {
  const span = 2 * CORE_HALF / OSM_TILES, margin = 300;
  fs.mkdirSync(path.join(TILES, 'osm'), { recursive: true });
  for (let ty = 0; ty < OSM_TILES; ty++) for (let tx = 0; tx < OSM_TILES; tx++) {
    const e0 = CE - CORE_HALF + tx * span, n1 = CN + CORE_HALF - ty * span;
    const b = utmLatLonBounds(e0 - margin, n1 - span - margin, e0 + span + margin, n1 + margin);
    const bbox = `${b.s},${b.w},${b.n},${b.e}`;
    const query = `[out:json][timeout:300];(
      way["landuse"](${bbox});relation["landuse"](${bbox});
      way["natural"](${bbox});relation["natural"](${bbox});
      way["leisure"](${bbox});way["aeroway"](${bbox});
      way["building"](${bbox});relation["building"](${bbox});
      way["highway"](${bbox});way["railway"="rail"](${bbox});
      way["waterway"](${bbox});relation["water"](${bbox});
    );out geom;`;
    await get('https://overpass-api.de/api/interpreter', `osm/${tx}_${ty}.json`,
      { method: 'POST', body: 'data=' + encodeURIComponent(query), headers: { 'Content-Type': 'application/x-www-form-urlencoded' } });
  }
}
function forEachOsm(fn) {
  const seen = new Set();
  for (let ty = 0; ty < OSM_TILES; ty++) for (let tx = 0; tx < OSM_TILES; tx++)
    for (const el of JSON.parse(fs.readFileSync(path.join(TILES, 'osm', `${tx}_${ty}.json`), 'utf8')).elements) {
      const key = el.type[0] + el.id;
      if (!seen.has(key)) { seen.add(key); fn(el); }
    }
}

// Regional DTMs outside Trentino. Lombardia: DTM 5 m (2015, CC BY 4.0) from the region's ImageServer,
// resampled by the server onto the Terrain3D vertices. Veneto: DTM LiDAR 5 m (IODL 2.0), 2 km ASCII tiles
// on the RDN2008 zone 12 grid.
const LOMBARDIA = 'https://www.cartografia.servizirl.it/arcgis2/rest/services/BaseMap/DTM5_RL_img/ImageServer/exportImage';
const LOM_TILE = 2048; // vertices per export (server limit 15000 x 4100)
async function fetchLombardia() {
  fs.mkdirSync(path.join(TILES, 'lombardia'), { recursive: true });
  const span = LOM_TILE * CORE_STEP;
  for (let ty = 0; ty < CORE_N / LOM_TILE; ty++) for (let tx = 0; tx < CORE_N / LOM_TILE; tx++) {
    // Pixel centres on the vertices: x = -CORE_HALF + c * CORE_STEP, rows from the north edge.
    const e0 = CE - CORE_HALF + tx * span - CORE_STEP / 2, n1 = CN + CORE_HALF - ty * span + CORE_STEP / 2;
    await get(`${LOMBARDIA}?bbox=${e0},${n1 - span},${e0 + span},${n1}&bboxSR=32632&imageSR=32632&size=${LOM_TILE},${LOM_TILE}`
      + '&format=tiff&pixelType=F32&interpolation=RSP_BilinearInterpolation&f=image', `lombardia/${tx}_${ty}.tif`);
  }
}
const VENETO_GS = 'https://idt2-geoserver.regione.veneto.it/geoserver/ows';
const VENETO_TM = [12, 1, 3000000]; // RDN2008 / zone 12: central meridian, scale 1, false easting (fit on Copernicus)
async function fetchVeneto() {
  const index = await get(`${VENETO_GS}?service=WFS&version=2.0.0&request=GetFeature&typeNames=rv:c0101071_lidar5m`
    + `&outputFormat=application/json&srsName=urn:ogc:def:crs:EPSG::25832`
    + `&bbox=${CE - CORE_HALF},${CN - CORE_HALF},${CE + CORE_HALF},${CN + CORE_HALF},urn:ogc:def:crs:EPSG::25832`, 'veneto_index.json');
  const dir = path.join(TILES, 'veneto');
  fs.mkdirSync(dir, { recursive: true });
  for (const { properties: p } of JSON.parse(index).features) {
    if (fs.existsSync(path.join(dir, `${p.nome}.asc`))) continue;
    await get(`https://idt2.regione.veneto.it/idt/download/layerDownload/downloadDtmLidar5?dataDtmLidarId=${p.id_pol}`, `veneto/${p.nome}.zip`);
    execFileSync('unzip', ['-o', '-q', path.join(dir, `${p.nome}.zip`), '-d', dir]);
    fs.rmSync(path.join(dir, `${p.nome}.zip`));
  }
  console.log(`Veneto DTM: ${JSON.parse(index).features.length} tiles`);
}

// Web Mercator tiles of the EOX 2016 mosaic (CC BY 4.0; later years are non-commercial).
// z13 (~13 m) under the 8 m context photo, z12 (~27 m) for the far photo.
const SAT_Z = 13, SAT_FAR_Z = 12;
function mercTile(lat, lon, z) {
  const n = 2 ** z, la = lat * Math.PI / 180;
  return [(lon + 180) / 360 * n, (1 - Math.log(Math.tan(la) + 1 / Math.cos(la)) / Math.PI) / 2 * n];
}
function satRange(z, half) {
  const b = contextLatLonBounds(half);
  const [x0, y0] = mercTile(b.n, b.w, z), [x1, y1] = mercTile(b.s, b.e, z);
  return { x0: Math.floor(x0), y0: Math.floor(y0), x1: Math.floor(x1), y1: Math.floor(y1) };
}
async function fetchSatellite(z, half) {
  const r = satRange(z, half);
  fs.mkdirSync(path.join(TILES, 'sat'), { recursive: true });
  let count = 0;
  for (let y = r.y0; y <= r.y1; y++)
    for (let x = r.x0; x <= r.x1; x++) {
      await get(`https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/g/${z}/${y}/${x}.jpg`, `sat/${z}_${x}_${y}.jpg`);
      count++;
    }
  console.log(`Satellite z${z}: ${count} tiles`);
}

// Orthophotos through WMS, already in our UTM grid; outside their region the services return white.
// pat: PAT 2015 (20 cm RGB). agea: AGEA 2024 as served by Regione Veneto (CC BY 4.0, AGEA).
const ORTHO_TILE = 2048;
const ORTHO_WMS = {
  pat: `${STEM}/geoserver/stem/wms?service=WMS&version=1.3.0&request=GetMap&layers=ecw-rgb-2015&styles=&crs=EPSG:25832`,
  agea: `${VENETO_GS}?service=WMS&version=1.3.0&request=GetMap&layers=rv:ortofoto_agea_2024&styles=&crs=EPSG:32632`,
};
const orthoGrid = (half, step) => ({ span: ORTHO_TILE * step, count: Math.ceil(2 * half / (ORTHO_TILE * step)) });
async function fetchOrtho(dir, half, step, source = 'pat') {
  const { span, count } = orthoGrid(half, step);
  fs.mkdirSync(path.join(TILES, dir), { recursive: true });
  for (let ty = 0; ty < count; ty++) for (let tx = 0; tx < count; tx++) {
    const e0 = CE - half + tx * span, n1 = CN + half - ty * span;
    await get(`${ORTHO_WMS[source]}&bbox=${e0},${n1 - span},${e0 + span},${n1}&width=${ORTHO_TILE}&height=${ORTHO_TILE}&format=image/jpeg`,
      `${dir}/${tx}_${ty}.jpg`);
  }
}

// ---------- build phase ----------
async function loadCopernicus() {
  const tiles = {};
  for (const f of fs.readdirSync(TILES).filter(f => f.startsWith('Copernicus_DSM'))) {
    const m = f.match(/N(\d+)_00_E(\d+)_00/);
    const img = sharp(path.join(TILES, f), { limitInputPixels: false });
    // libvips presents the single-band DEM as RGB: keep the first band.
    const { data, info } = await img.extractChannel(0).raw({ depth: 'float' }).toBuffer({ resolveWithObject: true });
    assert(info.channels === 1 && info.depth === 'float', 'Unexpected Copernicus layout');
    tiles[`${+m[1]}_${+m[2]}`] = { w: info.width, h: info.height, px: new Float32Array(data.buffer, data.byteOffset, info.width * info.height) };
  }
  // Pixel-is-point: row 0 is the northern edge, column 0 the western edge.
  return (lat, lon) => {
    const t = tiles[`${Math.floor(lat)}_${Math.floor(lon)}`];
    if (!t) return NaN;
    const fx = (lon - Math.floor(lon)) * (t.w), fy = (Math.floor(lat) + 1 - lat) * (t.h);
    const x = Math.min(Math.floor(fx), t.w - 2), y = Math.min(Math.floor(fy), t.h - 2), ax = fx - x, ay = fy - y;
    const p = (i, j) => t.px[j * t.w + i];
    return (p(x, y) * (1 - ax) + p(x + 1, y) * ax) * (1 - ay) + (p(x, y + 1) * (1 - ax) + p(x + 1, y + 1) * ax) * ay;
  };
}

// Classes inside the lat/lon box b, every `scale`-th 10 m pixel (nearest).
async function loadWorldCover(b, scale = 1) {
  const palette = { 10: [0, 100, 0], 20: [255, 187, 34], 30: [255, 255, 76], 40: [240, 150, 255], 50: [250, 0, 0],
    60: [180, 180, 180], 70: [240, 240, 240], 80: [0, 100, 200], 90: [0, 150, 160], 95: [0, 207, 117], 100: [250, 230, 160] };
  const byColour = new Map(Object.entries(palette).map(([k, c]) => [(c[0] << 16) | (c[1] << 8) | c[2], +k]));
  const tiles = {};
  for (const t of worldCoverTiles(b)) {
    const px = v => Math.max(0, Math.min(36000, v));
    const left = px(Math.floor((b.w - t.lon) * 12000)), right = px(Math.ceil((b.e - t.lon) * 12000));
    const top = px(Math.floor((t.lat + 3 - b.n) * 12000)), bottom = px(Math.ceil((t.lat + 3 - b.s) * 12000));
    const width = right - left, height = bottom - top;
    if (width <= 0 || height <= 0) continue;
    const w = Math.ceil(width / scale), h = Math.ceil(height / scale);
    // The map is a paletted TIFF: libvips expands it to the official class colours.
    const { data, info } = await sharp(path.join(TILES, t.file), { limitInputPixels: false })
      .extract({ left, top, width, height }).resize(w, h, { kernel: 'nearest' }).raw().toBuffer({ resolveWithObject: true });
    const classes = new Uint8Array(w * h);
    for (let i = 0; i < classes.length; i++) {
      const o = i * info.channels;
      classes[i] = byColour.get((data[o] << 16) | (data[o + 1] << 8) | data[o + 2]) || 0;
    }
    tiles[`${t.lat}_${t.lon}`] = { ...t, left, top, sx: w / width, sy: h / height, w, h, classes };
  }
  return (lat, lon) => {
    const t = tiles[`${Math.floor(lat / 3) * 3}_${Math.floor(lon / 3) * 3}`];
    if (!t) return 0;
    const x = Math.floor(((lon - t.lon) * 12000 - t.left) * t.sx), y = Math.floor(((t.lat + 3 - lat) * 12000 - t.top) * t.sy);
    return x < 0 || y < 0 || x >= t.w || y >= t.h ? 0 : t.classes[y * t.w + x];
  };
}

async function loadSatellite(z, half) {
  const r = satRange(z, half), w = (r.x1 - r.x0 + 1) * 256, h = (r.y1 - r.y0 + 1) * 256;
  const composites = [];
  for (let y = r.y0; y <= r.y1; y++)
    for (let x = r.x0; x <= r.x1; x++)
      composites.push({ input: path.join(TILES, 'sat', `${z}_${x}_${y}.jpg`), left: (x - r.x0) * 256, top: (y - r.y0) * 256 });
  const { data } = await sharp({ create: { width: w, height: h, channels: 3, background: '#000' }, limitInputPixels: false })
    .composite(composites).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  return (lat, lon) => {
    const [fx, fy] = mercTile(lat, lon, z);
    const x = (fx - r.x0) * 256 - 0.5, y = (fy - r.y0) * 256 - 0.5;
    const ix = Math.max(0, Math.min(w - 2, Math.floor(x))), iy = Math.max(0, Math.min(h - 2, Math.floor(y)));
    const ax = x - ix, ay = y - iy, out = [0, 0, 0];
    for (let c = 0; c < 3; c++) {
      const p = (i, j) => data[(j * w + i) * 3 + c];
      out[c] = (p(ix, iy) * (1 - ax) + p(ix + 1, iy) * ax) * (1 - ay) + (p(ix, iy + 1) * (1 - ax) + p(ix + 1, iy + 1) * ax) * ay;
    }
    return out;
  };
}

// ESRI ASCII grid: values row-major from the north edge (NaN = no data), x0/y0 = south-west cell centre.
function readAsc(file) {
  const buf = fs.readFileSync(file), len = buf.length;
  const header = {};
  let p = 0;
  for (let line = 0; line < 6; line++) {
    const end = buf.indexOf(10, p);
    const [k, v] = buf.toString('latin1', p, end).trim().split(/\s+/);
    header[k.toLowerCase()] = +v;
    p = end + 1;
  }
  const cell = header.cellsize, n = header.ncols * header.nrows, values = new Float32Array(n).fill(NaN);
  // Hand-rolled number scan: the 40 km DTM is ~40 GB of text.
  for (let i = 0; i < n && p < len;) {
    if (buf[p] <= 32) { p++; continue; }
    const start = p;
    let v = 0, scale = 0, plain = true;
    for (; p < len && buf[p] > 32; p++) {
      const c = buf[p];
      if (c >= 48 && c <= 57) { v = v * 10 + c - 48; scale *= 10; } else if (c === 46 && !scale) scale = 1;
      else if (c !== 45 || p !== start) plain = false;
    }
    if (plain) { v = scale ? v / scale : v; if (buf[start] === 45) v = -v; } else v = parseFloat(buf.toString('latin1', start, p));
    values[i++] = v === header.nodata_value ? NaN : v;
  }
  return { cols: header.ncols, rows: header.nrows, cell, x0: header.xllcenter ?? header.xllcorner + cell / 2,
    y0: header.yllcenter ?? header.yllcorner + cell / 2, values };
}

// 500 m PAT DTM tiles become 2 m block means (250 x 250 from the north-west corner, NaN when under half
// covered) next to the .asc, which is dropped: 250 KB instead of 6.5 MB per tile.
const DTM_TILE = 500, DTM_BLOCK = 2, DTM_BLOCKS = DTM_TILE / DTM_BLOCK;
function shrinkDtm(dir) {
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.asc'))) {
    const { cols, rows, cell, x0, y0, values } = readAsc(path.join(dir, f));
    const e0 = Math.floor((x0 - cell / 2) / DTM_TILE) * DTM_TILE, n1 = Math.floor((y0 - cell / 2) / DTM_TILE) * DTM_TILE + DTM_TILE;
    const sum = new Float32Array(DTM_BLOCKS * DTM_BLOCKS), count = new Uint8Array(sum.length);
    for (let r = 0; r < rows; r++) {
      const bj = Math.floor((n1 - (y0 + (rows - 1 - r) * cell)) / DTM_BLOCK);
      if (bj < 0 || bj >= DTM_BLOCKS) continue;
      for (let c = 0; c < cols; c++) {
        const v = values[r * cols + c], bi = Math.floor((x0 + c * cell - e0) / DTM_BLOCK);
        if (Number.isNaN(v) || bi < 0 || bi >= DTM_BLOCKS) continue;
        sum[bj * DTM_BLOCKS + bi] += v; count[bj * DTM_BLOCKS + bi]++;
      }
    }
    const half = (DTM_BLOCK / cell) ** 2 / 2;
    for (let i = 0; i < sum.length; i++) sum[i] = count[i] >= half ? sum[i] / count[i] : NaN;
    fs.writeFileSync(path.join(dir, f.replace(/\.asc$/, '.f32')), Buffer.from(sum.buffer));
    fs.rmSync(path.join(dir, f));
  }
}

// PAT LiDAR at the Terrain3D vertices: each vertex V averages the 2 m blocks centred at V +- 1 m (shrinkDtm).
function loadLidar() {
  const sum = new Float32Array(CORE_N * CORE_N), count = new Uint8Array(CORE_N * CORE_N);
  const west = CE - CORE_HALF, north = CN + CORE_HALF;
  let tiles = 0;
  for (const { properties: p } of JSON.parse(fs.readFileSync(path.join(TILES, 'lidar_index.json'))).features) {
    const file = path.join(TILES, 'lidar', `${p.n_tavola}.f32`);
    if (!fs.existsSync(file)) continue;
    const b = fs.readFileSync(file), blocks = new Float32Array(b.buffer.slice(b.byteOffset, b.byteOffset + b.length));
    tiles++;
    for (let bj = 0; bj < DTM_BLOCKS; bj++) {
      const vr = Math.round((north - (p.y_min + DTM_TILE - (bj + 0.5) * DTM_BLOCK)) / CORE_STEP);
      if (vr < 0 || vr >= CORE_N) continue;
      for (let bi = 0; bi < DTM_BLOCKS; bi++) {
        const v = blocks[bj * DTM_BLOCKS + bi], vc = Math.round((p.x_min + (bi + 0.5) * DTM_BLOCK - west) / CORE_STEP);
        if (Number.isNaN(v) || vc < 0 || vc >= CORE_N) continue;
        sum[vr * CORE_N + vc] += v; count[vr * CORE_N + vc]++;
      }
    }
  }
  for (let i = 0; i < sum.length; i++) sum[i] = count[i] >= 3 ? sum[i] / count[i] : NaN;
  console.log(`PAT LiDAR: ${tiles} tiles`);
  return sum;
}

// Lombardia DTM at the vertices (the exports are already on the vertex grid).
async function loadLombardia() {
  const out = new Float32Array(CORE_N * CORE_N).fill(NaN), tiles = CORE_N / LOM_TILE;
  for (let ty = 0; ty < tiles; ty++) for (let tx = 0; tx < tiles; tx++) {
    const { data, info } = await sharp(path.join(TILES, 'lombardia', `${tx}_${ty}.tif`), { limitInputPixels: false })
      .extractChannel(0).raw({ depth: 'float' }).toBuffer({ resolveWithObject: true });
    assert(info.width === LOM_TILE && info.height === LOM_TILE, 'Unexpected Lombardia tile');
    const px = new Float32Array(data.buffer, data.byteOffset, LOM_TILE * LOM_TILE);
    for (let y = 0; y < LOM_TILE; y++) for (let x = 0; x < LOM_TILE; x++) {
      const v = px[y * LOM_TILE + x];
      if (v > -1000) out[(ty * LOM_TILE + y) * CORE_N + tx * LOM_TILE + x] = v; // no data: -3.4e38
    }
  }
  return out;
}

// Veneto DTM at the vertices inside its tiles (bilinear on the zone 12 grid).
function loadVeneto() {
  const out = new Float32Array(CORE_N * CORE_N).fill(NaN), dir = path.join(TILES, 'veneto');
  const tiles = new Map();
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.asc'))) {
    const g = readAsc(path.join(dir, f)), span = g.cols * g.cell;
    tiles.set(`${Math.round((g.x0 - g.cell / 2) / span)}_${Math.round((g.y0 - g.cell / 2) / span)}`, { ...g, span });
  }
  if (!tiles.size) return out;
  const span = tiles.values().next().value.span;
  // Vertex window: the tile footprints from the WFS index (in UTM 32).
  let e0 = Infinity, n0 = Infinity, e1 = -Infinity, n1 = -Infinity;
  for (const f of JSON.parse(fs.readFileSync(path.join(TILES, 'veneto_index.json'))).features)
    for (const [e, n] of f.geometry.coordinates.flat(2)) { e0 = Math.min(e0, e); e1 = Math.max(e1, e); n0 = Math.min(n0, n); n1 = Math.max(n1, n); }
  const c0 = Math.max(0, Math.floor((e0 - CE + CORE_HALF) / CORE_STEP)), c1 = Math.min(CORE_N - 1, Math.ceil((e1 - CE + CORE_HALF) / CORE_STEP));
  const r0 = Math.max(0, Math.floor((CN + CORE_HALF - n1) / CORE_STEP)), r1 = Math.min(CORE_N - 1, Math.ceil((CN + CORE_HALF - n0) / CORE_STEP));
  for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) {
    const [x, y] = toTm(...utmLL(CE - CORE_HALF + c * CORE_STEP, CN + CORE_HALF - r * CORE_STEP), ...VENETO_TM);
    const g = tiles.get(`${Math.floor(x / span)}_${Math.floor(y / span)}`);
    if (!g) continue;
    const fx = Math.max(0, Math.min(g.cols - 1.001, (x - g.x0) / g.cell)), fy = Math.max(0, Math.min(g.rows - 1.001, (g.y0 + (g.rows - 1) * g.cell - y) / g.cell));
    const ix = Math.floor(fx), iy = Math.floor(fy), ax = fx - ix, ay = fy - iy, p = (i, j) => g.values[(iy + j) * g.cols + ix + i];
    out[r * CORE_N + c] = (p(0, 0) * (1 - ax) + p(1, 0) * ax) * (1 - ay) + (p(0, 1) * (1 - ax) + p(1, 1) * ax) * ay; // NaN near gaps
  }
  return out;
}

// Chamfer distance (in cells) to the nearest cell where inside[] is false.
function distanceInside(inside, w, h) {
  const d = new Float32Array(w * h);
  for (let i = 0; i < d.length; i++) d[i] = inside[i] ? 1e9 : 0;
  const D1 = 1, D2 = Math.SQRT2;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x; if (!d[i]) continue;
    if (x > 0) d[i] = Math.min(d[i], d[i - 1] + D1);
    if (y > 0) { d[i] = Math.min(d[i], d[i - w] + D1); if (x > 0) d[i] = Math.min(d[i], d[i - w - 1] + D2); if (x < w - 1) d[i] = Math.min(d[i], d[i - w + 1] + D2); }
  }
  for (let y = h - 1; y >= 0; y--) for (let x = w - 1; x >= 0; x--) {
    const i = y * w + x; if (!d[i]) continue;
    if (x < w - 1) d[i] = Math.min(d[i], d[i + 1] + D1);
    if (y < h - 1) { d[i] = Math.min(d[i], d[i + w] + D1); if (x < w - 1) d[i] = Math.min(d[i], d[i + w + 1] + D2); if (x > 0) d[i] = Math.min(d[i], d[i + w - 1] + D2); }
  }
  return d;
}

function boxBlur(src, w, h, channels, radius) {
  // Three box passes ~ gaussian. Separable, edge-clamped.
  let a = Float32Array.from(src), b = new Float32Array(src.length);
  for (let pass = 0; pass < 3; pass++) for (const horizontal of [true, false]) {
    const len = horizontal ? w : h, lines = horizontal ? h : w;
    for (let l = 0; l < lines; l++) for (let c = 0; c < channels; c++) {
      const idx = k => ((horizontal ? l * w + k : k * w + l) * channels + c);
      let acc = 0;
      for (let k = -radius; k <= radius; k++) acc += a[idx(Math.max(0, Math.min(len - 1, k)))];
      for (let k = 0; k < len; k++) {
        b[idx(k)] = acc / (2 * radius + 1);
        acc += a[idx(Math.min(len - 1, k + radius + 1))] - a[idx(Math.max(0, k - radius))];
      }
    }
    [a, b] = [b, a];
  }
  return a;
}

// ---------- OSM rasterisation (SVG, pixel = MASK_STEP metres) ----------
// Items keep their rings/lines as flat Float32Arrays of mask pixels (x0, y0, x1, y1, ...) and a pixel box.
function osmGeometry() {
  const west = CE - CORE_HALF, north = CN + CORE_HALF;
  const px = g => { const [e, n] = toUtm(g.lat, g.lon); return [(e - west) / MASK_STEP, (north - n) / MASK_STEP]; };
  const rings = (members) => {
    // Join open member ways end to end into closed rings.
    const open = members.map(m => m.geometry.map(px));
    const closed = [];
    while (open.length) {
      let ring = open.pop();
      for (let guard = 0; guard < 10000 && open.length; guard++) {
        const end = ring[ring.length - 1];
        const near = (p, q) => Math.abs(p[0] - q[0]) < 1e-6 && Math.abs(p[1] - q[1]) < 1e-6;
        if (near(end, ring[0])) break;
        const k = open.findIndex(w => near(w[0], end) || near(w[w.length - 1], end));
        if (k < 0) break;
        let next = open.splice(k, 1)[0];
        if (!near(next[0], end)) next = next.reverse();
        ring = ring.concat(next.slice(1));
      }
      closed.push(ring);
    }
    return closed;
  };
  const flat = pts => Float32Array.from(pts.flat());
  const items = [];
  forEachOsm(el => {
    const tags = el.tags || {};
    let item;
    if (el.type === 'way' && el.geometry) {
      const pts = flat(el.geometry.map(px));
      const isClosed = el.nodes && el.nodes[0] === el.nodes[el.nodes.length - 1];
      item = { tags, rings: isClosed ? [pts] : [], line: isClosed ? null : pts, id: el.id, closedLine: isClosed ? pts : null };
    } else if (el.type === 'relation' && el.members) {
      const members = el.members.filter(m => m.type === 'way' && m.geometry && (m.role === 'outer' || m.role === 'inner' || m.role === ''));
      item = { tags, rings: rings(members).map(flat), line: null, id: el.id };
    } else return;
    const box = [Infinity, Infinity, -Infinity, -Infinity];
    for (const r of item.rings.concat(item.line ? [item.line] : []))
      for (let i = 0; i < r.length; i += 2) {
        box[0] = Math.min(box[0], r[i]); box[1] = Math.min(box[1], r[i + 1]); box[2] = Math.max(box[2], r[i]); box[3] = Math.max(box[3], r[i + 1]);
      }
    if (box[2] < 0 || box[3] < 0 || box[0] > MASK_N || box[1] > MASK_N) return;
    item.box = box;
    items.push(item);
  });
  return items;
}
const coords = r => { let s = ''; for (let i = 0; i < r.length; i += 2) s += (i ? 'L' : '') + r[i].toFixed(2) + ',' + r[i + 1].toFixed(2); return s; };
const pathOf = rings => rings.map(r => 'M' + coords(r) + 'Z').join('');
const lineOf = pts => 'M' + coords(pts);
// Rasterise [item, item => svg] entries one chunk at a time: the SVG of the whole core would not fit a string.
const MASK_CHUNKS = 4;
async function renderMask(entries, crisp = false) {
  const out = Buffer.alloc(MASK_N * MASK_N), size = MASK_N / MASK_CHUNKS, pad = 8;
  for (let cy = 0; cy < MASK_CHUNKS; cy++) for (let cx = 0; cx < MASK_CHUNKS; cx++) {
    const x0 = cx * size, y0 = cy * size;
    const body = entries.filter(([i]) => i.box[2] >= x0 - pad && i.box[0] <= x0 + size + pad && i.box[3] >= y0 - pad && i.box[1] <= y0 + size + pad)
      .map(([i, svg]) => svg(i)).join('');
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="${x0} ${y0} ${size} ${size}"`
      + `${crisp ? ' shape-rendering="crispEdges"' : ''}><rect x="${x0}" y="${y0}" width="${size}" height="${size}" fill="#000"/>${body}</svg>`;
    const data = await sharp(Buffer.from(svg), { limitInputPixels: false, density: 72 }).removeAlpha().extractChannel(0).raw().toBuffer();
    for (let r = 0; r < size; r++) data.copy(out, (y0 + r) * MASK_N + x0, r * size, (r + 1) * size);
  }
  return out;
}
const fills = (items, test, fill = () => '#fff') => items.filter(i => i.rings.length && test(i))
  .map(i => [i, i => `<path d="${pathOf(i.rings)}" fill="${fill(i)}" fill-rule="evenodd"/>`]);
const strokes = (items, width, cap = 'round') => items.filter(i => i.line || i.closedLine).map(i => [i, i =>
  `<path d="${lineOf(i.line || i.closedLine)}" stroke="#fff" stroke-width="${width(i) / MASK_STEP}" stroke-linecap="${cap}" stroke-linejoin="round" fill="none"/>`]);
const roadWidth = { motorway: 22, trunk: 16, primary: 12, secondary: 10, tertiary: 8, unclassified: 6, residential: 6,
  living_street: 5, service: 4, motorway_link: 8, trunk_link: 8, primary_link: 7, secondary_link: 7, tertiary_link: 6,
  pedestrian: 5, track: 3, cycleway: 2.5 };

function hash01(n) { const x = Math.sin(n * 12.9898) * 43758.5453; return x - Math.floor(x); }
// Row direction of a parcel: its longest edge, 0..1 for 0..pi.
function parcelAngle(ring) {
  let best = 0, angle = 0;
  for (let i = 2; i < ring.length; i += 2) {
    const dx = ring[i] - ring[i - 2], dy = ring[i + 1] - ring[i - 1], l = dx * dx + dy * dy;
    if (l > best) { best = l; angle = Math.atan2(dy, dx); }
  }
  return ((angle % Math.PI) + Math.PI) % Math.PI / Math.PI;
}

const utmLL = (e, n) => toLatLon(e, n);
const png = (name, buf, n, channels = 4) => sharp(buf, { raw: { width: n, height: n, channels } }).png().toFile(path.join(OUT, name));
const raw = (name, arr) => fs.writeFileSync(path.join(OUT, name), Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength));

// Terrain albedo. Context (8 m over 61 km): PAT orthophoto, Sentinel-2 matched to it outside Trentino. Far
// (25.6 m, the whole context): Sentinel-2 with the same grade, the context photo in its centre. Wide (2.5 m, the
// Terrain3D core): orthophoto, AGEA 2024 in Veneto, the context photo elsewhere. Core (1 m around Riva, under
// the buildings): orthophoto, the wide photo elsewhere.
async function loadOrtho(dir, half, step) {
  const { count } = orthoGrid(half, step), n = 2 * half / step, size = count * ORTHO_TILE;
  const composites = [];
  for (let ty = 0; ty < count; ty++) for (let tx = 0; tx < count; tx++)
    composites.push({ input: path.join(TILES, dir, `${tx}_${ty}.jpg`), left: tx * ORTHO_TILE, top: ty * ORTHO_TILE });
  const mosaic = await sharp({ create: { width: size, height: size, channels: 3, background: '#fff' }, limitInputPixels: false })
    .composite(composites).removeAlpha().raw().toBuffer();
  return sharp(mosaic, { raw: { width: size, height: size, channels: 3 }, limitInputPixels: false })
    .extract({ left: 0, top: 0, width: n, height: n }).raw().toBuffer();
}
// 255 inside the orthophoto, ramping to 0 over ~2 sigma at its edge (white or black = no data: the AGEA
// service answers black outside its coverage).
async function photoWeight(rgb, n, sigma) {
  const valid = Buffer.alloc(n * n);
  for (let i = 0; i < n * n; i++) {
    const r = rgb[i * 3], g = rgb[i * 3 + 1], b = rgb[i * 3 + 2];
    valid[i] = Math.min(r, g, b) < 248 && Math.max(r, g, b) > 6 ? 255 : 0;
  }
  const blur = await sharp(valid, { raw: { width: n, height: n, channels: 1 }, limitInputPixels: false }).blur(sigma)
    .extractChannel(0).raw().toBuffer(); // libvips blurs to sRGB: keep one band
  const w = new Uint8Array(n * n);
  for (let i = 0; i < n * n; i++) w[i] = valid[i] ? Math.round(255 * Math.max(0, Math.min(1, (blur[i] - 128) / 120))) : 0; // the blur tops out near 253
  return w;
}
// Per-channel gain/offset giving src the mean and deviation of ref where weight is full.
function colourMatch(src, ref, weight) {
  const gain = [], offset = [];
  for (let ch = 0; ch < 3; ch++) {
    let k = 0, so = 0, so2 = 0, ss = 0, ss2 = 0;
    for (let i = 0; i < weight.length; i++) {
      if (weight[i] < 255) continue;
      const o = ref[i * 3 + ch], s = src[i * 3 + ch];
      k++; so += o; so2 += o * o; ss += s; ss2 += s * s;
    }
    assert(k > 1000, 'No overlap to match colours on');
    const mo = so / k, ms = ss / k, dO = Math.sqrt(so2 / k - mo * mo), dS = Math.sqrt(ss2 / k - ms * ms);
    gain[ch] = dO / dS; offset[ch] = mo - ms * gain[ch];
  }
  console.log('  colour match gain', gain.map(g => g.toFixed(3)), 'offset', offset.map(o => o.toFixed(1)));
  return { gain, offset };
}
// dst = mix(dst, graded src, weight / 255), in place.
function blendPhoto(dst, src, weight, grade = { gain: [1, 1, 1], offset: [0, 0, 0] }) {
  for (let i = 0; i < weight.length; i++) {
    const w = weight[i] / 255;
    if (!w) continue;
    for (let ch = 0; ch < 3; ch++) {
      const v = Math.max(0, Math.min(255, src[i * 3 + ch] * grade.gain[ch] + grade.offset[ch]));
      dst[i * 3 + ch] = Math.round(dst[i * 3 + ch] + (v - dst[i * 3 + ch]) * w);
    }
  }
}
// The centre [-half, half] of a square photo covering [-srcHalf, srcHalf], resized to n pixels.
function cropPhoto(src, srcHalf, srcStep, half, n) {
  const sn = Math.round(2 * srcHalf / srcStep), off = Math.round((srcHalf - half) / srcStep), size = Math.round(2 * half / srcStep);
  return sharp(src, { raw: { width: sn, height: sn, channels: 3 }, limitInputPixels: false })
    .extract({ left: off, top: off, width: size, height: size }).resize(n, n, { kernel: 'cubic' }).raw().toBuffer();
}
const jpeg = (name, buf, n) => sharp(buf, { raw: { width: n, height: n, channels: 3 }, limitInputPixels: false })
  .jpeg({ quality: 88 }).toFile(path.join(OUT, name));

async function buildPhoto() {
  // --- context ---
  const sentinel = async (z, half, step) => {
    const satellite = await loadSatellite(z, half), n = 2 * half / step, out = new Float32Array(n * n * 3);
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++)
      out.set(satellite(...utmLL(CE - half + (c + 0.5) * step, CN + half - (r + 0.5) * step)), (r * n + c) * 3);
    return out;
  };
  const cn = 2 * PHOTO_CTX_HALF / PHOTO_CTX_STEP;
  const ortho = await loadOrtho('ortho_context', PHOTO_CTX_HALF, PHOTO_CTX_STEP);
  const cw = await photoWeight(ortho, cn, 12);
  const sat = await sentinel(SAT_Z, PHOTO_CTX_HALF, PHOTO_CTX_STEP);
  // Matched against the orthophoto at Sentinel-2 resolution.
  console.log('Sentinel-2 -> orthophoto');
  const grade = colourMatch(sat, await sharp(ortho, { raw: { width: cn, height: cn, channels: 3 }, limitInputPixels: false }).blur(1.2).raw().toBuffer(), cw);
  const ctx = Buffer.alloc(cn * cn * 3);
  blendPhoto(ctx, sat, new Uint8Array(cn * cn).fill(255), grade);
  blendPhoto(ctx, ortho, cw);
  await jpeg('photo_context.jpg', ctx, cn);

  // --- far ---
  const fn = 2 * CTX_HALF / PHOTO_FAR_STEP, inner = 2 * PHOTO_CTX_HALF / PHOTO_FAR_STEP, offset = (CTX_HALF - PHOTO_CTX_HALF) / PHOTO_FAR_STEP;
  const far = Buffer.alloc(fn * fn * 3);
  blendPhoto(far, await sentinel(SAT_FAR_Z, CTX_HALF, PHOTO_FAR_STEP), new Uint8Array(fn * fn).fill(255), grade);
  const centre = await sharp(ctx, { raw: { width: cn, height: cn, channels: 3 }, limitInputPixels: false })
    .resize(inner, inner, { kernel: 'lanczos3' }).raw().toBuffer();
  for (let r = 0; r < inner; r++) centre.copy(far, ((r + offset) * fn + offset) * 3, r * inner * 3, (r + 1) * inner * 3);
  await jpeg('photo_far.jpg', far, fn);

  // --- wide ---
  const wn = 2 * CORE_HALF / PHOTO_WIDE_STEP, sn = 2 * CORE_HALF / PHOTO_CTX_STEP;
  const wide = await cropPhoto(ctx, PHOTO_CTX_HALF, PHOTO_CTX_STEP, CORE_HALF, wn);
  const agea = await loadOrtho('agea_wide', CORE_HALF, PHOTO_WIDE_STEP), aw = await photoWeight(agea, wn, 15);
  const pat = await loadOrtho('ortho_wide', CORE_HALF, PHOTO_WIDE_STEP), pw = await photoWeight(pat, wn, 15);
  // AGEA graded to the orthophoto where both cover the ground (southern Trentino, the lake), at 8 m.
  console.log('AGEA 2024 -> orthophoto');
  const small = (buf, channels, kernel) => {
    const image = sharp(buf, { raw: { width: wn, height: wn, channels }, limitInputPixels: false }).resize(sn, sn, { kernel });
    return (channels === 1 ? image.extractChannel(0) : image).raw().toBuffer();
  };
  const both = await small(aw.map((w, i) => Math.min(w, pw[i])), 1, 'nearest');
  blendPhoto(wide, agea, aw, colourMatch(await small(agea, 3, 'lanczos3'), await small(pat, 3, 'lanczos3'), both));
  blendPhoto(wide, pat, pw);
  await jpeg('photo_wide.jpg', wide, wn);

  // --- core ---
  const n = 2 * PHOTO_CORE_HALF / PHOTO_CORE_STEP;
  const core = await cropPhoto(wide, CORE_HALF, PHOTO_WIDE_STEP, PHOTO_CORE_HALF, n);
  const fine = await loadOrtho('ortho_core', PHOTO_CORE_HALF, PHOTO_CORE_STEP);
  blendPhoto(core, fine, await photoWeight(fine, n, 15));
  await jpeg('photo_core.jpg', core, n);
  console.log('Photo build complete:', OUT);
}

// Context only (Copernicus, WorldCover): no LiDAR/OSM needed to iterate on it.
async function buildContext() {
  const copernicus = await loadCopernicus();
  const worldcover = await loadWorldCover(contextLatLonBounds(), 3); // 30 m: the DEM step

  // --- context grid: DEM, land cover class ---
  const ctxH = new Float32Array(CTX_N * CTX_N), ctxClass = new Uint8Array(CTX_N * CTX_N);
  for (let r = 0; r < CTX_N; r++) for (let c = 0; c < CTX_N; c++) {
    const e = CE - CTX_HALF + c * CTX_STEP, n = CN + CTX_HALF - r * CTX_STEP, [lat, lon] = utmLL(e, n), i = r * CTX_N + c;
    ctxH[i] = copernicus(lat, lon);
    ctxClass[i] = worldcover(lat, lon);
  }
  const histogram = {};
  for (const k of ctxClass) histogram[k] = (histogram[k] || 0) + 1;
  console.log('WorldCover classes (context):', JSON.stringify(histogram));
  assert(!histogram[0] || histogram[0] < ctxClass.length * 0.01, 'WorldCover decoding failed');
  assert(ctxH.every(Number.isFinite), 'Copernicus tile missing');
  // Lake Garda: WorldCover water at the lake level, given a bed so the water plane covers it. Only the largest
  // such area: rivers and plain lakes elsewhere are below the Garda level but outside its water plane.
  const lake = new Uint8Array(CTX_N * CTX_N);
  for (let i = 0; i < lake.length; i++) lake[i] = ctxClass[i] === 80 && ctxH[i] < LAKE_LEVEL + 12 ? 1 : 0;
  const label = new Int32Array(CTX_N * CTX_N), queue = new Int32Array(CTX_N * CTX_N);
  let best = 0, bestSize = 0;
  for (let start = 0, id = 0; start < lake.length; start++) {
    if (!lake[start] || label[start]) continue;
    let head = 0, tail = 0;
    label[start] = ++id; queue[tail++] = start;
    while (head < tail) {
      const i = queue[head++], c = i % CTX_N;
      for (const j of [c > 0 ? i - 1 : -1, c < CTX_N - 1 ? i + 1 : -1, i - CTX_N, i + CTX_N])
        if (j >= 0 && j < lake.length && lake[j] && !label[j]) { label[j] = id; queue[tail++] = j; }
    }
    if (tail > bestSize) { best = id; bestSize = tail; }
  }
  const lakeRect = [Infinity, Infinity, -Infinity, -Infinity];
  for (let i = 0; i < lake.length; i++) {
    lake[i] = label[i] === best ? 1 : 0;
    if (!lake[i]) continue;
    const x = -CTX_HALF + (i % CTX_N) * CTX_STEP, z = -CTX_HALF + Math.floor(i / CTX_N) * CTX_STEP;
    lakeRect[0] = Math.min(lakeRect[0], x); lakeRect[1] = Math.min(lakeRect[1], z);
    lakeRect[2] = Math.max(lakeRect[2], x); lakeRect[3] = Math.max(lakeRect[3], z);
  }
  console.log(`Lake Garda: ${(bestSize * CTX_STEP * CTX_STEP / 1e6).toFixed(0)} km2, x/z ${lakeRect.join(' ')}`);
  const ctxLakeDist = distanceInside(lake, CTX_N, CTX_N);
  for (let i = 0; i < lake.length; i++)
    if (lake[i]) ctxH[i] = LAKE_LEVEL - Math.min(LAKE_MAX_DEPTH, 4 + ctxLakeDist[i] * CTX_STEP * 0.35);
  const ctxAt = (x, z) => {
    // Bilinear context height at world x/z.
    const fx = (x + CTX_HALF) / CTX_STEP, fz = (z + CTX_HALF) / CTX_STEP;
    const ix = Math.max(0, Math.min(CTX_N - 2, Math.floor(fx))), iz = Math.max(0, Math.min(CTX_N - 2, Math.floor(fz)));
    const ax = fx - ix, az = fz - iz, p = (a, b) => ctxH[b * CTX_N + a];
    return (p(ix, iz) * (1 - ax) + p(ix + 1, iz) * ax) * (1 - az) + (p(ix, iz + 1) * (1 - ax) + p(ix + 1, iz + 1) * ax) * az;
  };

  // --- context land cover as filterable weights for the material response ---
  // Texel centres sit on grid points, like the DEM: world x = -CTX_HALF + c * COVER_STEP.
  // Bare rock, snow/ice, water: the photo carries the colour, these drive the material response.
  const offsets = [-1, 0, 1].map(k => k * COVER_STEP / 3);
  const cover = Buffer.alloc(COVER_N * COVER_N * 3);
  for (let r = 0; r < COVER_N; r++) for (let c = 0; c < COVER_N; c++) {
    const e = CE - CTX_HALF + c * COVER_STEP, n = CN + CTX_HALF - r * COVER_STEP, o = (r * COVER_N + c) * 3;
    for (const oy of offsets) for (const ox of offsets) {
      const ch = [60, 70, 80].indexOf(worldcover(...utmLL(e + ox, n - oy)));
      if (ch >= 0) cover[o + ch] += 255 / 9;
    }
  }

  raw('context_height.r32', ctxH);
  await png('context_cover.png', cover, COVER_N, 3);
  const manifest = { center_utm32: [CE, CN], lake_level: LAKE_LEVEL, lake_rect: lakeRect,
    core: { half: CORE_HALF, step: CORE_STEP, size: CORE_N, file: 'core_height.r32' },
    masks: { half: CORE_HALF, step: MASK_STEP, size: MASK_N },
    context: { half: CTX_HALF, step: CTX_STEP, size: CTX_N, file: 'context_height.r32' },
    world: 'x = E - center_e, z = center_n - N, y = metres above sea level' };
  fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify(manifest, null, 2));
  console.log('Context build complete:', OUT);
  return { ctxAt };
}

// Core: LiDAR heights and OSM/WorldCover masks, blended into the context at the edge.
async function buildCore({ ctxAt }) {
  const worldcover = await loadWorldCover(contextLatLonBounds(CORE_HALF));
  // --- OSM masks over the core ---
  const items = osmGeometry();
  const t = k => i => i.tags[k] !== undefined;
  const is = (k, ...v) => i => v.includes(i.tags[k]);
  const urbanTest = i => is('landuse', 'residential', 'commercial', 'retail', 'industrial', 'construction', 'railway', 'garages')(i)
    || is('amenity', 'parking', 'school', 'hospital')(i) || is('leisure', 'pitch', 'sports_centre', 'stadium', 'marina')(i);
  const vineTest = is('landuse', 'vineyard', 'orchard');
  const fieldTest = is('landuse', 'farmland', 'allotments', 'plant_nursery', 'greenhouse_horticulture');
  const meadowTest = i => is('landuse', 'meadow', 'grass', 'village_green', 'recreation_ground')(i) || is('leisure', 'park', 'golf_course', 'garden')(i);
  const forestTest = i => is('landuse', 'forest')(i) || is('natural', 'wood')(i);
  const rockTest = is('natural', 'bare_rock', 'scree', 'shingle', 'cliff', 'stone');
  const scrubTest = is('natural', 'scrub', 'heath');
  const waterTest = i => is('natural', 'water')(i) || is('landuse', 'reservoir', 'basin')(i) || i.tags.water !== undefined || is('waterway', 'riverbank')(i);
  const buildingTest = t('building');

  const mUrban = await renderMask(fills(items, urbanTest));
  const mVine = await renderMask(fills(items, vineTest));
  const mField = await renderMask(fills(items, fieldTest));
  const mMeadow = await renderMask(fills(items, meadowTest));
  const mForestOsm = await renderMask(fills(items, forestTest));
  const mRock = await renderMask(fills(items, rockTest).concat(strokes(items.filter(i => is('natural', 'cliff')(i) && i.line), () => 12, 'butt')));
  const mScrub = await renderMask(fills(items, scrubTest));
  const mWater = await renderMask(fills(items, waterTest).concat(strokes(items.filter(is('waterway', 'river', 'stream', 'canal')),
    i => i.tags.waterway === 'river' ? 30 : i.tags.waterway === 'canal' ? 8 : 3)));
  const mBuild = await renderMask(fills(items, buildingTest));
  const mRoad = await renderMask(strokes(items.filter(i => roadWidth[i.tags.highway] && !i.tags.tunnel),
    i => Math.max(roadWidth[i.tags.highway], (+i.tags.lanes || 0) * 3.2))
    .concat(strokes(items.filter(i => i.tags.railway === 'rail' && i.line && !i.tags.tunnel), () => 6, 'butt')));
  // Parcel row direction and a per-parcel seed for colour variation.
  const parcels = items.filter(i => (vineTest(i) || fieldTest(i) || meadowTest(i)) && i.rings.length);
  const grey = v => { const g = Math.round(Math.max(0, Math.min(1, v)) * 255); return `rgb(${g},${g},${g})`; };
  const all = () => true;
  const mAngle = await renderMask(fills(parcels, all, i => grey(parcelAngle(i.rings[0]))), true);
  const seed = i => grey(0.04 + 0.96 * hash01(i.id));
  const mSeed = await renderMask(fills(parcels, all, seed).concat(fills(items, buildingTest, seed)), true);
  const mKind = await renderMask(fills(parcels, all, i => is('landuse', 'orchard')(i) ? '#fff' : is('landuse', 'vineyard')(i) ? '#808080' : '#000'), true);

  // --- per-mask-pixel land use (WorldCover where OSM is silent) ---
  const masksA = Buffer.alloc(MASK_N * MASK_N * 4), masksB = Buffer.alloc(MASK_N * MASK_N * 4), masksC = Buffer.alloc(MASK_N * MASK_N * 4);
  const coreLake = new Uint8Array(MASK_N * MASK_N);
  for (let r = 0; r < MASK_N; r++) for (let c = 0; c < MASK_N; c++) {
    const i = r * MASK_N + c;
    const e = CE - CORE_HALF + (c + 0.5) * MASK_STEP, n = CN + CORE_HALF - (r + 0.5) * MASK_STEP;
    const [lat, lon] = utmLL(e, n);
    const wc = worldcover(lat, lon);
    const cover = { 10: 0, 20: 0, 60: 0 };
    for (const [ox, oy] of [[-2.5, -2.5], [2.5, -2.5], [-2.5, 2.5], [2.5, 2.5]]) {
      const k = worldcover(...utmLL(e + ox, n + oy));
      if (k in cover) cover[k] += 255 / 4;
    }
    const water = Math.max(mWater[i], wc === 80 ? 255 : 0);
    const urban = Math.max(mUrban[i], wc === 50 && !mVine[i] && !mField[i] ? 200 : 0);
    const cultivated = Math.max(mVine[i], mField[i]);
    const override = Math.max(urban, cultivated, mMeadow[i], water) / 255;
    const forest = Math.max(cover[10], mForestOsm[i] * 0.6) * (1 - override);
    const rock = Math.max(mRock[i], cover[60]) * (1 - Math.max(urban, cultivated) / 255);
    masksA[i * 4] = forest; masksA[i * 4 + 1] = mVine[i]; masksA[i * 4 + 2] = Math.max(mField[i], wc === 40 && !mVine[i] && !urban ? 255 : 0); masksA[i * 4 + 3] = urban;
    masksB[i * 4] = mBuild[i]; masksB[i * 4 + 1] = mRoad[i]; masksB[i * 4 + 2] = rock; masksB[i * 4 + 3] = water;
    masksC[i * 4] = mAngle[i]; masksC[i * 4 + 1] = mSeed[i]; masksC[i * 4 + 2] = mKind[i]; masksC[i * 4 + 3] = Math.max(mScrub[i], cover[20]) * (1 - override);
    coreLake[i] = water > 128 ? 1 : 0;
  }

  // --- core heights: the finest DTM at each vertex, Copernicus where there is none, the context at the edge ---
  // PAT LiDAR > Veneto LiDAR 5 m > Lombardia 5 m: a source ramps in from its own edge over SEAM_BLEND where a
  // coarser DTM lies under it. The DTMs ramp into Copernicus over FINE_BLEND.
  const valid = new Uint8Array(CORE_N * CORE_N);
  const ramp = (src, metres) => {
    for (let i = 0; i < src.length; i++) valid[i] = Number.isNaN(src[i]) ? 0 : 1;
    const d = distanceInside(valid, CORE_N, CORE_N);
    for (let i = 0; i < d.length; i++) { const x = Math.min(1, d[i] * CORE_STEP / metres); d[i] = x * x * (3 - 2 * x); }
    return d;
  };
  const coverage = src => `${(100 * src.reduce((n, v) => n + (Number.isNaN(v) ? 0 : 1), 0) / src.length).toFixed(1)}%`;
  const fine = await loadLombardia();
  console.log(`Core: Lombardia DTM ${coverage(fine)}`);
  for (const [name, src] of [['Veneto LiDAR', loadVeneto()], ['PAT LiDAR', loadLidar()]]) {
    console.log(`Core: ${name} ${coverage(src)}`);
    const w = ramp(src, SEAM_BLEND);
    for (let i = 0; i < src.length; i++)
      if (!Number.isNaN(src[i])) fine[i] = Number.isNaN(fine[i]) ? src[i] : fine[i] + (src[i] - fine[i]) * w[i];
  }
  console.log(`Core: DTM coverage ${coverage(fine)}`);
  const fineWeight = ramp(fine, FINE_BLEND);
  const core = new Float32Array(CORE_N * CORE_N);
  for (let r = 0; r < CORE_N; r++) for (let c = 0; c < CORE_N; c++) {
    const x = -CORE_HALF + c * CORE_STEP, z = -CORE_HALF + r * CORE_STEP, i = r * CORE_N + c;
    const edge = Math.min(x + CORE_HALF, CORE_HALF - CORE_STEP - x, z + CORE_HALF, CORE_HALF - CORE_STEP - z);
    const w = Math.max(0, Math.min(1, edge / EDGE_BLEND)), s = w * w * (3 - 2 * w);
    const base = ctxAt(x, z);
    const h = Number.isNaN(fine[i]) ? base : base + (fine[i] - base) * fineWeight[i];
    core[i] = base + (h - base) * s;
  }
  // The lake: no bathymetry in either DEM. Carve under the OSM/WorldCover water of Garda.
  const lakeDist = distanceInside(coreLake, MASK_N, MASK_N);
  for (let r = 0; r < CORE_N; r++) for (let c = 0; c < CORE_N; c++) {
    const mi = Math.min(MASK_N - 1, r >> 1) * MASK_N + Math.min(MASK_N - 1, c >> 1), i = r * CORE_N + c;
    if (!coreLake[mi] || core[i] > LAKE_LEVEL + 6) continue;
    core[i] = Math.min(core[i], LAKE_LEVEL - Math.min(LAKE_MAX_DEPTH, 1.5 + lakeDist[mi] * MASK_STEP * 0.35));
  }

  raw('core_height.r32', core);
  await png('masks_a.png', masksA, MASK_N);
  await png('masks_b.png', masksB, MASK_N);
  await png('masks_c.png', masksC, MASK_N);
  console.log('Core build complete:', OUT);
}

// relief_core.png: world normals (x, z in R, G; y = sqrt(1 - x² - z²)) of the PAT LiDAR 2 m blocks around
// Riva, the detail the 4 m Terrain3D vertices average away. Riding on the core heights (clamped difference),
// so the shading follows the rendered surface where the LiDAR ends (lake, Lombardia) or differs (seams).
const RELIEF_HALF = 5120, RELIEF_STEP = 2, RELIEF_DETAIL = 3.0;
function buildRelief() {
  const n = 2 * RELIEF_HALF / RELIEF_STEP, west = CE - RELIEF_HALF, north = CN + RELIEF_HALF;
  const lidar = new Float32Array(n * n).fill(NaN);
  for (const { properties: p } of JSON.parse(fs.readFileSync(path.join(TILES, 'lidar_index.json'))).features) {
    const file = path.join(TILES, 'lidar', `${p.n_tavola}.f32`);
    const c0 = (p.x_min - west) / DTM_BLOCK, r0 = (north - p.y_min - DTM_TILE) / DTM_BLOCK;
    if (c0 <= -DTM_BLOCKS || c0 >= n || r0 <= -DTM_BLOCKS || r0 >= n || !fs.existsSync(file)) continue;
    const b = fs.readFileSync(file), blocks = new Float32Array(b.buffer.slice(b.byteOffset, b.byteOffset + b.length));
    for (let bj = 0; bj < DTM_BLOCKS; bj++) for (let bi = 0; bi < DTM_BLOCKS; bi++) {
      const r = r0 + bj, c = c0 + bi;
      if (r >= 0 && r < n && c >= 0 && c < n) lidar[r * n + c] = blocks[bj * DTM_BLOCKS + bi];
    }
  }
  const b = fs.readFileSync(path.join(OUT, 'core_height.r32')), core = new Float32Array(b.buffer, b.byteOffset, CORE_N * CORE_N);
  const h = new Float32Array(n * n);
  let covered = 0;
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) {
    // Pixel centre on the core vertex grid (bilinear).
    const u = (-RELIEF_HALF + (c + 0.5) * RELIEF_STEP + CORE_HALF) / CORE_STEP, v = (-RELIEF_HALF + (r + 0.5) * RELIEF_STEP + CORE_HALF) / CORE_STEP;
    const u0 = Math.floor(u), v0 = Math.floor(v), fu = u - u0, fv = v - v0, k = v0 * CORE_N + u0;
    const base = (core[k] * (1 - fu) + core[k + 1] * fu) * (1 - fv) + (core[k + CORE_N] * (1 - fu) + core[k + CORE_N + 1] * fu) * fv;
    const l = lidar[r * n + c];
    if (!Number.isNaN(l)) covered++;
    h[r * n + c] = Number.isNaN(l) ? base : base + Math.max(-RELIEF_DETAIL, Math.min(RELIEF_DETAIL, l - base));
  }
  const out = Buffer.alloc(n * n * 3);
  const at = (r, c) => h[Math.min(n - 1, Math.max(0, r)) * n + Math.min(n - 1, Math.max(0, c))];
  for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) {
    const x = at(r, c - 1) - at(r, c + 1), y = 2 * RELIEF_STEP, z = at(r - 1, c) - at(r + 1, c), len = Math.hypot(x, y, z);
    const i = (r * n + c) * 3;
    out[i] = Math.round((x / len * 0.5 + 0.5) * 255);
    out[i + 1] = Math.round((z / len * 0.5 + 0.5) * 255);
    out[i + 2] = 255;
  }
  console.log(`Relief: ${n} px, LiDAR on ${(covered / n / n * 100).toFixed(1)}%`);
  return png('relief_core.png', out, n, 3);
}

// ---------- buildings: OSM footprints as boxes, roof height from the PAT DBM ----------
// buildings.json, one entry per building: ring (world x, z pairs, outer ring only), roof (DBM median
// inside the footprint, null if none), height (OSM height/levels, 0 if untagged), colour (sRGB 0..1,
// orthophoto mean), gable (centre x, z, ridge length, span, ridge angle in the xz plane) when the footprint
// is close to its minimum-area rectangle, else null (flat roof). Bases come from Terrain3D in the Godot build.
const BUILDING_MIN_AREA = 12, DBM_TILE = 500, DBM_CELL = 0.5;
// Gable roofs: footprint fills >= 85% of its rectangle and spans 4-20 m (wider: flat industrial roofs).
const GABLE_FILL = 0.85, GABLE_MIN_SPAN = 4, GABLE_MAX_SPAN = 20;
function osmBuildings() {
  const world = g => { const [e, n] = toUtm(g.lat, g.lon); return [e - CE, CN - n]; };
  const out = [];
  forEachOsm(el => {
    const tags = el.tags || {};
    if (!tags.building || ['roof', 'ruins', 'construction'].includes(tags.building)) return;
    // ponytail: multipolygons keep their closed outer ways; outer rings split over several ways are skipped.
    const ways = el.type === 'way' ? [el.geometry] : (el.members || []).filter(m => m.role === 'outer').map(m => m.geometry);
    for (const g of ways) {
      if (!g || g.length < 4) continue;
      const ring = g.map(world);
      const first = ring[0], last = ring.pop();
      if (Math.hypot(first[0] - last[0], first[1] - last[1]) > 0.01) continue;
      if (ring.some(([x, z]) => Math.abs(x) > BUILDINGS_HALF - 2 || Math.abs(z) > BUILDINGS_HALF - 2)) continue;
      let area = 0;
      for (let i = 0; i < ring.length; i++) { const a = ring[i], b = ring[(i + 1) % ring.length]; area += a[0] * b[1] - b[0] * a[1]; }
      if (Math.abs(area) / 2 >= BUILDING_MIN_AREA) out.push({ ring, tags, area: Math.abs(area) / 2 });
    }
  });
  return out;
}
const ringBounds = ring => ring.reduce((b, [x, z]) => [Math.min(b[0], x), Math.min(b[1], z), Math.max(b[2], x), Math.max(b[3], z)],
  [Infinity, Infinity, -Infinity, -Infinity]);
function insideRing(ring, x, z) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, zi] = ring[i], [xj, zj] = ring[j];
    if ((zi > z) !== (zj > z) && x < (xj - xi) * (z - zi) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}
// Minimum-area rectangle: one side lies on a convex hull edge.
function footprintBox(ring) {
  const pts = ring.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const half = list => list.reduce((h, p) => { while (h.length > 1 && cross(h[h.length - 2], h[h.length - 1], p) <= 0) h.pop(); h.push(p); return h; }, []);
  const lower = half(pts), upper = half(pts.slice().reverse());
  const hull = lower.slice(0, -1).concat(upper.slice(0, -1));
  let best = null;
  for (let i = 0; i < hull.length; i++) {
    const [ax, az] = hull[i], [bx, bz] = hull[(i + 1) % hull.length];
    const angle = Math.atan2(bz - az, bx - ax), c = Math.cos(angle), s = Math.sin(angle);
    let u0 = Infinity, u1 = -Infinity, v0 = Infinity, v1 = -Infinity;
    for (const [x, z] of hull) {
      const u = x * c + z * s, v = z * c - x * s;
      u0 = Math.min(u0, u); u1 = Math.max(u1, u); v0 = Math.min(v0, v); v1 = Math.max(v1, v);
    }
    if (!best || (u1 - u0) * (v1 - v0) < best.area)
      best = { area: (u1 - u0) * (v1 - v0), angle, c, s, u: (u0 + u1) / 2, v: (v0 + v1) / 2, width: u1 - u0, depth: v1 - v0 };
  }
  return { x: best.u * best.c - best.v * best.s, z: best.u * best.s + best.v * best.c, width: best.width, depth: best.depth, angle: best.angle };
}
// 500 m DBM tiles (by south-west corner in UTM) touched by the footprints.
function buildingTiles(buildings) {
  const keys = new Set();
  for (const { ring } of buildings) {
    const [x0, z0, x1, z1] = ringBounds(ring);
    for (let e = Math.floor((CE + x0) / DBM_TILE); e <= Math.floor((CE + x1) / DBM_TILE); e++)
      for (let n = Math.floor((CN - z1) / DBM_TILE); n <= Math.floor((CN - z0) / DBM_TILE); n++) keys.add(`${e * DBM_TILE}_${n * DBM_TILE}`);
  }
  return keys;
}
const tileKey = f => `${f.properties.x_min}_${f.properties.y_min}`;

async function buildBuildings(buildings) {
  const names = new Map(JSON.parse(fs.readFileSync(path.join(TILES, 'lidar_dbm_index.json'))).features.map(f => [tileKey(f), f.properties.n_tavola]));
  const cache = new Map(); // ponytail: FIFO of 24 tiles (~100 MB); buildings are sorted by tile row.
  const dbmAt = (e, n) => {
    const key = `${Math.floor(e / DBM_TILE) * DBM_TILE}_${Math.floor(n / DBM_TILE) * DBM_TILE}`;
    if (!cache.has(key)) {
      if (cache.size >= 24) cache.delete(cache.keys().next().value);
      const file = path.join(TILES, 'lidar_dbm', `${names.get(key)}.asc`);
      let grid = null;
      if (names.has(key) && fs.existsSync(file)) {
        const a = readAsc(file);
        assert(a.cols * a.cell === DBM_TILE && a.rows * a.cell === DBM_TILE, 'Unexpected DBM tile ' + file);
        grid = a.values;
      }
      cache.set(key, grid);
    }
    const grid = cache.get(key);
    if (!grid) return NaN;
    const n0 = DBM_TILE / DBM_CELL, c = Math.floor((e % DBM_TILE) / DBM_CELL), r = n0 - 1 - Math.floor((n % DBM_TILE) / DBM_CELL);
    return grid[r * n0 + c];
  };
  const n = Math.round(2 * PHOTO_CORE_HALF / PHOTO_CORE_STEP);
  const { data: photo } = await sharp(path.join(OUT, 'photo_core.jpg'), { limitInputPixels: false }).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const rowOf = b => Math.floor((CN - b.ring[0][1]) / DBM_TILE) * 1e6 + Math.floor((CE + b.ring[0][0]) / DBM_TILE);
  buildings.sort((a, b) => rowOf(a) - rowOf(b));
  const out = [];
  let withRoof = 0, gables = 0;
  buildings.forEach(({ ring, tags, area }) => {
    const box = footprintBox(ring);
    const [x0, z0, x1, z1] = ringBounds(ring);
    const roofs = [], colour = [0, 0, 0];
    let samples = 0;
    // DBM cell centres (UTM multiples of 0.5 m + 0.25) inside the footprint.
    for (let e = Math.floor((CE + x0) / DBM_CELL) * DBM_CELL + DBM_CELL / 2; e < CE + x1; e += DBM_CELL)
      for (let nn = Math.floor((CN - z1) / DBM_CELL) * DBM_CELL + DBM_CELL / 2; nn < CN - z0; nn += DBM_CELL) {
        const x = e - CE, z = CN - nn;
        if (!insideRing(ring, x, z)) continue;
        const h = dbmAt(e, nn);
        if (Number.isFinite(h)) roofs.push(h);
        const p = (Math.min(n - 1, Math.floor((z + PHOTO_CORE_HALF) / PHOTO_CORE_STEP)) * n + Math.min(n - 1, Math.floor((x + PHOTO_CORE_HALF) / PHOTO_CORE_STEP))) * 3;
        colour[0] += photo[p]; colour[1] += photo[p + 1]; colour[2] += photo[p + 2]; samples++;
      }
    roofs.sort((a, b) => a - b);
    const roof = roofs.length >= 4 ? roofs[roofs.length >> 1] : NaN;
    if (Number.isFinite(roof)) withRoof++;
    const levels = parseFloat(tags['building:levels']);
    const height = parseFloat(tags.height) || (levels > 0 ? levels * 3 + 1 : 0);
    // Ridge along the long side.
    const [ridge, span, angle] = box.width >= box.depth ? [box.width, box.depth, box.angle] : [box.depth, box.width, box.angle + Math.PI / 2];
    const gable = area >= GABLE_FILL * box.width * box.depth && span >= GABLE_MIN_SPAN && span <= GABLE_MAX_SPAN;
    if (gable) gables++;
    const round = v => Math.round(v * 100) / 100;
    out.push({ ring: ring.flat().map(round), roof: Number.isFinite(roof) ? round(roof) : null, height,
      colour: colour.map(v => round(samples ? v / samples / 255 : 0.5)),
      gable: gable ? [box.x, box.z, ridge, span, angle].map(v => Math.round(v * 1000) / 1000) : null });
  });
  fs.writeFileSync(path.join(OUT, 'buildings.json'), JSON.stringify(out));
  console.log(`Buildings: ${buildings.length}, ${withRoof} with a DBM roof, ${gables} gabled`);
}

(async () => {
  const phase = process.argv[2] || 'all';
  // context = fetch + build of the context only (Copernicus, WorldCover).
  // photo = fetch + build of the albedo photos (orthophoto, Sentinel-2).
  if (phase === 'fetch' || phase === 'all' || phase === 'context') {
    await fetchCopernicus();
    await fetchWorldCover();
  }
  if (phase === 'fetch' || phase === 'all' || phase === 'photo') {
    await fetchSatellite(SAT_Z, PHOTO_CTX_HALF);
    await fetchSatellite(SAT_FAR_Z, CTX_HALF);
    await fetchOrtho('ortho_core', PHOTO_CORE_HALF, PHOTO_CORE_STEP);
    await fetchOrtho('ortho_wide', CORE_HALF, PHOTO_WIDE_STEP);
    await fetchOrtho('agea_wide', CORE_HALF, PHOTO_WIDE_STEP, 'agea');
    await fetchOrtho('ortho_context', PHOTO_CTX_HALF, PHOTO_CTX_STEP);
  }
  if (phase === 'fetch' || phase === 'all') {
    await fetchOsm();
    await fetchLombardia();
    await fetchVeneto();
  }
  // lidar = the PAT DTM download alone (~6000 tiles, hours): fetch runs it too.
  if (phase === 'fetch' || phase === 'all' || phase === 'lidar') await fetchLidar();
  if (phase === 'context') await buildContext();
  if (phase === 'build' || phase === 'all') await buildCore(await buildContext());
  if (phase === 'photo' || phase === 'build' || phase === 'all') await buildPhoto();
  // relief = the 2 m normal map alone (needs the LiDAR cache and core_height.r32).
  if (phase === 'relief' || phase === 'build' || phase === 'all') await buildRelief();
  // buildings = OSM + DBM tiles under the footprints, then boxes (after photo: roof colours).
  if (phase === 'buildings' || phase === 'all') {
    if (phase === 'buildings') await fetchOsm();
    const buildings = osmBuildings(), tiles = buildingTiles(buildings);
    await fetchLidar('dbm', f => tiles.has(tileKey(f)));
    await buildBuildings(buildings);
  }
})().catch(e => { console.error(e); process.exit(1); });
