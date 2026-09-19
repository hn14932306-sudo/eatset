import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp, clientIP } from '../app.mjs';
import { configFromEnv } from '../config.mjs';
import { UsageStore } from '../limits.mjs';
import { verifiedMenu } from '../menu-links.mjs';
const baseConfig = { ...configFromEnv({}), apiKey: 'test-key-only', secret: 'test-signing-secret-at-least-32-characters', dbPath: ':memory:' };
const json = data => new Response(JSON.stringify(data), { headers: { 'content-type': 'application/json' } });

test('menu links require an exact reviewed place ID and expire', () => {
  const at = Date.UTC(2026, 8, 19);
  assert.equal(verifiedMenu('unknown', at), null);
  assert.equal(verifiedMenu('ChIJD5KtvxQfaDQR_eYa8OJOZM0', at).url, 'https://www.ikea.com.tw/zh/store/tao-yuan/ikea-food-and-beverage');
  assert.equal(verifiedMenu('ChIJD5KtvxQfaDQR_eYa8OJOZM0', at + 90 * 86400000), null);
});

test('details return at most three photos and only curated menus with safe websites', async t => {
  const app = await start(t, {}, {
    now: () => Date.UTC(2026, 8, 19),
    fetchImpl: async (url, init) => {
      assert(init.headers['X-Goog-FieldMask'].split(',').includes('websiteUri'));
      const id = new URL(url).pathname.split('/').at(-1);
      return json({ id, websiteUri: id === 'unknown' ? 'javascript:bad' : 'https://www.ikea.com.tw', menuUri: 'https://unverified.example/menu', photos: Array.from({length: 10}, (_, i) => ({name: `places/${id}/photos/p${i}`})) });
    },
  });
  const p = await (await app.get('/v1/places/ChIJD5KtvxQfaDQR_eYa8OJOZM0')).json();
  assert.equal(p.photos.length, 3);
  assert.equal(p.websiteUri, 'https://www.ikea.com.tw/');
  assert.equal(p.menuUri, 'https://www.ikea.com.tw/zh/store/tao-yuan/ikea-food-and-beverage');
  const unknown = await (await app.get('/v1/places/unknown')).json();
  assert.equal(unknown.websiteUri, undefined);
  assert.equal(unknown.menuUri, undefined);
});
async function start(t, overrides = {}, deps = {}) {
  const app = createApp({ ...baseConfig, ...overrides }, deps);
  app.server.listen(0, '127.0.0.1'); await once(app.server, 'listening');
  t.after(async () => { app.server.closeAllConnections(); await new Promise(resolve => app.server.close(resolve)); app.usage.close(); });
  const address = `http://127.0.0.1:${app.server.address().port}`;
  return { ...app, get: (path, headers) => fetch(address + path, { headers }), post: (path, body, headers) => fetch(address + path, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body) }) };
}

test('production fails closed without persistent storage and secrets', () => {
  assert.throws(() => configFromEnv({ NODE_ENV: 'production' }));
  assert.throws(() => configFromEnv({ CLIENT_REQUESTS_PER_MINUTE: '-1' }));
  assert.throws(() => configFromEnv({ TRUSTED_PROXY_IPS: '*' }));
  assert.equal(configFromEnv({ NODE_ENV: 'production', GOOGLE_PLACES_API_KEY: 'test', SERVER_SECRET: 'x'.repeat(32), DB_PATH: '/data/usage.sqlite' }).production, true);
});

test('request limits can be disabled in development but not production', () => {
  const env = { CLIENT_REQUESTS_PER_MINUTE: '0', CLIENT_REQUESTS_PER_DAY: '0', GOOGLE_REQUESTS_PER_DAY: '0', GOOGLE_PHOTO_REQUESTS_PER_DAY: '0' };
  const config = configFromEnv(env);
  assert.equal(config.perMinute, 0);
  assert.equal(config.perDay, 0);
  assert.equal(config.dailyGoogle, 0);
  assert.equal(config.dailyPhoto, 0);
  const production = { NODE_ENV: 'production', GOOGLE_PLACES_API_KEY: 'test', SERVER_SECRET: 'x'.repeat(32), DB_PATH: '/data/usage.sqlite' };
  for (const key of Object.keys(env)) {
    assert.throws(() => configFromEnv({ ...production, [key]: '0' }), new RegExp(key));
    assert.throws(() => configFromEnv({ [key]: '-1' }), new RegExp(key));
  }
});

test('disabled minute cap allows photo browsing beyond 30 requests and retains counters', async t => {
  const at = Date.UTC(2026, 8, 19);
  const app = await start(t, { perDay: 0, dailyGoogle: 0, perMinute: 0 }, {
    now: () => at,
    fetchImpl: async () => json({ id: 'place_a', photos: [] }),
  });
  for (let i = 0; i < 35; i++) {
    assert.equal((await app.get('/v1/places/place_a/photos')).status, 200);
  }
  assert.equal(app.usage.allowClient('127.0.0.1', { perMinute: 30, perDay: 0 }, at), false);
  assert.equal(app.usage.db.prepare("SELECT count FROM usage WHERE kind='photo_list' AND outcome='attempt'").get().count, 35);
});

test('disabled daily caps allow requests beyond old cap while retaining counters and minute limit', async t => {
  const at = Date.UTC(2026, 8, 19);
  const app = await start(t, { perDay: 0, dailyGoogle: 0, perMinute: 3 }, {
    now: () => at,
    fetchImpl: async () => json({ id: 'place_a' }),
  });
  assert.equal(app.usage.allowGoogle(1, at), true);
  assert.equal(app.usage.allowGoogle(1, at), false);
  for (let i = 0; i < 3; i++) assert.equal((await app.get('/v1/places/place_a')).status, 200);
  const limited = await app.get('/v1/places/place_a');
  assert.equal(limited.status, 429);
  assert.deepEqual(await limited.json(), { error: { code: 'CLIENT_LIMIT' } });
  assert.equal(app.usage.allowGoogle(4, at), false);
  assert.equal(app.usage.allowClient('127.0.0.1', { perMinute: 30, perDay: 3 }, at + 60000), false);
  assert.equal(app.usage.db.prepare("SELECT count FROM usage WHERE outcome='attempt'").get().count, 3);
});

test('nearby has fixed mask, bounded search, and only returns allowlisted content', async t => {
  let calls = 0;
  const app = await start(t, {}, { fetchImpl: async (url, init) => {
    calls++; assert.equal(url, 'https://places.googleapis.com/v1/places:searchNearby');
    assert.equal(init.headers['X-Goog-Api-Key'], 'test-key-only');
    assert.equal(init.redirect, 'error');
    const b = JSON.parse(init.body);
    assert.equal(b.maxResultCount, 20); assert.deepEqual(b.includedTypes, ['restaurant']);
    assert.equal(b.locationRestriction.circle.radius, 1200);
    assert(!init.headers['X-Goog-FieldMask'].includes('*'));
    return json({ places: [{ id: 'place_a', displayName: { text: '餐廳' }, privateData: 'omit' }] });
  } });
  for (const body of [{ lat: 100, lng: 121 }, { lat: 25, lng: 121, radiusMeters: 50000 }, { lat: 25, lng: 121, fields: '*' }]) {
    assert.equal((await app.post('/v1/nearby', body)).status, 400);
  }
  assert.equal(calls, 0);
  const response = await app.post('/v1/nearby', { lat: 25, lng: 121 });
  assert.equal(response.status, 200); assert.equal(response.headers.get('cache-control'), 'no-store');
  const data = await response.json();
  assert.deepEqual(data.places[0].photos, []);
  assert(data.places[0].photosExpiresAt > Date.now());
  delete data.places[0].photos;
  delete data.places[0].photosExpiresAt;
  assert.deepEqual(data, { places: [{ id: 'place_a', displayName: { text: '餐廳' } }] });
  assert.equal(calls, 1);
});

test('nearby photo metadata can load a photo without a separate details request', async t => {
  const calls = [];
  const app = await start(t, {}, { fetchImpl: async (url, init) => {
    calls.push(url);
    if (url.endsWith('places:searchNearby')) {
      assert(init.headers['X-Goog-FieldMask'].split(',').includes('places.photos'));
      return json({ places: [{ id: 'place_a', photos: [
        { name: 'places/place_a/photos/photo_1', authorAttributions: [{ displayName: 'Author' }] },
        { name: 'places/other/photos/wrong' },
      ] }] });
    }
    if (url.includes('/media?')) return json({ photoUri: 'https://lh3.googleusercontent.com/photo' });
    assert.equal(url, 'https://lh3.googleusercontent.com/photo');
    return new Response(new Uint8Array([1,2,3]), { headers: { 'content-type': 'image/jpeg' } });
  } });
  const data = await (await app.post('/v1/nearby', { lat: 25, lng: 121 })).json();
  assert.equal(data.places[0].photos.length, 1);
  const photo = data.places[0].photos[0];
  assert.equal(photo.authorAttributions[0].displayName, 'Author');
  assert.equal((await app.post('/v1/photo', { token: photo.token })).status, 200);
  assert.equal(calls.filter(url => url.startsWith('https://places.googleapis.com')).length, 2);
});

test('upstream failure never exposes credential or response body', async t => {
  const app = await start(t, {}, { fetchImpl: async () => new Response('test-key-only secret detailed exception', { status: 403 }) });
  const response = await app.get('/v1/places/place_a');
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: { code: 'UPSTREAM_FAILED' } });
});

test('unconfigured backend does not issue Google calls', async t => {
  let called = false;
  const app = await start(t, { apiKey: '' }, { fetchImpl: async () => { called = true; throw Error(); } });
  assert.equal((await app.get('/v1/places/place_a')).status, 503);
  assert.equal(called, false);
});

test('photos require an issued unexpired signature; CDN receives no Google key', async t => {
  let time = Date.UTC(2026,8,19); const calls = [];
  const app = await start(t, {}, { now: () => time, fetchImpl: async (url, init) => {
    calls.push(url);
    if (url.endsWith('/places/place_a?languageCode=zh-TW')) return json({ id: 'place_a', photos: [{ name: 'places/place_a/photos/photo_1', authorAttributions: [{ displayName: 'A', uri: 'https://maps.google.com/contrib/a' }], googleMapsUri: 'https://maps.google.com/photo/1', flagContentUri: 'javascript:alert(1)' }, { name: 'places/other/photos/wrong' }] });
    if (url.includes('/media?')) return json({ photoUri: 'https://lh3.googleusercontent.com/image' });
    assert.equal(init.headers, undefined); assert.equal(init.redirect, 'error');
    return new Response(new Uint8Array([1,2,3]), { headers: { 'content-type': 'image/png' } });
  } });
  const { photos } = await (await app.get('/v1/places/place_a/photos')).json();
  assert.equal(photos.length, 1); assert.equal(photos[0].flagContentUri, undefined);
  assert.equal((await app.post('/v1/photo', { token: `${photos[0].token}x` })).status, 403);
  assert.equal(calls.length, 1);
  const image = await app.post('/v1/photo', { token: photos[0].token });
  assert.equal(image.status, 200); assert.equal(image.headers.get('content-type'), 'image/png');
  assert.deepEqual(new Uint8Array(await image.arrayBuffer()), new Uint8Array([1,2,3]));
  time += 30 * 60 * 1000 + 1;
  assert.equal((await app.post('/v1/photo', { token: photos[0].token })).status, 403);
  assert.equal(calls.length, 3);
});

test('non-Google image host is rejected before a network request', async t => {
  let calls = 0;
  const app = await start(t, {}, { fetchImpl: async url => {
    calls++;
    if (url.endsWith('/photos')) throw Error('unexpected route');
    if (url.includes('/media?')) return json({ photoUri: 'http://127.0.0.1/private' });
    return json({ id: 'place_a', photos: [{ name: 'places/place_a/photos/photo_1' }] });
  } });
  const { photos } = await (await app.get('/v1/places/place_a/photos')).json();
  assert.equal((await app.post('/v1/photo', { token: photos[0].token })).status, 502);
  assert.equal(calls, 2);
});

test('client minute limit cannot be bypassed by forged forwarding headers', async t => {
  let calls = 0;
  const app = await start(t, { perMinute: 1 }, { fetchImpl: async () => { calls++; return json({ id: 'place_a' }); } });
  assert.equal((await app.get('/v1/places/place_a', { 'x-forwarded-for': '1.1.1.1' })).status, 200);
  assert.equal((await app.get('/v1/places/place_a', { 'x-forwarded-for': '2.2.2.2' })).status, 429);
  assert.equal(calls, 1);
  assert.equal(clientIP({ socket: { remoteAddress: '127.0.0.1' }, headers: { 'x-forwarded-for': '1.1.1.1, 8.8.8.8' } }, { trustedProxies: ['127.0.0.1'] }), '8.8.8.8');
});

test('daily Google cap persists through restart and counters contain no raw IP', async t => {
  const directory = mkdtempSync(join(tmpdir(), 'eatset-usage-')); t.after(() => rmSync(directory, { recursive: true }));
  const path = join(directory, 'usage.sqlite'); const at = Date.UTC(2026,8,19);
  let store = new UsageStore(path, baseConfig.secret);
  assert.equal(store.allowGoogle(1, at), true);
  assert.equal(store.allowClient('192.0.2.123', baseConfig, at), true);
  store.close(); store = new UsageStore(path, baseConfig.secret);
  assert.equal(store.allowGoogle(1, at), false);
  assert.equal(store.allowGoogle(1, at + 86400000), true);
  assert(!JSON.stringify(store.db.prepare('SELECT * FROM counters').all()).includes('192.0.2.123'));
  store.close();
});

test('global cap includes upstream failures and rejects before the next billable request', async t => {
  let calls = 0;
  const app = await start(t, { dailyGoogle: 1 }, { fetchImpl: async () => { calls++; return new Response('', { status: 500 }); } });
  assert.equal((await app.get('/v1/places/place_a')).status, 502);
  assert.equal((await app.get('/v1/places/place_a')).status, 429);
  assert.equal(calls, 1);
  assert.equal(app.usage.db.prepare("SELECT count FROM usage WHERE outcome='attempt'").get().count, 1);
});

test('unapproved web origins are rejected; native requests have no origin', async t => {
  const app = await start(t, { origins: ['https://eatset.example'] }, { fetchImpl: async () => json({ id: 'place_a' }) });
  assert.equal((await app.get('/v1/places/place_a', { Origin: 'https://evil.example' })).status, 403);
  const allowed = await app.get('/v1/places/place_a', { Origin: 'https://eatset.example' });
  assert.equal(allowed.headers.get('access-control-allow-origin'), 'https://eatset.example');
  assert.equal((await app.get('/v1/places/place_a')).status, 200);
});

test('concurrency cap holds while upstream is pending', async t => {
  let release; let entered;
  const gate = new Promise(resolve => { release = resolve; });
  const started = new Promise(resolve => { entered = resolve; });
  const app = await start(t, { concurrent: 1 }, { fetchImpl: async () => { entered(); await gate; return json({ id: 'place_a' }); } });
  const first = app.get('/v1/places/place_a'); await started;
  assert.equal((await app.get('/v1/places/place_b')).status, 503);
  release(); assert.equal((await first).status, 200);
});

test('photo tokens outlive the five-minute place-data window, so browsing needs no second photo lookup', async t => {
  let time = Date.UTC(2026, 8, 19); let listCalls = 0;
  const app = await start(t, {}, { now: () => time, fetchImpl: async url => {
    if (url.includes('/media?')) return json({ photoUri: 'https://lh3.googleusercontent.com/image' });
    if (url.startsWith('https://places.googleapis.com/')) { listCalls++; return json({ places: [{ id: 'place_a', photos: [{ name: 'places/place_a/photos/photo_1' }] }] }); }
    return new Response(new Uint8Array([1]), { headers: { 'content-type': 'image/png' } });
  } });
  const { places } = await (await app.post('/v1/nearby', { lat: 25, lng: 121 })).json();
  assert(places[0].photosExpiresAt - time >= 25 * 60 * 1000);
  time += 20 * 60 * 1000;
  assert.equal((await app.post('/v1/photo', { token: places[0].photos[0].token })).status, 200);
  assert.equal(listCalls, 1);
});

test('photo size is chosen from a fixed list and never by the caller', async t => {
  const media = [];
  const app = await start(t, {}, { now: () => Date.UTC(2026, 8, 19), fetchImpl: async url => {
    if (url.includes('/media?')) { media.push(url.split('/media?')[1]); return json({ photoUri: 'https://lh3.googleusercontent.com/image' }); }
    if (url.startsWith('https://places.googleapis.com/')) return json({ places: [{ id: 'place_a', photos: [{ name: 'places/place_a/photos/photo_1' }] }] });
    return new Response(new Uint8Array([1]), { headers: { 'content-type': 'image/png' } });
  } });
  const { token } = (await (await app.post('/v1/nearby', { lat: 25, lng: 121 })).json()).places[0].photos[0];
  assert.equal((await app.post('/v1/photo', { token })).status, 200);
  assert.equal((await app.post('/v1/photo', { token, size: 'thumb' })).status, 200);
  assert.equal((await app.post('/v1/photo', { token, size: '9999' })).status, 400);
  assert.equal((await app.post('/v1/photo', { token, width: 4000 })).status, 400);
  assert.deepEqual(media, ['maxWidthPx=1000&maxHeightPx=750&skipHttpRedirect=true', 'maxWidthPx=400&maxHeightPx=300&skipHttpRedirect=true']);
});

test('photo quota is a separate pool: exhausting it never blocks nearby search', async t => {
  const app = await start(t, { dailyPhoto: 1 }, { now: () => Date.UTC(2026, 8, 19), fetchImpl: async url => {
    if (url.includes('/media?')) return json({ photoUri: 'https://lh3.googleusercontent.com/image' });
    if (url.startsWith('https://places.googleapis.com/')) return json({ places: [{ id: 'place_a', photos: [{ name: 'places/place_a/photos/photo_1' }] }] });
    return new Response(new Uint8Array([1]), { headers: { 'content-type': 'image/png' } });
  } });
  const { token } = (await (await app.post('/v1/nearby', { lat: 25, lng: 121 })).json()).places[0].photos[0];
  assert.equal((await app.post('/v1/photo', { token })).status, 200);
  const blocked = await app.post('/v1/photo', { token });
  assert.equal(blocked.status, 429);
  assert.equal((await blocked.json()).error.code, 'DAILY_LIMIT');
  assert.equal((await app.post('/v1/nearby', { lat: 25, lng: 121 })).status, 200);
});

test('large JSON is gzip-compressed only when the client accepts it', async t => {
  const places = Array.from({ length: 20 }, (_, i) => ({ id: `place_${i}`, displayName: { text: '店'.repeat(20) }, photos: [{ name: `places/place_${i}/photos/p` }] }));
  const app = await start(t, {}, { now: () => Date.UTC(2026, 8, 19), fetchImpl: async () => json({ places }) });
  const compressed = await app.post('/v1/nearby', { lat: 25, lng: 121 }, { 'accept-encoding': 'gzip' });
  assert.equal(compressed.headers.get('content-encoding'), 'gzip');
  assert.match(compressed.headers.get('vary'), /Accept-Encoding/);
  assert.equal((await compressed.json()).places.length, 20);
  const plain = await app.post('/v1/nearby', { lat: 25, lng: 121 }, { 'accept-encoding': 'identity' });
  assert.equal(plain.headers.get('content-encoding'), null);
  assert.equal((await plain.json()).places.length, 20);
});

test('display type label is requested in the field mask', async t => {
  let mask = '';
  const app = await start(t, {}, { fetchImpl: async (_url, init) => { mask = init.headers['X-Goog-FieldMask']; return json({ places: [{ id: 'a', primaryTypeDisplayName: { text: '拉麵店' } }] }); } });
  const body = await (await app.post('/v1/nearby', { lat: 25, lng: 121 })).json();
  assert(mask.split(',').includes('places.primaryTypeDisplayName'));
  assert.equal(body.places[0].primaryTypeDisplayName.text, '拉麵店');
});
