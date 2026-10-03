#!/usr/bin/env node
// Check Git's tracked tree, since ignore rules do not protect files already tracked.
const { spawnSync } = require('node:child_process');

function forbidden(path) {
  const parts = path.replaceAll('\\', '/').toLowerCase().split('/');
  const name = parts.at(-1);
  const root = parts[0];

  if (parts.some((part) => ['.claude', '.agents', 'agents', 'agent-memory',
    'handoff', 'scratch'].includes(part))) return true;
  if (parts.some((part) => /^photos[^/]*$/.test(part))) return true;
  if (parts.some((part) => ['agents.md', 'claude.md', 'project.md'].includes(part))) return true;
  if (root === 'doc' && ['brief', 'reports', 'archive'].includes(parts[1])) return true;
  if (root === 'doc' && ['backlog.md', 'conventions.md', 'control-set.md'].includes(name)) return true;
  if (['.env', 'secrets.json'].includes(name)) return true;
  if (name.startsWith('.env.') && name !== '.env.example') return true;
  if (/\.(pem|key|p12|pfx|jks|keystore)$/.test(name)) return true;
  return false;
}

function check(paths) {
  return paths.filter(forbidden);
}

if (require.main === module) {
  const result = spawnSync('git', ['ls-files', '-z'], { encoding: 'utf8' });
  if (result.status !== 0) {
    process.stderr.write(`git ls-files failed: ${result.stderr}`);
    process.exit(2);
  }
  const violations = check(result.stdout.split('\0').filter(Boolean));
  if (violations.length) {
    process.stderr.write(`Forbidden tracked paths:\n${violations.join('\n')}\n`);
    process.exit(1);
  }
  process.stdout.write('Tracked public paths: OK\n');
}

module.exports = { forbidden, check };
