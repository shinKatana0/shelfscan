const { test } = require('node:test');
const assert = require('node:assert/strict');
const { forbidden, check, failureSummary } = require('./check-public-paths.cjs');

test('rejects private workspace paths with case variants', () => {
  for (const path of [
    'AGENTS.md', 'nested/CLAUDE.md', '.claude/delivery/file',
    '.agents/state', 'agents/WORKER.md', 'doc/brief/brief.md',
    'doc/reports/report.md', 'doc/archive/old.md', 'doc/backlog.md',
    'doc/conventions.md', 'doc/control-set.md', 'PROJECT.md',
    'photos2/example.jpg', 'nested/PhotosArchive/example.jpg',
    '.env', '.ENV.local', 'nested/secrets.json', 'signing.P12',
    'private.KEY',
  ]) assert.equal(forbidden(path), true, path);
});

test('allows public assets, examples, and product agent code', () => {
  for (const path of [
    '.env.example', 'app/assets/icon.png', 'app/lib/agent_router.dart',
    'doc/decisions/0001-platform.md', 'ARCHITECTURE.md',
    'app/android/key.properties.example',
  ]) assert.equal(forbidden(path), false, path);
  assert.deepEqual(check(['README.md', '.env.production']), ['.env.production']);
});

test('failure output never repeats private filenames', () => {
  const paths = ['doc/reports/private-title.md', '.env.private-key'];
  const summary = failureSummary(paths);
  assert.equal(summary, 'Forbidden tracked paths: 2 (credential file, private project record)\n');
  for (const path of paths) assert.equal(summary.includes(path), false);
});
