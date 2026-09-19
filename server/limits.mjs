import { DatabaseSync } from 'node:sqlite';
import { createHmac } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

// One SQLite volume shared by this single service. Counters are transactional
// and survive restarts. No coordinates, place IDs, photo URLs, or raw IPs stored.
export class UsageStore {
  constructor(path, secret) {
    if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
    this.secret = secret;
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS counters (bucket TEXT, subject TEXT, count INTEGER NOT NULL, expires INTEGER NOT NULL, PRIMARY KEY(bucket,subject));
      CREATE TABLE IF NOT EXISTS usage (day TEXT, kind TEXT, outcome TEXT, count INTEGER NOT NULL, PRIMARY KEY(day,kind,outcome));`);
  }
  reserve(rules) {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      for (const { bucket, subject, limit } of rules) {
        const row = this.db.prepare('SELECT count FROM counters WHERE bucket=? AND subject=?').get(bucket, subject);
        // Zero disables a development request cap, but still counts usage so
        // restoring a cap later does not discard requests made while disabled.
        if (limit !== 0 && (row?.count ?? 0) >= limit) { this.db.exec('ROLLBACK'); return false; }
      }
      for (const { bucket, subject, expires } of rules) {
        this.db.prepare('INSERT INTO counters VALUES (?,?,1,?) ON CONFLICT(bucket,subject) DO UPDATE SET count=count+1').run(bucket, subject, expires);
      }
      this.db.exec('COMMIT');
      return true;
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
  allowClient(ip, config, now) {
    const day = new Date(now).toISOString().slice(0, 10);
    const subject = createHmac('sha256', this.secret).update(`${day}:${ip}`).digest('hex');
    return this.reserve([
      { bucket: `minute:${Math.floor(now / 60000)}`, subject, limit: config.perMinute, expires: now + 120000 },
      { bucket: `client:${day}`, subject, limit: config.perDay, expires: now + 172800000 },
    ]);
  }
  allowGoogle(limit, now, pool = 'core') {
    // 'core' keeps the original bucket name so existing counters carry over.
    const day = new Date(now).toISOString().slice(0, 10);
    return this.reserve([{ bucket: pool === 'core' ? `google:${day}` : `google:${pool}:${day}`, subject: 'all', limit, expires: now + 172800000 }]);
  }
  record(kind, outcome, now) {
    this.db.prepare('INSERT INTO usage VALUES (?,?,?,1) ON CONFLICT(day,kind,outcome) DO UPDATE SET count=count+1')
      .run(new Date(now).toISOString().slice(0, 10), kind, outcome);
  }
  cleanup(now) {
    this.db.prepare('DELETE FROM counters WHERE expires < ?').run(now);
    this.db.prepare('DELETE FROM usage WHERE day < ?').run(new Date(now - 30 * 86400000).toISOString().slice(0, 10));
  }
  close() { this.db.close(); }
}
