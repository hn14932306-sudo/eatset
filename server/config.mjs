import { isAbsolute } from 'node:path';
import { isIP } from 'node:net';
export function configFromEnv(env = process.env) {
  const production = env.NODE_ENV === 'production';
  const number = (key, fallback, max, minimum = 1) => {
    const value = Number(env[key] ?? fallback);
    if (!Number.isSafeInteger(value) || value < minimum || value > max) throw new Error(`Invalid ${key}`);
    return value;
  };
  const config = {
    production, host: env.HOST ?? '127.0.0.1', port: number('PORT', 8787, 65535),
    apiKey: env.GOOGLE_PLACES_API_KEY ?? '',
    secret: env.SERVER_SECRET ?? '', dbPath: env.DB_PATH ?? './data/usage.sqlite',
    perMinute: number('CLIENT_REQUESTS_PER_MINUTE', 30, 1000, production ? 1 : 0),
    perDay: number('CLIENT_REQUESTS_PER_DAY', 150, 10000, production ? 1 : 0),
    dailyGoogle: number('GOOGLE_REQUESTS_PER_DAY', 500, 100000, production ? 1 : 0),
    dailyPhoto: number('GOOGLE_PHOTO_REQUESTS_PER_DAY', 1000, 100000, production ? 1 : 0),
    concurrent: number('MAX_CONCURRENT_REQUESTS', 4, 32),
    origins: (env.ALLOWED_ORIGINS ?? '').split(',').filter(Boolean),
    trustedProxies: (env.TRUSTED_PROXY_IPS ?? '').split(',').filter(Boolean),
  };
  if (config.trustedProxies.some(ip => !isIP(ip))) throw new Error('Invalid TRUSTED_PROXY_IPS');
  if (production && (!config.apiKey || config.secret.length < 32 || !isAbsolute(config.dbPath))) {
    throw new Error('Production requires GOOGLE_PLACES_API_KEY, SERVER_SECRET (32+ characters), and an absolute persistent DB_PATH');
  }
  return config;
}
