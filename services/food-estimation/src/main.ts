import { readConfig } from './config.js';
import { createService } from './server.js';

process.umask(0o077);
try {
  const service = createService(readConfig());
  await service.listen();
  process.stdout.write(JSON.stringify({ event: 'service_listening' }) + '\n');
  let closing = false;
  const close = async () => { if (closing) return; closing = true; await service.close(); process.exit(0); };
  process.on('SIGTERM', () => { void close(); }); process.on('SIGINT', () => { void close(); });
} catch {
  // Environment values and upstream errors can contain credentials. Never print them.
  process.stderr.write('Service startup failed. Check configuration, directory access and port availability.\n');
  process.exitCode = 1;
}
