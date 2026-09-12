// DEM 3DEP + ortofoto allineati, quadrato UTM 250x250km (Henry Mountains, UT) — lavoro a blocchi.
// Fasi: node tools/fetch_utah_250km.cjs dem [maxNew] | img [maxNew] | build | all [maxNew]
// Richiede `npm i sharp` in tools/ (scarica binari precompilati, ~1 min)
// Cache riquadri in tools/tiles/, output in terrain/source/utah_250km/
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const sharp = require('sharp');

const LAT0 = 38.12, LON0 = -110.6, HALF = 125000, N = 8192;
const ROOT = path.resolve(__dirname, '..');
const OUT = path.join(ROOT, 'terrain', 'source', 'utah_250km');
const TILES = path.join(__dirname, 'tiles');
fs.mkdirSync(OUT, { recursive: true });
fs.mkdirSync(TILES, { recursive: true });
const PHASE = process.argv[2] || 'all';
const MAXNEW = parseInt(process.argv[3] || '1000000', 10);
const want = p => PHASE === 'all' || PHASE === p;
let newDownloads = 0;
function cached(tp, minSize) {
  try { return fs.statSync(tp).size > minSize ? fs.readFileSync(tp) : null; } catch { return null; }
}
function countCached(prefix) {
  try { return fs.readdirSync(TILES).filter(f => f.startsWith(prefix)).length; } catch { return 0; }
}

// ---------- UTM zona 12N ----------
function latLonToUtm(lat, lon, zone = 12) {
  const a = 6378137, f = 1 / 298.257223563, k0 = 0.9996;
  const e2 = 2 * f - f * f, ep2 = e2 / (1 - e2);
  const la = lat * Math.PI / 180, lo = lon * Math.PI / 180;
  const lo0 = ((zone - 1) * 6 - 180 + 3) * Math.PI / 180;
  const Nn = a / Math.sqrt(1 - e2 * Math.sin(la) ** 2);
  const T = Math.tan(la) ** 2, C = ep2 * Math.cos(la) ** 2, A = Math.cos(la) * (lo - lo0);
  const M = a * ((1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 ** 3 / 256) * la
    - (3 * e2 / 8 + 3 * e2 * e2 / 32 + 45 * e2 ** 3 / 1024) * Math.sin(2 * la)
    + (15 * e2 * e2 / 256 + 45 * e2 ** 3 / 1024) * Math.sin(4 * la)
    - (35 * e2 ** 3 / 3072) * Math.sin(6 * la));
  return {
    x: k0 * Nn * (A + (1 - T + C) * A ** 3 / 6 + (5 - 18 * T + T * T + 72 * C - 58 * ep2) * A ** 5 / 120) + 500000,
    y: k0 * (M + Nn * Math.tan(la) * (A * A / 2 + (5 - T + 9 * C + 4 * C * C) * A ** 4 / 24
      + (61 - 58 * T + T * T + 600 * C - 330 * ep2) * A ** 6 / 720)),
  };
}
function utmToLatLon(x, y, zone = 12) {
  const a = 6378137, f = 1 / 298.257223563, k0 = 0.9996;
  const e2 = 2 * f - f * f, ep2 = e2 / (1 - e2);
  const e1 = (1 - Math.sqrt(1 - e2)) / (1 + Math.sqrt(1 - e2));
  x -= 500000;
  const mu = (y / k0) / (a * (1 - e2 / 4 - 3 * e2 * e2 / 64 - 5 * e2 ** 3 / 256));
  const p1 = mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * Math.sin(2 * mu)
    + (21 * e1 * e1 / 16 - 55 * e1 ** 4 / 32) * Math.sin(4 * mu) + (151 * e1 ** 3 / 96) * Math.sin(6 * mu);
  const N1 = a / Math.sqrt(1 - e2 * Math.sin(p1) ** 2);
  const T1 = Math.tan(p1) ** 2, C1 = ep2 * Math.cos(p1) ** 2;
  const R1 = a * (1 - e2) / (1 - e2 * Math.sin(p1) ** 2) ** 1.5;
  const D = (x) / (N1 * k0);
  const lat = p1 - (N1 * Math.tan(p1) / R1) * (D * D / 2 - (5 + 3 * T1 + 10 * C1 - 4 * C1 * C1 - 9 * ep2) * D ** 4 / 24
    + (61 + 90 * T1 + 298 * C1 + 45 * T1 * T1 - 252 * ep2 - 3 * C1 * C1) * D ** 6 / 720);
  const lo0 = ((zone - 1) * 6 - 180 + 3) * Math.PI / 180;
  const lon = lo0 + (D - (1 + 2 * T1 + C1) * D ** 3 / 6
    + (5 - 2 * C1 + 28 * T1 - 3 * C1 * C1 + 8 * ep2 + 24 * T1 * T1) * D ** 5 / 120) / Math.cos(p1);
  return { lat: lat * 180 / Math.PI, lon: lon * 180 / Math.PI };
}

// ---------- fetch con retry ----------
async function get(url, label, tries = 4) {
  for (let i = 1; i <= tries; i++) {
    try {
      console.log(`  [${label}] tentativo ${i}...`);
      const r = await fetch(url, { signal: AbortSignal.timeout(900000) });
      if (!r.ok) {
        const t = await r.text().catch(() => '');
        throw new Error(`HTTP ${r.status} ${t.slice(0, 150)}`);
      }
      const b = Buffer.from(await r.arrayBuffer());
      console.log(`  [${label}] OK ${(b.length / 1048576).toFixed(1)} MB`);
      return b;
    } catch (e) {
      console.log(`  [${label}] errore: ${e.message}`);
      if (i === tries) throw e;
      await new Promise(r => setTimeout(r, 5000 * i));
    }
  }
}

// ---------- mini TIFF reader (classic TIFF LE, anche tiled, float32 non compresso) ----------
function readFloatTiff(buf, w, h) {
  if (buf.toString('ascii', 0, 4) !== 'II*\x00') throw new Error('TIFF non classico/LE');
  const u16 = o => buf.readUInt16LE(o), u32 = o => buf.readUInt32LE(o);
  const ifd = u32(4), n = u16(ifd);
  let offs = null, counts = null, tw = w, tl = h;
  for (let i = 0; i < n; i++) {
    const e = ifd + 2 + i * 12, tag = u16(e), typ = u16(e + 2), cnt = u32(e + 4), v = u32(e + 8);
    const arr = (t, c, o, s) => { const a = []; for (let k = 0; k < c; k++) a.push(t(o + k * s)); return a; };
    if (tag === 324 || tag === 273) offs = cnt === 1 ? [v] : arr(o => buf.readUInt32LE(o), cnt, v, 4);
    if (tag === 325 || tag === 279) counts = cnt === 1 ? [v] : arr(o => buf.readUInt32LE(o), cnt, v, 4);
    if (tag === 322) tw = typ === 3 ? u16(e + 8) : v;
    if (tag === 323) tl = typ === 3 ? u16(e + 8) : v;
    if (tag === 259 && u16(e + 8) !== 1) throw new Error('TIFF compresso, non gestito');
    if (tag === 258 && u16(e + 8) !== 32) throw new Error('bit depth non 32');
  }
  if (!offs) throw new Error('offset tile/strip assenti');
  const out = new Float32Array(w * h);
  const across = Math.ceil(w / tw);
  for (let t = 0; t < offs.length; t++) {
    const ab = new ArrayBuffer(counts[t]);
    Buffer.from(ab).set(buf.subarray(offs[t], offs[t] + counts[t]));
    const src = new Float32Array(ab);
    const tx = t % across, ty = (t / across) | 0;
    const cw = Math.min(tw, w - tx * tw), ch = Math.min(tl, h - ty * tl);
    for (let r = 0; r < ch; r++) out.set(src.subarray(r * tw, r * tw + cw), (ty * tl + r) * w + tx * tw);
  }
  return out;
}

// ---------- writer F32 GeoTIFF (EPSG:32612, una strip) ----------
function writeGeoTiffF32(px, w, h, xmin, ymax, pxSize) {
  const dataBytes = w * h * 4;
  const scale = [pxSize, pxSize, 0], tie = [0, 0, 0, xmin, ymax, 0];
  const keys = [1, 1, 0, 3, 1024, 0, 1, 1, 1025, 0, 1, 1, 3072, 0, 1, 32612];
  const tags = [256, 257, 258, 259, 262, 273, 277, 278, 279, 33550, 33922, 34735];
  const shorts = { 258: 32, 259: 1, 262: 1, 277: 1 };
  const ifdSize = 2 + tags.length * 12 + 4;
  const scaleOff = 8 + ifdSize, tieOff = scaleOff + 24, keysOff = tieOff + 48;
  const pixOff = keysOff + keys.length * 2;
  const buf = Buffer.allocUnsafe(pixOff + dataBytes);
  buf.write('II*\x00', 0); buf.writeUInt32LE(8, 4);
  buf.writeUInt16LE(tags.length, 8);
  tags.forEach((tag, i) => {
    const o = 10 + i * 12;
    buf.writeUInt16LE(tag, o);
    buf.writeUInt16LE(tag === 33550 || tag === 33922 ? 12 : tag === 34735 ? 3 : tag === 256 || tag === 257 || tag === 273 || tag === 278 || tag === 279 ? 4 : 3, o + 2);
    buf.writeUInt32LE(tag === 33550 ? 3 : tag === 33922 ? 6 : tag === 34735 ? keys.length : 1, o + 4);
    if (tag === 256) buf.writeUInt32LE(w, o + 8);
    else if (tag === 257) buf.writeUInt32LE(h, o + 8);
    else if (shorts[tag] !== undefined) buf.writeUInt16LE(shorts[tag], o + 8);
    else if (tag === 273) buf.writeUInt32LE(pixOff, o + 8);
    else if (tag === 278) buf.writeUInt32LE(h, o + 8);
    else if (tag === 279) buf.writeUInt32LE(dataBytes, o + 8);
    else if (tag === 33550) buf.writeUInt32LE(scaleOff, o + 8);
    else if (tag === 33922) buf.writeUInt32LE(tieOff, o + 8);
    else if (tag === 34735) buf.writeUInt32LE(keysOff, o + 8);
  });
  buf.writeUInt32LE(0, 10 + tags.length * 12);
  scale.forEach((v, i) => buf.writeDoubleLE(v, scaleOff + i * 8));
  tie.forEach((v, i) => buf.writeDoubleLE(v, tieOff + i * 8));
  keys.forEach((v, i) => buf.writeUInt16LE(v, keysOff + i * 2));
  Buffer.from(px.buffer, px.byteOffset, dataBytes).copy(buf, pixOff);
  return buf;
}

// ---------- writer PNG 16-bit grayscale (filtro Sub) ----------
function writePng16(gray, w, h) {
  const crcT = new Int32Array(256);
  for (let i = 0; i < 256; i++) { let c = i; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crcT[i] = c; }
  const crc = b => { let c = -1; for (let i = 0; i < b.length; i++) c = crcT[(c ^ b[i]) & 255] ^ (c >>> 8); return (c ^ -1) >>> 0; };
  const chunk = (type, data) => {
    const head = Buffer.alloc(8); head.writeUInt32BE(data.length, 0); head.write(type, 4);
    const tail = Buffer.alloc(4); tail.writeUInt32BE(crc(Buffer.concat([Buffer.from(type), data])), 0);
    return Buffer.concat([head, data, tail]);
  };
  const rowBytes = w * 2, raw = Buffer.allocUnsafe((rowBytes + 1) * h);
  for (let y = 0; y < h; y++) {
    const ro = y * (rowBytes + 1); raw[ro] = 1;
    for (let x = 0; x < w; x++) {
      const v = gray[y * w + x], o = ro + 1 + x * 2, p = x === 0 ? 0 : gray[y * w + x - 1];
      raw[o] = ((v >>> 8) - (p >>> 8)) & 255; raw[o + 1] = ((v & 255) - (p & 255)) & 255;
    }
    if (y % 2048 === 0) console.log(`  PNG16 riga ${y}/${h}`);
  }
  console.log('  compressione PNG16...');
  const idat = zlib.deflateSync(raw, { level: 6 });
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 16; ihdr[9] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', idat), chunk('IEND', Buffer.alloc(0))]);
}

function extractTiffPart(multipart) {
  const idx = multipart.toString('binary').indexOf('II*\x00');
  if (idx < 0) throw new Error('parte TIFF non trovata: ' + multipart.slice(0, 300).toString());
  return multipart.slice(idx);
}

(async () => {
  const c = latLonToUtm(LAT0, LON0);
  const xmin = c.x - HALF, xmax = c.x + HALF, ymin = c.y - HALF, ymax = c.y + HALF;
  const pxSize = (2 * HALF) / N;
  const DTE = 8, TPX = 1024, DT = (2 * HALF) / DTE;
  console.log(`fase=${PHASE} bbox UTM12N ${xmin.toFixed(0)} ${ymin.toFixed(0)} ${xmax.toFixed(0)} ${ymax.toFixed(0)} px=${pxSize.toFixed(4)}m`);
  const tiles = [];
  for (let ty = 0; ty < DTE; ty++) for (let tx = 0; tx < DTE; tx++) tiles.push([ty, tx]);
  const log = [];
  let failed = [];
  const urlfile = path.join(OUT, 'fetch_urls.txt');
  const noteUrl = (prefix, line) => {
    try {
      const prev = fs.existsSync(urlfile) ? fs.readFileSync(urlfile, 'utf8') : '';
      if (!prev.includes(prefix)) fs.appendFileSync(urlfile, line + '\n');
    } catch {}
  };
  const tileBox = (ty, tx) => [xmin + tx * DT, xmin + (tx + 1) * DT, ymax - (ty + 1) * DT, ymax - ty * DT];

  // ---- DEM ----
  if (want('dem')) {
    let stop = false;
    for (const [ty, tx] of tiles) {
      if (stop) break;
      const [x0, x1, y0, y1] = tileBox(ty, tx), nm = `r${ty}c${tx}`;
      const tp = path.join(TILES, `dem_${nm}.tif`);
      if (cached(tp, 100000)) continue;
      if (newDownloads >= MAXNEW) { stop = true; break; }
      const q = new URLSearchParams({
        service: 'WCS', version: '2.0.1', request: 'GetCoverage', coverageId: 'DEP3Elevation',
        format: 'image/tiff', outputCrs: 'http://www.opengis.net/def/crs/EPSG/0/32612',
        scalesize: `x(${TPX}),y(${TPX})`,
        interpolation: 'http://www.opengis.net/def/interpolation/OGC/1/cubic',
      });
      const url = 'https://elevation.nationalmap.gov/arcgis/services/3DEPElevation/ImageServer/WCSServer?'
        + q.toString() + `&subset=x(${x0},${x1})&subset=y(${y0},${y1})`;
      if (newDownloads === 0 && countCached('dem_r') === 0) noteUrl('WCS es.:', 'WCS es.: ' + url);
      try {
        const part = extractTiffPart(await get(url, 'DEM-' + nm));
        readFloatTiff(part, TPX, TPX); // valida subito
        fs.writeFileSync(tp, part);
        newDownloads++;
      } catch (e) { failed.push(nm); console.log(`  DEM-${nm} fallito, continuo: ${e.message}`); }
      await new Promise(r => setTimeout(r, 1500));
    }
    console.log(`DEM cache: ${countCached('dem_r')}/${DTE * DTE} (nuovi: ${newDownloads})${failed.length ? ' MANCANTI: ' + failed.join(',') : ''}`);
    if (PHASE === 'dem') return;
    newDownloads = 0;
  }

  // ---- IMG ----
  if (want('img')) {
    let stop = false;
    for (const [ty, tx] of tiles) {
      if (stop) break;
      const [x0, x1, y0, y1] = tileBox(ty, tx), nm = `r${ty}c${tx}`;
      const tp = path.join(TILES, `img_${nm}.png`);
      if (cached(tp, 50000)) continue;
      if (newDownloads >= MAXNEW) { stop = true; break; }
      const q = new URLSearchParams({
        bbox: `${x0},${y0},${x1},${y1}`, bboxSR: '32612', imageSR: '32612',
        size: `${TPX},${TPX}`, format: 'png', f: 'image',
      });
      const url = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/export?' + q.toString();
      if (newDownloads === 0 && countCached('img_r') === 0) noteUrl('IMG es.:', 'IMG es.: ' + url);
      try {
        const buf = await get(url, 'IMG-' + nm);
        const m = await sharp(buf).metadata();
        if (m.width !== TPX || m.height !== TPX) throw new Error(`tile ${nm}: ${m.width}x${m.height}`);
        fs.writeFileSync(tp, buf);
        newDownloads++;
      } catch (e) { failed.push(nm); console.log(`  IMG-${nm} fallito, continuo: ${e.message}`); }
      await new Promise(r => setTimeout(r, 800));
    }
    console.log(`IMG cache: ${countCached('img_r')}/${DTE * DTE} (nuovi: ${newDownloads})${failed.length ? ' MANCANTI: ' + failed.join(',') : ''}`);
    if (PHASE === 'img') return;
  }

  // ---- BUILD ----
  if (countCached('dem_r') !== DTE * DTE || countCached('img_r') !== DTE * DTE) {
    console.log('cache incompleta: completa le fasi dem/img prima di build');
    process.exit(2);
  }
  console.log('assemblaggio DEM da cache...');
  const dem = new Float32Array(N * N);
  for (const [ty, tx] of tiles) {
    const f = readFloatTiff(fs.readFileSync(path.join(TILES, `dem_r${ty}c${tx}.tif`)), TPX, TPX);
    for (let r = 0; r < TPX; r++) dem.set(f.subarray(r * TPX, (r + 1) * TPX), (ty * TPX + r) * N + tx * TPX);
  }
  let mn = Infinity, mx = -Infinity, bad = 0, sum = 0, cnt = 0;
  for (let i = 0; i < dem.length; i++) {
    const v = dem[i];
    if (!Number.isFinite(v) || v < -500) { bad++; continue; }
    if (v < mn) mn = v; if (v > mx) mx = v; sum += v; cnt++;
  }
  console.log(`DEM stats: min=${mn.toFixed(2)} max=${mx.toFixed(2)} media=${(sum / cnt).toFixed(1)} anomali=${bad}`);
  console.log('scrittura master F32...');
  fs.writeFileSync(path.join(OUT, 'utah_250km_dem_8192_f32.tif'), writeGeoTiffF32(dem, N, N, xmin, ymax, pxSize));
  fs.writeFileSync(path.join(OUT, 'utah_250km_dem_8192_f32.tfw'),
    `${pxSize.toFixed(10)}\n0\n0\n${(-pxSize).toFixed(10)}\n${(xmin + pxSize / 2).toFixed(4)}\n${(ymax - pxSize / 2).toFixed(4)}\n`);
  console.log('normalizzazione 16-bit...');
  const u16a = new Uint16Array(N * N), span = mx - mn;
  for (let i = 0; i < dem.length; i++) {
    const v = dem[i];
    u16a[i] = !Number.isFinite(v) || v < -500 ? 0 : Math.round((Math.min(Math.max(v, mn), mx) - mn) / span * 65535);
  }
  fs.writeFileSync(path.join(OUT, 'utah_250km_height_8192_u16.png'), writePng16(u16a, N, N));
  fs.writeFileSync(path.join(OUT, 'utah_250km_worldmachine.r16'), Buffer.from(u16a.buffer, u16a.byteOffset, u16a.byteLength));
  console.log('mosaico color 8192...');
  const imgs = tiles.map(([ty, tx]) => ({
    input: path.join(TILES, `img_r${ty}c${tx}.png`), left: tx * TPX, top: ty * TPX,
  }));
  await sharp({ create: { width: N, height: N, channels: 3, background: '#000' } })
    .composite(imgs).png({ compressionLevel: 6 }).toFile(path.join(OUT, 'utah_250km_color_8192.png'));
  fs.writeFileSync(path.join(OUT, 'utah_250km_color_8192.pgw'),
    `${pxSize.toFixed(10)}\n0\n0\n${(-pxSize).toFixed(10)}\n${(xmin + pxSize / 2).toFixed(4)}\n${(ymax - pxSize / 2).toFixed(4)}\n`);
  console.log('preview...');
  await sharp(path.join(OUT, 'utah_250km_color_8192.png')).resize(2048, 2048).jpeg({ quality: 88 })
    .toFile(path.join(OUT, 'utah_250km_preview.jpg'));
  await sharp(path.join(OUT, 'utah_250km_height_8192_u16.png')).resize(1024, 1024)
    .toFile(path.join(OUT, 'utah_250km_dem_preview.png'));
  const corners = { NW: utmToLatLon(xmin, ymax), NE: utmToLatLon(xmax, ymax), SE: utmToLatLon(xmax, ymin), SW: utmToLatLon(xmin, ymin) };
  const f = (p) => `${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}`;
  fs.writeFileSync(path.join(OUT, 'utah_250km_info.txt'),
    `UTAH 250KM x 250KM - HENRY MOUNTAINS (World Creator ready)\n` +
    `============================================================\n\n` +
    `1. CENTRO\n-----------\n- Decimale: ${LAT0.toFixed(4)} N, ${Math.abs(LON0).toFixed(4)} W\n` +
    `- UTM zona 12N (EPSG:32612): E=${c.x.toFixed(3)} N=${c.y.toFixed(3)}\n\n` +
    `2. BOUNDING BOX (EPSG:32612, identico per DEM e color)\n------------------------------------------------------\n` +
    `- Xmin/Xmax: ${xmin.toFixed(3)} / ${xmax.toFixed(3)}\n- Ymin/Ymax: ${ymin.toFixed(3)} / ${ymax.toFixed(3)}\n` +
    `- Angoli lat/lon: NW ${f(corners.NW)} | NE ${f(corners.NE)} | SE ${f(corners.SE)} | SW ${f(corners.SW)}\n\n` +
    `3. GRIGLIA\n----------\n- Raster: ${N} x ${N} px, riga 0 = NORD (top-down, nessun flip)\n` +
    `- Passo: ${pxSize.toFixed(4)} m/px (250000 m / 8192)\n- Allineamento: DEM e color condividono bbox e griglia, pixel coincidenti\n\n` +
    `4. ALTIMETRIA (metri reali)\n---------------------------\n- Min: ${mn.toFixed(2)} m | Max: ${mx.toFixed(2)} m | Escursione: ${(mx - mn).toFixed(2)} m\n` +
    `- Celle anomale escluse dalla normalizzazione: ${bad}\n\n` +
    `5. FONTI E LICENZE\n------------------\n- DEM: USGS 3DEP (National Map WCS, mosaico best-available ~10 m ricampionato cubico a 30.5 m), pubblico dominio USA\n` +
    `- Color: Esri World Imagery (su Utah rurale = quasi tutto NAIP/USDA 0.6-1 m + Landsat/Sentinel dove manca), ricampionata a 30.5 m\n` +
    `  Termini Esri: uso consentito con attribuzione "Esri, Maxar, Earthstar Geographics, USDA FSA"; per ridistribuzione commerciale verificare i termini vigenti\n\n` +
    `6. FILE\n-------\n- utah_250km_dem_8192_f32.tif (+.tfw): master float32 in metri, EPSG:32612\n` +
    `- utah_250km_height_8192_u16.png: heightmap 16-bit, 0=${mn.toFixed(2)} m, 65535=${mx.toFixed(2)} m\n` +
    `- utah_250km_worldmachine.r16: RAW uint16 LE, ${(N * N * 2 / 1048576).toFixed(1)} MB\n` +
    `- utah_250km_color_8192.png (+.pgw): ortofoto RGB stesso bbox/griglia\n` +
    `- utah_250km_preview.jpg / utah_250km_dem_preview.png: anteprime\n\n` +
    `7. IMPORT IN WORLD CREATOR (File Input heightmap)\n------------------------------------------------\n` +
    `- File: utah_250km_worldmachine.r16 | Type RAW16 unsigned LE | ${N}x${N}\n` +
    `- Extent: 250 x 250 km | Alt min ${mn.toFixed(2)} m, max ${mx.toFixed(2)} m | Flip Y deselezionato\n` +
    `- Color map overlay: utah_250km_color_8192.png sullo stesso extent\n`);
  try {
    const urls = fs.existsSync(urlfile) ? fs.readFileSync(urlfile, 'utf8') : log.join('\n');
    fs.writeFileSync(path.join(OUT, 'fetch_log.txt'), 'bbox UTM12N ' + [xmin, ymin, xmax, ymax].map(v => v.toFixed(1)).join(' ') + '\n' + urls);
  } catch {}
  console.log('\nFATTO. File in ' + OUT);
  for (const name of fs.readdirSync(OUT)) {
    const st = fs.statSync(path.join(OUT, name));
    console.log(' ', (st.size / 1048576).toFixed(1).padStart(8) + ' MB  ' + name);
  }
})().catch(e => { console.error('FALLITO:', e.message || e); process.exit(1); });
