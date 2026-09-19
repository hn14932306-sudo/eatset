import { configFromEnv } from './config.mjs';
import { createApp } from './app.mjs';
const config = configFromEnv();
const { server, usage } = createApp(config);
server.listen(config.port, config.host, () => console.log(`EatSet API listening on ${config.host}:${config.port}; Google ${config.apiKey ? 'configured' : 'not configured'}`));
function stop() { server.close(() => { usage.close(); process.exit(0); }); }
process.once('SIGINT', stop);
process.once('SIGTERM', stop);
