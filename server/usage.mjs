import { DatabaseSync } from 'node:sqlite';
const path = process.env.DB_PATH ?? './data/usage.sqlite';
const db = new DatabaseSync(path, { readOnly: true });
console.table(db.prepare('SELECT day,kind,outcome,count FROM usage ORDER BY day DESC,kind,outcome').all());
db.close();
