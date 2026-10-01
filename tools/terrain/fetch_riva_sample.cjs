// Riva del Garda sample: 10.24 km of real data + 61 km context, aligned in UTM 32N.
// Phases: node tools/terrain/fetch_riva_sample.cjs fetch | build | all
// Requires `npm i --no-save sharp` in tools/. Download cache in tools/tiles/riva/,
// outputs in terrain/source/riva_sample/ (both git-ignored). Godot import:
// tools/terrain/build_riva_sample.gd.
//
// Sources (attribution required):
//  - DTM LiDAR PAT 2014/2018 0.5 m, Provincia autonoma di Trento, CC BY 4.0
//  - Copernicus DEM GLO-30, © DLR/Airbus, provided under COPERNICUS by the EU and ESA
//  - ESA WorldCover 10 m 2021 v200, © ESA, CC BY 4.0
//  - OpenStreetMap, © OpenStreetMap contributors, ODbL
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
fs.mkdirSync(OUT, { recursive: true });

// World origin (UTM 32N / ETRS89, <1 m apart here). World x = E - CE, world z = CN - N.
const CE = 645120, CN = 5082880;
const CORE_HALF = 5120, CORE_STEP = 2, CORE_N = 5120; // Terrain3D vertices
const MASK_STEP = 4, MASK_N = 2560;                    // land use masks over the core
const CTX_HALF = 30720, CTX_STEP = 30, CTX_N = 2048;   // context DEM, colour and tint
const LAKE_LEVEL = 65.0, LAKE_MAX_DEPTH = 300.0;
const EDGE_BLEND = 400.0; // core LiDAR -> context DEM over the outer band of the core

// ---------- UTM zone 32 ----------
const A = 6378137, F = 1 / 298.257223563, K0 = 0.9996, E2 = 2 * F - F * F, EP2 = E2 / (1 - E2);
const LON0 = 9 * Math.PI / 180;
function toUtm(lat, lon) {
  const la = lat * Math.PI / 180, lo = lon * Math.PI / 180;
  const N = A / Math.sqrt(1 - E2 * Math.sin(la) ** 2);
  const T = Math.tan(la) ** 2, C = EP2 * Math.cos(la) ** 2, Aa = Math.cos(la) * (lo - LON0);
  const M = A * ((1 - E2 / 4 - 3 * E2 * E2 / 64 - 5 * E2 ** 3 / 256) * la
    - (3 * E2 / 8 + 3 * E2 * E2 / 32 + 45 * E2 ** 3 / 1024) * Math.sin(2 * la)
    + (15 * E2 * E2 / 256 + 45 * E2 ** 3 / 1024) * Math.sin(4 * la) - (35 * E2 ** 3 / 3072) * Math.sin(6 * la));
  return [K0 * N * (Aa + (1 - T + C) * Aa ** 3 / 6 + (5 - 18 * T + T * T + 72 * C - 58 * EP2) * Aa ** 5 / 120) + 500000,
    K0 * (M + N * Math.tan(la) * (Aa * Aa / 2 + (5 - T + 9 * C + 4 * C * C) * Aa ** 4 / 24
      + (61 - 58 * T + T * T + 600 * C - 330 * EP2) * Aa ** 6 / 720))];
}
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
      await new Promise(r => setTimeout(r, 4000 * i));
    }
  }
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

// ---------- fetch phase ----------
const STEM = 'https://siat.provincia.tn.it';
async function fetchLidar() {
  // Tile index from the province WFS; download through the public STEM merge service.
  const e0 = CE - CORE_HALF, n0 = CN - CORE_HALF;
  const index = await get(`${STEM}/geoserver/stem/wfs?service=WFS&version=2.0.0&request=GetFeature`
    + `&typeNames=stem:inqlid2014_dtm_asc&outputFormat=application/json`
    + `&bbox=${e0 - 1},${n0 - 1},${e0 + 2 * CORE_HALF + 1},${n0 + 2 * CORE_HALF + 1},urn:ogc:def:crs:EPSG::25832`, 'lidar_index.json');
  const features = JSON.parse(index).features;
  const missing = features.filter(f => !fs.existsSync(path.join(TILES, 'lidar', `${f.properties.n_tavola}.asc`)));
  console.log(`LiDAR: ${features.length} tiles, ${missing.length} to download`);
  fs.mkdirSync(path.join(TILES, 'lidar'), { recursive: true });
  for (let i = 0; i < missing.length; i += 80) {
    const batch = missing.slice(i, i + 80);
    const r = await fetch(`${STEM}/stem/services/merge`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ files: batch.map(f => f.properties.location) }) });
    const job = await r.json();
    if (!job.success) throw new Error('STEM merge failed ' + JSON.stringify(job));
    for (;;) {
      const info = await (await fetch(`${STEM}/stem/services/file/info?id=${job.id}&token=${job.token}`)).json();
      if (info.state !== 0) break;
      await sleep(5000);
    }
    const zip = path.join(TILES, `lidar_batch_${i}.zip`);
    fs.rmSync(zip, { force: true });
    await get(`${STEM}/stem/services/file?id=${job.id}&token=${job.token}`, path.basename(zip));
    const dir = path.join(TILES, 'lidar');
    execFileSync('unzip', ['-o', '-q', zip, '-d', dir]);
    for (const inner of fs.readdirSync(dir).filter(f => f.endsWith('.zip'))) {
      execFileSync('unzip', ['-o', '-q', path.join(dir, inner), '-d', dir]);
      fs.rmSync(path.join(dir, inner));
    }
    for (const asc of fs.readdirSync(dir).filter(f => f.endsWith('_DTM.asc')))
      fs.renameSync(path.join(dir, asc), path.join(dir, asc.replace('_DTM.asc', '.asc')));
    fs.rmSync(zip);
    console.log(`  LiDAR batch ${i / 80 + 1}/${Math.ceil(missing.length / 80)} done`);
  }
  return features;
}

function contextLatLonBounds() {
  let s = 90, n = -90, w = 180, e = -180;
  for (const [dx, dy] of [[-1, -1], [1, -1], [-1, 1], [1, 1], [0, -1], [0, 1], [-1, 0], [1, 0]]) {
    const [la, lo] = toLatLon(CE + dx * CTX_HALF, CN + dy * CTX_HALF);
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

const WORLDCOVER = 'ESA_WorldCover_10m_2021_v200_N45E009_Map.tif';
async function fetchWorldCover() {
  await get(`https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/${WORLDCOVER}`, WORLDCOVER);
}

function coreLatLonBounds(margin) {
  const [s, w] = toLatLon(CE - CORE_HALF - margin, CN - CORE_HALF - margin);
  const [n, e] = toLatLon(CE + CORE_HALF + margin, CN + CORE_HALF + margin);
  const [s2, e2] = toLatLon(CE + CORE_HALF + margin, CN - CORE_HALF - margin);
  const [n2, w2] = toLatLon(CE - CORE_HALF - margin, CN + CORE_HALF + margin);
  return { s: Math.min(s, s2), n: Math.max(n, n2), w: Math.min(w, w2), e: Math.max(e, e2) };
}

async function fetchOsm() {
  const b = coreLatLonBounds(300);
  const bbox = `${b.s},${b.w},${b.n},${b.e}`;
  const query = `[out:json][timeout:300];(
    way["landuse"](${bbox});relation["landuse"](${bbox});
    way["natural"](${bbox});relation["natural"](${bbox});
    way["leisure"](${bbox});way["aeroway"](${bbox});
    way["building"](${bbox});relation["building"](${bbox});
    way["highway"](${bbox});way["railway"="rail"](${bbox});
    way["waterway"](${bbox});relation["water"](${bbox});
  );out geom;`;
  await get('https://overpass-api.de/api/interpreter', 'osm_core.json',
    { method: 'POST', body: 'data=' + encodeURIComponent(query), headers: { 'Content-Type': 'application/x-www-form-urlencoded' } });
}

// Web Mercator tiles of the EOX 2016 mosaic (CC BY 4.0; later years are non-commercial).
const SAT_Z = 13;
function mercTile(lat, lon, z) {
  const n = 2 ** z, la = lat * Math.PI / 180;
  return [(lon + 180) / 360 * n, (1 - Math.log(Math.tan(la) + 1 / Math.cos(la)) / Math.PI) / 2 * n];
}
function satRange() {
  const b = contextLatLonBounds();
  const [x0, y0] = mercTile(b.n, b.w, SAT_Z), [x1, y1] = mercTile(b.s, b.e, SAT_Z);
  return { x0: Math.floor(x0), y0: Math.floor(y0), x1: Math.floor(x1), y1: Math.floor(y1) };
}
async function fetchSatellite() {
  const r = satRange();
  fs.mkdirSync(path.join(TILES, 'sat'), { recursive: true });
  let count = 0;
  for (let y = r.y0; y <= r.y1; y++)
    for (let x = r.x0; x <= r.x1; x++) {
      await get(`https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/g/${SAT_Z}/${y}/${x}.jpg`, `sat/${SAT_Z}_${x}_${y}.jpg`);
      count++;
    }
  console.log(`Satellite: ${count} tiles`);
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

async function loadWorldCover() {
  const b = contextLatLonBounds();
  const left = Math.floor((b.w - 9) * 12000), top = Math.floor((48 - b.n) * 12000);
  const width = Math.ceil((b.e - 9) * 12000) - left, height = Math.ceil((48 - b.s) * 12000) - top;
  // The map is a paletted TIFF: libvips expands it to the official class colours.
  const { data, info } = await sharp(path.join(TILES, WORLDCOVER), { limitInputPixels: false })
    .extract({ left, top, width, height }).raw().toBuffer({ resolveWithObject: true });
  const palette = { 10: [0, 100, 0], 20: [255, 187, 34], 30: [255, 255, 76], 40: [240, 150, 255], 50: [250, 0, 0],
    60: [180, 180, 180], 70: [240, 240, 240], 80: [0, 100, 200], 90: [0, 150, 160], 95: [0, 207, 117], 100: [250, 230, 160] };
  const byColour = new Map(Object.entries(palette).map(([k, c]) => [(c[0] << 16) | (c[1] << 8) | c[2], +k]));
  const classes = new Uint8Array(width * height);
  for (let i = 0; i < classes.length; i++) {
    const o = i * info.channels;
    classes[i] = byColour.get((data[o] << 16) | (data[o + 1] << 8) | data[o + 2]) || 0;
  }
  return (lat, lon) => {
    const x = Math.floor((lon - 9) * 12000) - left, y = Math.floor((48 - lat) * 12000) - top;
    return x < 0 || y < 0 || x >= width || y >= height ? 0 : classes[y * width + x];
  };
}

async function loadSatellite() {
  const r = satRange(), w = (r.x1 - r.x0 + 1) * 256, h = (r.y1 - r.y0 + 1) * 256;
  const composites = [];
  for (let y = r.y0; y <= r.y1; y++)
    for (let x = r.x0; x <= r.x1; x++)
      composites.push({ input: path.join(TILES, 'sat', `${SAT_Z}_${x}_${y}.jpg`), left: (x - r.x0) * 256, top: (y - r.y0) * 256 });
  const { data } = await sharp({ create: { width: w, height: h, channels: 3, background: '#000' } })
    .composite(composites).raw().toBuffer({ resolveWithObject: true });
  return (lat, lon) => {
    const [fx, fy] = mercTile(lat, lon, SAT_Z);
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

function loadLidar() {
  // 0.5 m cells averaged into the 2 m Terrain3D vertex grid (each cell to its nearest vertex).
  const sum = new Float64Array(CORE_N * CORE_N), count = new Uint16Array(CORE_N * CORE_N);
  const west = CE - CORE_HALF, north = CN + CORE_HALF;
  const dir = path.join(TILES, 'lidar');
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.asc'));
  for (const f of files) {
    const text = fs.readFileSync(path.join(dir, f), 'latin1');
    const header = {};
    let pos = 0;
    for (let line = 0; line < 6; line++) {
      const end = text.indexOf('\n', pos);
      const [k, v] = text.slice(pos, end).trim().split(/\s+/);
      header[k.toLowerCase()] = +v;
      pos = end + 1;
    }
    const cols = header.ncols, rows = header.nrows, cell = header.cellsize, nodata = header.nodata_value;
    const x0 = header.xllcenter ?? header.xllcorner + cell / 2, y0 = header.yllcenter ?? header.yllcorner + cell / 2;
    const values = text.slice(pos).trim().split(/\s+/);
    for (let r = 0; r < rows; r++) {
      const n = y0 + (rows - 1 - r) * cell;
      const vr = Math.round((north - n) / CORE_STEP);
      if (vr < 0 || vr >= CORE_N) continue;
      for (let c = 0; c < cols; c++) {
        const v = +values[r * cols + c];
        if (v === nodata || !Number.isFinite(v)) continue;
        const vc = Math.round((x0 + c * cell - west) / CORE_STEP);
        if (vc < 0 || vc >= CORE_N) continue;
        sum[vr * CORE_N + vc] += v; count[vr * CORE_N + vc]++;
      }
    }
  }
  const out = new Float32Array(CORE_N * CORE_N).fill(NaN);
  for (let i = 0; i < out.length; i++) if (count[i] >= 4) out[i] = sum[i] / count[i];
  console.log(`LiDAR: ${files.length} tiles assembled`);
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
function osmGeometry() {
  const osm = JSON.parse(fs.readFileSync(path.join(TILES, 'osm_core.json'), 'utf8'));
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
  const items = [];
  for (const el of osm.elements) {
    const tags = el.tags || {};
    if (el.type === 'way' && el.geometry) {
      const pts = el.geometry.map(px);
      const isClosed = el.nodes && el.nodes[0] === el.nodes[el.nodes.length - 1];
      items.push({ tags, rings: isClosed ? [pts] : [], line: isClosed ? null : pts, id: el.id, closedLine: isClosed ? pts : null });
    } else if (el.type === 'relation' && el.members) {
      const members = el.members.filter(m => m.type === 'way' && m.geometry && (m.role === 'outer' || m.role === 'inner' || m.role === ''));
      items.push({ tags, rings: rings(members), line: null, id: el.id });
    }
  }
  return items;
}
const pathOf = rings => rings.map(r => 'M' + r.map(p => `${p[0].toFixed(2)},${p[1].toFixed(2)}`).join('L') + 'Z').join('');
const lineOf = pts => 'M' + pts.map(p => `${p[0].toFixed(2)},${p[1].toFixed(2)}`).join('L');
async function renderSvg(body, crisp = false) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${MASK_N}" height="${MASK_N}" viewBox="0 0 ${MASK_N} ${MASK_N}"`
    + `${crisp ? ' shape-rendering="crispEdges"' : ''}><rect width="100%" height="100%" fill="#000"/>${body}</svg>`;
  const { data } = await sharp(Buffer.from(svg), { limitInputPixels: false, density: 72 })
    .removeAlpha().extractChannel(0).raw().toBuffer({ resolveWithObject: true });
  return data;
}
const fillPaths = (items, test, fill = '#fff') => items.filter(test).filter(i => i.rings.length)
  .map(i => `<path d="${pathOf(i.rings)}" fill="${fill}" fill-rule="evenodd"/>`).join('');
const roadWidth = { motorway: 22, trunk: 16, primary: 12, secondary: 10, tertiary: 8, unclassified: 6, residential: 6,
  living_street: 5, service: 4, motorway_link: 8, trunk_link: 8, primary_link: 7, secondary_link: 7, tertiary_link: 6,
  pedestrian: 5, track: 3, cycleway: 2.5 };

function hash01(n) { const x = Math.sin(n * 12.9898) * 43758.5453; return x - Math.floor(x); }
// Row direction of a parcel: its longest edge, 0..1 for 0..pi.
function parcelAngle(ring) {
  let best = 0, angle = 0;
  for (let i = 1; i < ring.length; i++) {
    const dx = ring[i][0] - ring[i - 1][0], dy = ring[i][1] - ring[i - 1][1], l = dx * dx + dy * dy;
    if (l > best) { best = l; angle = Math.atan2(dy, dx); }
  }
  return ((angle % Math.PI) + Math.PI) % Math.PI / Math.PI;
}

async function build() {
  const copernicus = await loadCopernicus();
  const worldcover = await loadWorldCover();
  const satellite = await loadSatellite();
  const utmLL = (e, n) => toLatLon(e, n);

  // --- context grid: DEM, land cover class, satellite colour ---
  const ctxH = new Float32Array(CTX_N * CTX_N), ctxClass = new Uint8Array(CTX_N * CTX_N), ctxSat = new Float32Array(CTX_N * CTX_N * 3);
  for (let r = 0; r < CTX_N; r++) for (let c = 0; c < CTX_N; c++) {
    const e = CE - CTX_HALF + c * CTX_STEP, n = CN + CTX_HALF - r * CTX_STEP, [lat, lon] = utmLL(e, n), i = r * CTX_N + c;
    ctxH[i] = copernicus(lat, lon);
    ctxClass[i] = worldcover(lat, lon);
    const s = satellite(lat, lon);
    ctxSat.set(s, i * 3);
  }
  const histogram = {};
  for (const k of ctxClass) histogram[k] = (histogram[k] || 0) + 1;
  console.log('WorldCover classes (context):', JSON.stringify(histogram));
  assert(!histogram[0] || histogram[0] < ctxClass.length * 0.01, 'WorldCover decoding failed');
  // Lake Garda: WorldCover water at the lake level, given a bed so the water plane covers it.
  const lake = new Uint8Array(CTX_N * CTX_N);
  for (let i = 0; i < lake.length; i++) lake[i] = ctxClass[i] === 80 && ctxH[i] < LAKE_LEVEL + 12 ? 1 : 0;
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

  // --- OSM masks over the core (4 m) ---
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

  const mUrban = await renderSvg(fillPaths(items, urbanTest));
  const mVine = await renderSvg(fillPaths(items, vineTest));
  const mField = await renderSvg(fillPaths(items, fieldTest));
  const mMeadow = await renderSvg(fillPaths(items, meadowTest));
  const mForestOsm = await renderSvg(fillPaths(items, forestTest));
  const mRock = await renderSvg(fillPaths(items, rockTest)
    + items.filter(is('natural', 'cliff')).filter(i => i.line).map(i => `<path d="${lineOf(i.line)}" stroke="#fff" stroke-width="${12 / MASK_STEP}" fill="none"/>`).join(''));
  const mScrub = await renderSvg(fillPaths(items, scrubTest));
  const mWater = await renderSvg(fillPaths(items, waterTest)
    + items.filter(i => is('waterway', 'river', 'stream', 'canal')(i)).map(i => {
      const pts = i.line || i.closedLine; if (!pts) return '';
      const width = i.tags.waterway === 'river' ? 30 : i.tags.waterway === 'canal' ? 8 : 3;
      return `<path d="${lineOf(pts)}" stroke="#fff" stroke-width="${width / MASK_STEP}" stroke-linecap="round" fill="none"/>`;
    }).join(''));
  const mBuild = await renderSvg(fillPaths(items, buildingTest));
  const roadSvg = items.filter(i => roadWidth[i.tags.highway] && !i.tags.tunnel && (i.line || i.closedLine)).map(i => {
    const width = Math.max(roadWidth[i.tags.highway], (+i.tags.lanes || 0) * 3.2);
    return `<path d="${lineOf(i.line || i.closedLine)}" stroke="#fff" stroke-width="${width / MASK_STEP}" stroke-linecap="round" stroke-linejoin="round" fill="none"/>`;
  }).join('') + items.filter(i => i.tags.railway === 'rail' && i.line && !i.tags.tunnel)
    .map(i => `<path d="${lineOf(i.line)}" stroke="#fff" stroke-width="${6 / MASK_STEP}" fill="none"/>`).join('');
  const mRoad = await renderSvg(roadSvg);
  // Parcel row direction and a per-parcel seed for colour variation.
  const parcels = items.filter(i => (vineTest(i) || fieldTest(i) || meadowTest(i)) && i.rings.length);
  const grey = v => { const g = Math.round(Math.max(0, Math.min(1, v)) * 255); return `rgb(${g},${g},${g})`; };
  const mAngle = await renderSvg(parcels.map(i => `<path d="${pathOf(i.rings)}" fill="${grey(parcelAngle(i.rings[0]))}" fill-rule="evenodd"/>`).join(''), true);
  const mSeed = await renderSvg(parcels.concat(items.filter(i => buildingTest(i) && i.rings.length))
    .map(i => `<path d="${pathOf(i.rings)}" fill="${grey(0.04 + 0.96 * hash01(i.id))}" fill-rule="evenodd"/>`).join(''), true);
  const mKind = await renderSvg(parcels.map(i => `<path d="${pathOf(i.rings)}" fill="${is('landuse', 'orchard')(i) ? '#fff' : is('landuse', 'vineyard')(i) ? '#808080' : '#000'}" fill-rule="evenodd"/>`).join(''), true);

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

  // --- core heights: LiDAR, context DEM outside it and at the edge band, lake bed ---
  const lidar = loadLidar();
  const core = new Float32Array(CORE_N * CORE_N);
  let lidarCells = 0;
  for (let r = 0; r < CORE_N; r++) for (let c = 0; c < CORE_N; c++) {
    const x = -CORE_HALF + c * CORE_STEP, z = -CORE_HALF + r * CORE_STEP, i = r * CORE_N + c;
    const edge = Math.min(x + CORE_HALF, CORE_HALF - CORE_STEP - x, z + CORE_HALF, CORE_HALF - CORE_STEP - z);
    const w = Math.max(0, Math.min(1, edge / EDGE_BLEND)), s = w * w * (3 - 2 * w);
    const base = ctxAt(x, z);
    const fine = lidar[i];
    if (Number.isFinite(fine)) lidarCells++;
    core[i] = Number.isFinite(fine) ? base + (fine - base) * s : base;
  }
  // The lake: no bathymetry in either DEM. Carve under the OSM/WorldCover water of Garda.
  const lakeDist = distanceInside(coreLake, MASK_N, MASK_N);
  for (let r = 0; r < CORE_N; r++) for (let c = 0; c < CORE_N; c++) {
    const mi = Math.min(MASK_N - 1, r >> 1) * MASK_N + Math.min(MASK_N - 1, c >> 1), i = r * CORE_N + c;
    if (!coreLake[mi] || core[i] > LAKE_LEVEL + 6) continue;
    core[i] = Math.min(core[i], LAKE_LEVEL - Math.min(LAKE_MAX_DEPTH, 1.5 + lakeDist[mi] * MASK_STEP * 0.35));
  }
  console.log(`Core: LiDAR coverage ${(100 * lidarCells / core.length).toFixed(1)}%`);

  // --- satellite tint: low-pass colour relative to its land-cover class mean ---
  const satBlur = boxBlur(ctxSat, CTX_N, CTX_N, 3, 2); // ~3x5x30 m effective ~ 150 m
  const sums = {}, counts = {};
  for (let i = 0; i < ctxClass.length; i++) {
    const k = ctxClass[i]; sums[k] ??= [0, 0, 0]; counts[k] = (counts[k] || 0) + 1;
    for (let ch = 0; ch < 3; ch++) sums[k][ch] += satBlur[i * 3 + ch];
  }
  const tint = Buffer.alloc(CTX_N * CTX_N * 4);
  for (let i = 0; i < ctxClass.length; i++) {
    const k = ctxClass[i];
    for (let ch = 0; ch < 3; ch++) {
      const ratio = satBlur[i * 3 + ch] / Math.max(1, sums[k][ch] / counts[k]);
      tint[i * 4 + ch] = Math.round(Math.max(0, Math.min(1, ratio / 2)) * 255); // 128 = class mean
    }
    tint[i * 4 + 3] = 255;
  }

  // --- context albedo (sRGB), matching the core shader palette ---
  const palette = { 10: [44, 58, 30], 20: [88, 92, 54], 30: [92, 100, 58], 40: [122, 116, 74], 50: [128, 120, 110],
    60: [150, 146, 136], 70: [235, 238, 242], 80: [22, 44, 54], 90: [76, 88, 58], 95: [60, 80, 50], 100: [120, 120, 100], 0: [104, 112, 62] };
  const albedoPlain = Buffer.alloc(CTX_N * CTX_N * 4), albedoTint = Buffer.alloc(CTX_N * CTX_N * 4);
  for (let i = 0; i < ctxClass.length; i++) {
    const p = palette[ctxClass[i]] || palette[0];
    for (let ch = 0; ch < 3; ch++) {
      albedoPlain[i * 4 + ch] = p[ch];
      const lin = (p[ch] / 255) ** 2.2 * Math.max(0.7, Math.min(1.35, tint[i * 4 + ch] / 128));
      albedoTint[i * 4 + ch] = Math.round(Math.min(1, lin) ** (1 / 2.2) * 255);
    }
    albedoPlain[i * 4 + 3] = albedoTint[i * 4 + 3] = 255;
  }

  // --- write ---
  const raw = (name, arr) => fs.writeFileSync(path.join(OUT, name), Buffer.from(arr.buffer, arr.byteOffset, arr.byteLength));
  raw('core_height.r32', core);
  raw('context_height.r32', ctxH);
  const png = (name, buf, n) => sharp(buf, { raw: { width: n, height: n, channels: 4 } }).png().toFile(path.join(OUT, name));
  await png('masks_a.png', masksA, MASK_N);
  await png('masks_b.png', masksB, MASK_N);
  await png('masks_c.png', masksC, MASK_N);
  await png('tint.png', tint, CTX_N);
  await png('context_albedo_plain.png', albedoPlain, CTX_N);
  await png('context_albedo_tint.png', albedoTint, CTX_N);
  // Reference: raw satellite and a hillshade preview for review only.
  const satPreview = Buffer.alloc(CTX_N * CTX_N * 3);
  for (let i = 0; i < satPreview.length; i++) satPreview[i] = ctxSat[i];
  await sharp(satPreview, { raw: { width: CTX_N, height: CTX_N, channels: 3 } }).png().toFile(path.join(OUT, 'satellite_reference.png'));
  const manifest = { center_utm32: [CE, CN], lake_level: LAKE_LEVEL,
    core: { half: CORE_HALF, step: CORE_STEP, size: CORE_N, file: 'core_height.r32' },
    masks: { half: CORE_HALF, step: MASK_STEP, size: MASK_N },
    context: { half: CTX_HALF, step: CTX_STEP, size: CTX_N, file: 'context_height.r32' },
    world: 'x = E - center_e, z = center_n - N, y = metres above sea level' };
  fs.writeFileSync(path.join(OUT, 'manifest.json'), JSON.stringify(manifest, null, 2));
  console.log('Build complete:', OUT);
}

(async () => {
  const phase = process.argv[2] || 'all';
  if (phase === 'fetch' || phase === 'all') {
    await fetchCopernicus();
    await fetchWorldCover();
    await fetchOsm();
    await fetchSatellite();
    await fetchLidar();
  }
  if (phase === 'build' || phase === 'all') await build();
})().catch(e => { console.error(e); process.exit(1); });
