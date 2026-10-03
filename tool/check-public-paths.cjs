#!/usr/bin/env node
// Check Git's tracked tree, since ignore rules do not protect files already tracked.
const { spawnSync } = require('node:child_process');

function category(path) {
  const parts = path.replaceAll('\\', '/').toLowerCase().split('/');
  const name = parts.at(-1);
  const root = parts[0];

  if (parts.some((part) => ['.claude', '.agents', 'agents', 'agent-memory',
    'handoff', 'scratch'].includes(part))) return 'private workspace state';
  if (parts.some((part) => /^photos[^/]*$/.test(part))) return 'local photo input';
  if (parts.some((part) => ['agents.md', 'claude.md', 'project.md'].includes(part))) return 'private workspace state';
  if (root === 'doc' && ['brief', 'reports', 'archive'].includes(parts[1])) return 'private project record';
  if (root === 'doc' && ['backlog.md', 'conventions.md', 'control-set.md'].includes(name)) return 'private project record';
  if (['.env', 'secrets.json'].includes(name)) return 'credential file';
  if (name.startsWith('.env.') && name !== '.env.example') return 'credential file';
  if (/\.(pem|key|p12|pfx|jks|keystore)$/.test(name)) return 'credential file';
  return null;
}

function forbidden(path) {
  return category(path) !== null;
}

function check(paths) {
  return paths.filter(forbidden);
}

function failureSummary(violations) {
  const categories = [...new Set(violations.map(category))].sort();
  return `Forbidden tracked paths: ${violations.length} (${categories.join(', ')})\n`;
}

if (require.main === module) {
  const result = spawnSync('git', ['ls-files', '-z'], { encoding: 'utf8' });
  if (result.status !== 0) {
    process.stderr.write('Could not inspect tracked paths with git ls-files.\n');
    process.exit(2);
  }
  const violations = check(result.stdout.split('\0').filter(Boolean));
  if (violations.length) {
    process.stderr.write(failureSummary(violations));
    process.exit(1);
  }
  process.stdout.write('Tracked public paths: OK\n');
}

module.exports = { forbidden, check, failureSummary };
