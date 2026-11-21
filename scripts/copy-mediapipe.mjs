// Copies MediaPipe's WASM runtime into public/ so face detection works without a CDN.
import { cpSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const src = join(root, 'node_modules', '@mediapipe', 'tasks-vision', 'wasm');
const dest = join(root, 'public', 'mediapipe');
if (!existsSync(src)) {
  console.warn('[copy-mediapipe] @mediapipe/tasks-vision not installed yet, skipping');
} else {
  mkdirSync(dest, { recursive: true });
  cpSync(src, dest, { recursive: true });
  console.log('[copy-mediapipe] copied WASM runtime to public/mediapipe');
}
