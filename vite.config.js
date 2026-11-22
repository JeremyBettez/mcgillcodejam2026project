// Serves the Godot web export (godot/build/web).
// `npm run serve`      -> http://localhost:5173 (camera works on localhost)
// `npm run serve:lan`  -> https://<your-ip>:5173 for phones on the same Wi-Fi
//                         (self-signed certificate: accept the browser warning once)
import { defineConfig } from 'vite';
import basicSsl from '@vitejs/plugin-basic-ssl';

export default defineConfig(({ mode }) => ({
  root: 'godot/build/web',
  appType: 'mpa',
  plugins: mode === 'lan' ? [basicSsl()] : [],
  server: {
    host: mode === 'lan',
    port: 5173,
    strictPort: true,
  },
}));
