// Photo Town browser glue. Loaded by the web export's <head> (see export_presets.cfg)
// and copied next to index.html by `npm run export:web`.
// Godot talks to it through JavaScriptBridge.get_interface('photoTown').
//
// Privacy: the photo never leaves this page here. It is decoded, rotated upright,
// shrunk to MAX_SIDE, re-encoded as JPEG (which drops EXIF/GPS metadata) and handed
// to Godot in memory. Nothing is stored.
(function () {
  'use strict';

  const MAX_SIDE = 1024;
  const JPEG_QUALITY = 0.9;

  function reply(callback, payload) {
    try {
      callback(JSON.stringify(payload));
    } catch (err) {
      console.error('[photoTown] Godot callback failed', err);
    }
  }

  // Decode with the phone's rotation applied (EXIF orientation).
  async function decode(file) {
    if ('createImageBitmap' in window) {
      try {
        return await createImageBitmap(file, { imageOrientation: 'from-image' });
      } catch (err) {
        // Older browsers reject the options object; fall back to <img>.
      }
    }
    const url = URL.createObjectURL(file);
    try {
      const img = new Image();
      img.src = url;
      await img.decode(); // <img> applies EXIF orientation by default
      return img;
    } finally {
      URL.revokeObjectURL(url);
    }
  }

  function toJpeg(source) {
    const w = source.naturalWidth || source.width;
    const h = source.naturalHeight || source.height;
    if (!w || !h) return Promise.reject(new Error('empty image'));
    const scale = Math.min(1, MAX_SIDE / Math.max(w, h));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(w * scale));
    canvas.height = Math.max(1, Math.round(h * scale));
    canvas.getContext('2d').drawImage(source, 0, 0, canvas.width, canvas.height);
    return new Promise((resolve, reject) => {
      canvas.toBlob((blob) => {
        if (!blob) return reject(new Error('JPEG encoding failed'));
        const reader = new FileReader();
        reader.onload = () => resolve({
          base64: String(reader.result).split(',')[1],
          width: canvas.width,
          height: canvas.height,
        });
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(blob);
      }, 'image/jpeg', JPEG_QUALITY);
    });
  }

  async function processFile(file) {
    const image = await decode(file);
    try {
      return await toJpeg(image);
    } finally {
      if (image.close) image.close();
    }
  }

  // source: 'camera' opens the camera app directly; 'library' opens the photo picker.
  // callback receives a JSON string:
  //   {ok: true, base64, width, height} | {ok: false, cancelled: true} | {ok: false, error}
  function pickPhoto(source, callback) {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    if (source === 'camera') input.setAttribute('capture', 'environment');
    input.style.display = 'none';
    document.body.appendChild(input);

    let done = false;
    const finish = (payload) => {
      if (done) return;
      done = true;
      input.remove();
      reply(callback, payload);
    };

    input.addEventListener('cancel', () => finish({ ok: false, cancelled: true }));
    input.addEventListener('change', async () => {
      const file = input.files && input.files[0];
      if (!file) return finish({ ok: false, cancelled: true });
      try {
        finish({ ok: true, ...(await processFile(file)) });
      } catch (err) {
        console.warn('[photoTown] could not read photo', err);
        finish({ ok: false, error: 'Could not read that photo. Try a JPEG or PNG.' });
      }
    });

    try {
      input.click();
    } catch (err) {
      finish({ ok: false, error: 'Could not open the camera or photo picker.' });
    }
  }

  // Phone-friendly text entry (Godot's own on-screen keyboard is experimental on web).
  // Returns the trimmed name, or null if the player cancelled.
  function askName(current) {
    const value = window.prompt('Their name', current || '');
    return value === null ? null : value.trim().slice(0, 40);
  }

  window.photoTown = {
    version: 2,
    ready: true,
    pickPhoto,
    askName,
  };
})();
