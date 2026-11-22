"""Photo Town relay: one photo in, one phone-friendly rigged GLB out.

Runs as a free CPU Hugging Face Space. It keeps HF_TOKEN secret (a Space secret)
and calls the public VAST-AI/AniGen Space, whose GPU time is billed to that token.
The game calls the `/generate` endpoint below.

Privacy: the photo is shrunk, stripped of metadata, sent to AniGen and deleted.
Nothing is stored here after the request finishes.
"""

import os
import re
import shutil
import tempfile
import time

import gradio as gr
from gradio_client import Client, handle_file
from PIL import Image, ImageOps

ANIGEN_SPACE = os.environ.get('ANIGEN_SPACE', 'VAST-AI/AniGen')
HF_TOKEN = os.environ.get('HF_TOKEN') or None
MAX_SIDE = 1024
# Local testing only: return this GLB instead of calling AniGen (never set on the Space).
FAKE_GLB = os.environ.get('RELAY_FAKE_GLB') or None
FAKE_DELAY_S = float(os.environ.get('RELAY_FAKE_DELAY', '8'))

# Settings that produced a ~2.4k-triangle, 512 px, 22-bone model in Phase 0.
GENERATE = dict(
    seed=42,
    ss_model_name='ss_flow_duet',
    slat_model_name='slat_flow_auto',
    ss_guidance_strength=7.5,
    ss_sampling_steps=25,
    slat_guidance_strength=3.0,
    slat_sampling_steps=25,
    joints_density=1,
)
EXTRACT = dict(texture_size=512, simplify_ratio=0.98, fill_holes=True)


def friendly_error(err):
    text = str(err)
    print(f'[relay] AniGen error: {type(err).__name__}: {text[:500]}', flush=True)
    low = text.lower()
    if 'quota' in low:
        wait = re.search(r'try again in ([0-9:]+)', text, re.IGNORECASE)
        later = f'in {wait.group(1)} (h:mm:ss)' if wait else 'later'
        return f'The GPU quota ran out. Please try again {later}.'
    if 'sleeping' in low or 'paused' in low or 'building' in low or '503' in low:
        return 'The 3D generator is starting up or unavailable. Try again in a minute.'
    if 'timeout' in low or 'timed out' in low:
        return 'The 3D generator took too long. Please try again.'
    return f'3D generation failed: {text[:200]}'


def shrink_photo(photo_path, out_dir):
    """Fix phone rotation, drop EXIF/GPS metadata, cap the size, save as JPEG."""
    out = os.path.join(out_dir, 'input.jpg')
    with Image.open(photo_path) as im:
        im = ImageOps.exif_transpose(im).convert('RGB')
        im.thumbnail((MAX_SIDE, MAX_SIDE))
        im.save(out, 'JPEG', quality=90)
    return out


def sweep_old_outputs(max_age_s=600):
    """Delete earlier results; Gradio keeps its own cached copy only until delete_cache runs."""
    tmp = tempfile.gettempdir()
    now = time.time()
    for name in os.listdir(tmp):
        path = os.path.join(tmp, name)
        if name.startswith('phototown_out_') and now - os.path.getmtime(path) > max_age_s:
            shutil.rmtree(path, ignore_errors=True)


def connect(download_dir, attempts=3):
    """AniGen's config endpoint is sometimes slow, so wait longer and retry."""
    for attempt in range(1, attempts + 1):
        try:
            return Client(
                ANIGEN_SPACE,
                token=HF_TOKEN,
                verbose=False,
                download_files=download_dir,
                httpx_kwargs={'timeout': 60},
            )
        except Exception:
            if attempt == attempts:
                raise
            time.sleep(3 * attempt)


def fake_result(small_photo):
    """Test mode (RELAY_FAKE_GLB set): skip AniGen and its GPU quota, return a known GLB."""
    if not os.path.isfile(FAKE_GLB):
        raise gr.Error(f'RELAY_FAKE_GLB file not found: {FAKE_GLB}')
    time.sleep(FAKE_DELAY_S)
    out_dir = tempfile.mkdtemp(prefix='phototown_out_')
    mesh_out = shutil.copy(FAKE_GLB, os.path.join(out_dir, 'resident.glb'))
    cutout_out = shutil.copy(small_photo, os.path.join(out_dir, 'cutout.jpg'))
    return mesh_out, cutout_out


def generate(photo_path):
    if not photo_path:
        raise gr.Error('No photo received.')
    sweep_old_outputs()
    work = tempfile.mkdtemp(prefix='phototown_')
    try:
        try:
            small = shrink_photo(photo_path, work)
        except Exception:
            raise gr.Error('That file is not a readable image.')
        if FAKE_GLB:
            return fake_result(small)
        try:
            # A new Client is a new AniGen session, so concurrent players never share state.
            client = connect(work)
            client.predict(api_name='/start_session')
            cutout = client.predict(image=handle_file(small), api_name='/prepare_input_for_generation')
            client.predict(**GENERATE, api_name='/generate_preview')
            mesh, _skeleton, status = client.predict(**EXTRACT, api_name='/extract_glb')
        except gr.Error:
            raise
        except Exception as err:
            raise gr.Error(friendly_error(err))
        if not mesh or not os.path.isfile(mesh):
            raise gr.Error(f'3D generation returned no model ({status}).')
        # Hand Gradio stable copies; it serves them from its own cache.
        out_dir = tempfile.mkdtemp(prefix='phototown_out_')
        mesh_out = shutil.copy(mesh, os.path.join(out_dir, 'resident.glb'))
        cutout_out = shutil.copy(cutout, os.path.join(out_dir, 'cutout.png'))
        return mesh_out, cutout_out
    finally:
        shutil.rmtree(work, ignore_errors=True)


with gr.Blocks(title='Photo Town relay', delete_cache=(600, 600)) as demo:
    gr.Markdown(
        '# Photo Town relay\n'
        'Turns a full-body photo into a low-poly rigged 3D model with '
        '[AniGen](https://huggingface.co/spaces/VAST-AI/AniGen). '
        'Only upload photos of people who agreed. Photos are not stored.'
    )
    with gr.Row():
        photo = gr.Image(type='filepath', label='Full-body photo', sources=['upload', 'webcam'])
        with gr.Column():
            glb = gr.File(label='Rigged model (.glb)')
            cutout = gr.Image(type='filepath', label='Cut-out')
    button = gr.Button('Generate', variant='primary')
    button.click(generate, inputs=photo, outputs=[glb, cutout], api_name='generate')

demo.queue(default_concurrency_limit=2)

if __name__ == '__main__':
    demo.launch()
