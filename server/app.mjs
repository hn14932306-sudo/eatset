import { createServer } from 'node:http';
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { isIP } from 'node:net';
import { gzipSync } from 'node:zlib';
import { UsageStore } from './limits.mjs';
import { verifiedMenu } from './menu-links.mjs';

const fields = ['id','displayName','primaryTypeDisplayName','location','formattedAddress','rating','userRatingCount','priceLevel','currentOpeningHours','types','businessStatus','attributions'];
const fieldsWithPhotos = [...fields, 'photos', 'websiteUri'];
const idPattern = /^[A-Za-z0-9_-]{1,256}$/;
// The signature only stops arbitrary proxying; it is not Google's photo lifetime
// and is deliberately longer than place-data freshness so a browsing session does
// not pay for a second photo-list lookup.
const PHOTO_TTL_MS = 30 * 60 * 1000;
// Photo requests are billed per call, not per pixel: pick the size by use.
const photoSizes = { card: 'maxWidthPx=1000&maxHeightPx=750', thumb: 'maxWidthPx=400&maxHeightPx=300' };
const photoPattern = /^places\/[A-Za-z0-9_-]{1,256}\/photos\/[A-Za-z0-9_-]{1,2048}$/;
class ApiError extends Error { constructor(status, code) { super(code); this.status = status; this.code = code; } }
const safeLink = value => {
  try { const u = new URL(value.startsWith('//') ? `https:${value}` : value); return u.protocol === 'https:' && !u.username && !u.password ? u.href : undefined; } catch { return undefined; }
};
const normalizeIP = ip => ip?.startsWith('::ffff:') ? ip.slice(7) : ip;
export function clientIP(req, config) {
  let ip = normalizeIP(req.socket.remoteAddress) ?? 'unknown';
  // Only explicitly trusted peers may provide forwarding headers. Walk from
  // the nearest proxy; a client's injected left-hand address is never trusted.
  const chain = String(req.headers['x-forwarded-for'] ?? '').split(',').map(v => normalizeIP(v.trim())).filter(Boolean);
  while (config.trustedProxies.includes(ip) && chain.length) {
    const previous = chain.pop();
    if (!isIP(previous)) throw new ApiError(400, 'INVALID_REQUEST');
    ip = previous;
  }
  return ip;
}
function signPhoto(name, secret, now) {
  const payload = Buffer.from(JSON.stringify({ name, expires: now + PHOTO_TTL_MS })).toString('base64url');
  return `${payload}.${createHmac('sha256', secret).update(payload).digest('base64url')}`;
}
function verifyPhoto(token, secret, now) {
  if (typeof token !== 'string' || token.length > 4096) throw new ApiError(400, 'INVALID_REQUEST');
  const [payload, signature, extra] = token.split('.');
  const expected = createHmac('sha256', secret).update(payload ?? '').digest();
  const received = Buffer.from(signature ?? '', 'base64url');
  if (extra || received.length !== expected.length || !timingSafeEqual(expected, received)) throw new ApiError(403, 'INVALID_PHOTO');
  let data;
  try { data = JSON.parse(Buffer.from(payload, 'base64url').toString()); } catch { throw new ApiError(403, 'INVALID_PHOTO'); }
  if (!photoPattern.test(data.name) || !Number.isFinite(data.expires) || data.expires <= now || data.expires > now + PHOTO_TTL_MS) throw new ApiError(403, 'INVALID_PHOTO');
  return data.name;
}
function cleanPlace(p) {
  const result = {};
  for (const f of fields) if (Object.hasOwn(p, f)) result[f] = p[f];
  return result;
}
async function readBody(req) {
  if (!String(req.headers['content-type'] ?? '').startsWith('application/json')) throw new ApiError(415, 'JSON_REQUIRED');
  const chunks = []; let size = 0;
  for await (const chunk of req) { size += chunk.length; if (size > 8192) throw new ApiError(413, 'BODY_TOO_LARGE'); chunks.push(chunk); }
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!body || Array.isArray(body) || typeof body !== 'object') throw new Error();
    return body;
  } catch { throw new ApiError(400, 'INVALID_REQUEST'); }
}
async function limitedBytes(response, maximum) {
  if (Number(response.headers.get('content-length') ?? 0) > maximum) { await response.body?.cancel(); throw new ApiError(502, 'UPSTREAM_FAILED'); }
  const chunks = []; let size = 0;
  for await (const chunk of response.body ?? []) {
    size += chunk.length;
    if (size > maximum) throw new ApiError(502, 'UPSTREAM_FAILED');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}
export function createApp(config, { fetchImpl = fetch, now = Date.now, store } = {}) {
  const secret = config.secret || randomBytes(32).toString('hex');
  const usage = store ?? new UsageStore(config.dbPath, secret);
  let inFlight = 0;
  let lastCleanup = 0;
  function photoList(place) {
    return (place.photos ?? []).filter(p => photoPattern.test(p.name) && p.name.split('/')[1] === place.id).slice(0,3).map(p => ({
      name: p.name, token: signPhoto(p.name, secret, now()),
      authorAttributions: (p.authorAttributions ?? []).map(a => ({ displayName: a.displayName, uri: safeLink(a.uri) })),
      googleMapsUri: safeLink(p.googleMapsUri), flagContentUri: safeLink(p.flagContentUri),
    }));
  }
  const placeWithPhotos = p => {
    const menu = verifiedMenu(p.id, now());
    return {
      ...cleanPlace(p), photos: photoList(p), photosExpiresAt: now() + PHOTO_TTL_MS,
      websiteUri: safeLink(p.websiteUri),
      ...(menu ? { menuUri: menu.url, menuNote: menu.note } : {}),
    };
  };
  async function google(path, { method = 'GET', body, mask, kind }) {
    if (!config.apiKey) throw new ApiError(503, 'SERVICE_NOT_CONFIGURED');
    // Photos have their own daily pool so they can never starve search/details.
    const photoPool = kind === 'photo' || kind === 'photo_list';
    if (!usage.allowGoogle(photoPool ? config.dailyPhoto : config.dailyGoogle, now(), photoPool ? 'photo' : 'core')) { usage.record(kind, 'daily_limit', now()); throw new ApiError(429, 'DAILY_LIMIT'); }
    usage.record(kind, 'attempt', now());
    try {
      const response = await fetchImpl(`https://places.googleapis.com/v1/${path}`, {
        method, redirect: 'error', signal: AbortSignal.timeout(12000),
        headers: { 'X-Goog-Api-Key': config.apiKey, ...(mask ? { 'X-Goog-FieldMask': mask } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}) },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      if (!response.ok) { await response.body?.cancel(); throw new ApiError(response.status === 404 ? 404 : 502, response.status === 404 ? 'PLACE_NOT_FOUND' : 'UPSTREAM_FAILED'); }
      const data = JSON.parse((await limitedBytes(response, 1024 * 1024)).toString('utf8'));
      usage.record(kind, 'success', now());
      return data;
    } catch (error) {
      usage.record(kind, 'failure', now());
      if (error instanceof ApiError) throw error;
      throw new ApiError(502, 'UPSTREAM_FAILED');
    }
  }
  const server = createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    let admitted = false;
    const send = (status, body) => {
      const payload = Buffer.from(JSON.stringify(body));
      const headers = { 'Content-Type': 'application/json; charset=utf-8' };
      const vary = res.getHeader('Vary');
      res.setHeader('Vary', vary ? `${vary}, Accept-Encoding` : 'Accept-Encoding');
      if (payload.length > 1024 && /\bgzip\b/.test(String(req.headers['accept-encoding'] ?? ''))) {
        headers['Content-Encoding'] = 'gzip';
        res.writeHead(status, headers); return res.end(gzipSync(payload));
      }
      res.writeHead(status, headers); res.end(payload);
    };
    try {
      const url = new URL(req.url, 'http://local');
      if (url.pathname === '/healthz' && req.method === 'GET') return send(200, { ok: true });
      const origin = req.headers.origin;
      if (origin && !config.origins.includes(origin)) throw new ApiError(403, 'ORIGIN_NOT_ALLOWED');
      if (origin) { res.setHeader('Access-Control-Allow-Origin', origin); res.setHeader('Vary', 'Origin'); }
      if (req.method === 'OPTIONS') {
        res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
        res.writeHead(204); return res.end();
      }
      if (url.search) throw new ApiError(400, 'INVALID_REQUEST');
      if (now() - lastCleanup > 60000) { usage.cleanup(now()); lastCleanup = now(); }
      if (!usage.allowClient(clientIP(req, config), config, now())) { res.setHeader('Retry-After', '60'); throw new ApiError(429, 'CLIENT_LIMIT'); }
      if (inFlight >= config.concurrent) throw new ApiError(503, 'BUSY');
      inFlight++; admitted = true;
      if (url.pathname === '/v1/nearby' && req.method === 'POST') {
        const b = await readBody(req);
        const { lat, lng, radiusMeters = 1200 } = b;
        if (Object.keys(b).some(k => !['lat','lng','radiusMeters'].includes(k)) || typeof lat !== 'number' || !Number.isFinite(lat) || Math.abs(lat) > 90 || typeof lng !== 'number' || !Number.isFinite(lng) || Math.abs(lng) > 180 || !Number.isInteger(radiusMeters) || radiusMeters < 100 || radiusMeters > 2000) throw new ApiError(400, 'INVALID_REQUEST');
        const data = await google('places:searchNearby', { method: 'POST', mask: fieldsWithPhotos.map(f => `places.${f}`).join(','), kind: 'nearby', body: {
          includedTypes: ['restaurant'], languageCode: 'zh-TW', maxResultCount: 20,
          locationRestriction: { circle: { center: { latitude: lat, longitude: lng }, radius: radiusMeters } },
        } });
        return send(200, { places: (data.places ?? []).filter(p => idPattern.test(p.id)).slice(0,20).map(placeWithPhotos) });
      }
      const route = url.pathname.match(/^\/v1\/places\/([A-Za-z0-9_-]{1,256})(\/photos)?$/);
      if (route && req.method === 'GET') {
        const [, id, photos] = route;
        const data = await google(`places/${id}?languageCode=zh-TW`, { mask: photos ? 'id,photos' : fieldsWithPhotos.join(','), kind: photos ? 'photo_list' : 'details' });
        if (data.id !== id) throw new ApiError(502, 'UPSTREAM_FAILED');
        if (!photos) return send(200, placeWithPhotos(data));
        const list = photoList(data);
        return send(200, { id, photos: list });
      }
      if (url.pathname === '/v1/photo' && req.method === 'POST') {
        const body = await readBody(req);
        if (Object.keys(body).some(k => !['token', 'size'].includes(k))) throw new ApiError(400, 'INVALID_REQUEST');
        const size = body.size ?? 'card';
        if (!Object.hasOwn(photoSizes, size)) throw new ApiError(400, 'INVALID_REQUEST');
        const name = verifyPhoto(body.token, secret, now());
        const data = await google(`${name}/media?${photoSizes[size]}&skipHttpRedirect=true`, { kind: 'photo' });
        const uri = safeLink(data.photoUri);
        if (!uri || !['googleusercontent.com','ggpht.com','gstatic.com'].some(h => new URL(uri).hostname === h || new URL(uri).hostname.endsWith(`.${h}`))) throw new ApiError(502, 'UPSTREAM_FAILED');
        const image = await fetchImpl(uri, { redirect: 'error', signal: AbortSignal.timeout(12000) });
        const type = image.headers.get('content-type')?.split(';')[0];
        if (!image.ok || !['image/jpeg','image/png','image/webp','image/gif','image/avif'].includes(type)) { await image.body?.cancel(); throw new ApiError(502, 'UPSTREAM_FAILED'); }
        const bytes = await limitedBytes(image, 8 * 1024 * 1024);
        if (!bytes.length) throw new ApiError(502, 'UPSTREAM_FAILED');
        res.writeHead(200, { 'Content-Type': type }); return res.end(bytes);
      }
      throw new ApiError(404, 'NOT_FOUND');
    } catch (error) {
      const status = error instanceof ApiError ? error.status : 503;
      // No upstream body, raw URL, IP, coordinates, credential, or stack trace.
      if (!res.headersSent) send(status, { error: { code: error instanceof ApiError ? error.code : 'SERVICE_UNAVAILABLE' } });
      else res.end();
    } finally { if (admitted) inFlight--; }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  return { server, usage };
}
