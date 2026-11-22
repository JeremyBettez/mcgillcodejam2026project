// Runs the Photo Town relay (relay/app.py) on this computer at http://127.0.0.1:7860,
// with the keys from .env.local, so the game in the editor or a desktop browser can
// make friends and places.
//
// Usage:
//   npm run relay        real generators (HF_TOKEN for friends/Detailed 3D,
//                        ANTHROPIC_API_KEY for Quick build places)
//   npm run relay:test   no GPU quota or API key needed: friends get the demo model
//                        (renders/demo/mesh.glb) and Quick build gets relay/sample_recipe.json
//
// Keys are passed to the relay process only; they are never printed.

import { spawn } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const test = process.argv.includes('--test');

function readEnv(path) {
  const values = {};
  if (!existsSync(path)) return values;
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const at = line.indexOf('=');
    if (at < 1 || line.trimStart().startsWith('#')) continue;
    const name = line.slice(0, at).trim();
    const value = line.slice(at + 1).trim().replace(/^(['"])(.*)\1$/, '$2');
    if (name && value) values[name] = value;
  }
  return values;
}

const env = { ...readEnv(join(root, '.env.local')), ...process.env };
if (test) {
  const demo = join(root, 'renders', 'demo', 'mesh.glb');
  if (existsSync(demo)) env.RELAY_FAKE_GLB = demo;
  env.RELAY_FAKE_RECIPE = join(root, 'relay', 'sample_recipe.json');
  env.RELAY_FAKE_DELAY = env.RELAY_FAKE_DELAY || '4';
}
env.GRADIO_ANALYTICS_ENABLED = 'False';

const python = process.platform === 'win32'
  ? join(root, 'relay', '.venv', 'Scripts', 'python.exe')
  : join(root, 'relay', '.venv', 'bin', 'python');
if (!existsSync(python)) {
  console.error('relay/.venv is missing. Create it (see CLAUDE.md, "Relay"), then run this again.');
  process.exit(1);
}

const on = (yes) => (yes ? 'on' : 'off');
console.log(`Photo Town relay${test ? ' (TEST MODE)' : ''} -> http://127.0.0.1:7860`);
console.log(`  Friends (AniGen):          ${test && env.RELAY_FAKE_GLB ? 'demo model' : on(env.HF_TOKEN)}`);
console.log(`  Places, Detailed 3D:       ${on(env.HF_TOKEN)}`);
console.log(`  Places, Quick build:       ${test ? 'sample recipe' : on(env.ANTHROPIC_API_KEY)}`);
if (!test && !env.ANTHROPIC_API_KEY) console.log('  (add ANTHROPIC_API_KEY to .env.local for Quick build)');
console.log('Press Ctrl+C to stop.\n');

const child = spawn(python, [join(root, 'relay', 'app.py')], { cwd: root, env, stdio: 'inherit' });
child.on('exit', (code) => process.exit(code ?? 0));
process.on('SIGINT', () => child.kill('SIGINT'));
