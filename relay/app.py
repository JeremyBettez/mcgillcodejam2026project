"""Photo Town relay: one photo in, one phone-friendly 3D result out.

Runs as a free CPU Hugging Face Space. It keeps HF_TOKEN and ANTHROPIC_API_KEY
secret (Space secrets). Endpoints the game calls:
- /generate               friend photo -> rigged GLB (VAST-AI/AniGen)
- /generate_place         place photo -> textured GLB (TRELLIS), "Detailed 3D"
- /generate_place_recipe  place photo + name -> JSON building recipe (Claude
                          reads the photo); the game builds a low-poly model
                          from it in code, "Quick build"

Privacy: the photo is shrunk, stripped of metadata, sent to the generator and
deleted. Nothing is stored here after the request finishes.
"""

import base64
import json
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

# Places (buildings, restaurants...): TRELLIS image-to-3D, a static textured GLB.
TRELLIS_SPACE = os.environ.get('TRELLIS_SPACE', 'trellis-community/TRELLIS')
PLACE_SETTINGS = dict(
    multiimages=[],
    seed=0,
    ss_guidance_strength=7.5,
    ss_sampling_steps=12,
    slat_guidance_strength=3.0,
    slat_sampling_steps=12,
    multiimage_algo='stochastic',
    mesh_simplify=0.97, # max the Space allows is 0.98; keeps places light for phones
    texture_size=512,
)
# Local testing only: return this GLB for places instead of calling TRELLIS.
FAKE_PLACE_GLB = os.environ.get('RELAY_FAKE_PLACE_GLB') or None

# Quick build: Claude looks at the photo and describes the building as a recipe
# of simple parts (see RECIPE_SCHEMA); the game assembles it (recipe_model.gd).
RECIPE_MODEL = os.environ.get('RECIPE_MODEL', 'claude-opus-5-5')
# Local testing only: return this JSON recipe instead of calling Claude.
FAKE_RECIPE = os.environ.get('RELAY_FAKE_RECIPE') or None

COLOR = {'type': 'string', 'description': 'Hex colour like #a8553a, taken from the photo.'}
RECIPE_SCHEMA = {
    'type': 'object',
    'properties': {
        'kind': {'type': 'string', 'enum': ['university', 'cafe', 'restaurant', 'shop', 'church', 'house',
                                            'office', 'museum', 'library', 'station', 'stadium', 'tower', 'park', 'other']},
        'width': {'type': 'number', 'description': 'Front width in metres, 4 to 10.'},
        'depth': {'type': 'number', 'description': 'Depth in metres, 3 to 8.'},
        'height': {'type': 'number', 'description': 'Height of the walls (not the roof) in metres, 2.5 to 8.'},
        'floors': {'type': 'integer', 'description': 'Number of floors with windows, 1 to 5.'},
        'wall_color': COLOR,
        'trim_color': COLOR,
        'roof_style': {'type': 'string', 'enum': ['flat', 'pitched', 'dome', 'mansard', 'spire']},
        'roof_color': COLOR,
        'wings': {'type': 'boolean', 'description': 'Lower side wings left and right of the main block.'},
        'columns': {'type': 'integer', 'description': 'Columns across the front entrance, 0 to 6.'},
        'column_color': COLOR,
        'windows_per_floor': {'type': 'integer', 'description': 'Windows across the front per floor, 0 to 8.'},
        'window_color': COLOR,
        'door_color': COLOR,
        'awning': {'type': 'boolean', 'description': 'A fabric awning over the ground floor.'},
        'awning_color': COLOR,
        'tower': {'type': 'string', 'enum': ['none', 'spire', 'dome', 'clock', 'flat']},
        'tower_color': COLOR,
        'sign_text': {'type': 'string', 'description': 'Short name for a sign on the front (max 20 characters), or "".'},
        'sign_color': COLOR,
        'sign_text_color': COLOR,
        'flag_colors': {'type': 'array', 'items': COLOR,
                        'description': 'Two brand or flag colours if the place has a recognizable flag or brand, else [].'},
        'trees': {'type': 'integer', 'description': 'Trees or bushes around it, 0 to 4.'},
    },
    'required': ['kind', 'width', 'depth', 'height', 'floors', 'wall_color', 'trim_color', 'roof_style', 'roof_color',
                 'wings', 'columns', 'column_color', 'windows_per_floor', 'window_color', 'door_color', 'awning',
                 'awning_color', 'tower', 'tower_color', 'sign_text', 'sign_color', 'sign_text_color', 'flag_colors', 'trees'],
    'additionalProperties': False,
}
RECIPE_SYSTEM = (
    'You design buildings for a cozy low-poly mobile town game. You get a photo of a real place, usually '
    'from the front, and its name. Describe it as a recipe of simple parts the game assembles from boxes, '
    'cylinders, domes and cones: a main block (optionally with lower side wings), floors of windows, a door, '
    'an optional portico of columns, an optional awning, a roof style, an optional tower, a front sign and '
    'some trees. Aim for something instantly recognizable as this place in a toy-like style, not an exact '
    'copy: pick the 2-3 most distinctive features and make them count. Sizes are stylised and must fit a '
    'game lot: width 4-10 m, depth 3-8 m, wall height 2.5-8 m. Take colours from the photo, a little '
    'brighter and warmer than real life; use #rrggbb. If the photo is not a building (a park, a statue, '
    'a mural...), still describe the closest simple structure. sign_text is the name painted on the place '
    'if one is visible, else a short form of the given name.'
)


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


def connect(download_dir, attempts=3, space=None):
    """Spaces' config endpoints are sometimes slow, so wait longer and retry."""
    for attempt in range(1, attempts + 1):
        try:
            return Client(
                space or ANIGEN_SPACE,
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


def generate_place(photo_path):
    """Photo of a building/place -> textured static GLB via TRELLIS."""
    if not photo_path:
        raise gr.Error('No photo received.')
    sweep_old_outputs()
    work = tempfile.mkdtemp(prefix='phototown_')
    try:
        try:
            small = shrink_photo(photo_path, work)
        except Exception:
            raise gr.Error('That file is not a readable image.')
        if FAKE_PLACE_GLB:
            if not os.path.isfile(FAKE_PLACE_GLB):
                raise gr.Error(f'RELAY_FAKE_PLACE_GLB file not found: {FAKE_PLACE_GLB}')
            time.sleep(FAKE_DELAY_S)
            out_dir = tempfile.mkdtemp(prefix='phototown_out_')
            return shutil.copy(FAKE_PLACE_GLB, os.path.join(out_dir, 'place.glb'))
        try:
            client = connect(work, space=TRELLIS_SPACE)
            client.predict(api_name='/start_session')
            cutout = client.predict(image=handle_file(small), api_name='/preprocess_image')
            _video, glb, _download = client.predict(image=handle_file(cutout), **PLACE_SETTINGS, api_name='/generate_and_extract_glb')
        except gr.Error:
            raise
        except Exception as err:
            raise gr.Error(friendly_error(err))
        if not glb or not os.path.isfile(glb):
            raise gr.Error('3D generation returned no model.')
        out_dir = tempfile.mkdtemp(prefix='phototown_out_')
        return shutil.copy(glb, os.path.join(out_dir, 'place.glb'))
    finally:
        shutil.rmtree(work, ignore_errors=True)


def recipe_error(err):
    import anthropic
    print(f'[relay] recipe error: {type(err).__name__}: {str(err)[:300]}', flush=True)
    if isinstance(err, anthropic.AuthenticationError):
        return 'The quick builder is not set up (missing or invalid API key).'
    if isinstance(err, anthropic.RateLimitError):
        return 'The quick builder is busy. Try again in a minute.'
    if isinstance(err, anthropic.APIConnectionError):
        return 'Could not reach the quick builder. Try again in a minute.'
    if isinstance(err, anthropic.APIStatusError) and err.status_code >= 500:
        return 'The quick builder is having trouble right now. Try again in a minute.'
    return 'The quick build failed. Try another photo or Detailed 3D.'


def ask_for_recipe(small_photo, name):
    """Send the shrunk photo and the name to Claude; return the recipe dict."""
    import anthropic
    with open(small_photo, 'rb') as f:
        image = base64.standard_b64encode(f.read()).decode('utf-8')
    client = anthropic.Anthropic(timeout=90.0)
    request = dict(
        model=RECIPE_MODEL,
        max_tokens=16000,
        system=RECIPE_SYSTEM,
        messages=[{
            'role': 'user',
            'content': [
                {'type': 'image', 'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': image}},
                {'type': 'text', 'text': f'The player calls this place: {name}'},
            ],
        }],
        output_config={'effort': 'medium', 'format': {'type': 'json_schema', 'schema': RECIPE_SCHEMA}},
    )
    try:
        # If a safety check declines on this model, the API retries on a fallback model.
        response = client.beta.messages.create(betas=['server-side-fallback-2026-07-01'], fallbacks='default', **request)
    except anthropic.BadRequestError:
        response = client.messages.create(**request) # fallbacks not accepted here: plain request
    if response.stop_reason == 'refusal':
        raise gr.Error('The quick builder could not use that photo. Try another one or Detailed 3D.')
    if response.stop_reason == 'max_tokens':
        raise gr.Error('The quick build came back incomplete. Please try again.')
    text = next((b.text for b in response.content if b.type == 'text'), '')
    return json.loads(text)


def generate_place_recipe(photo_path, name):
    """Photo of a place -> JSON recipe for a low-poly building the game builds in code."""
    if not photo_path:
        raise gr.Error('No photo received.')
    name = (name or '').strip()[:60] or 'This place'
    work = tempfile.mkdtemp(prefix='phototown_')
    try:
        try:
            small = shrink_photo(photo_path, work)
        except Exception:
            raise gr.Error('That file is not a readable image.')
        if FAKE_RECIPE:
            if not os.path.isfile(FAKE_RECIPE):
                raise gr.Error(f'RELAY_FAKE_RECIPE file not found: {FAKE_RECIPE}')
            time.sleep(min(FAKE_DELAY_S, 3.0))
            with open(FAKE_RECIPE, encoding='utf-8') as f:
                recipe = json.load(f)
            recipe['sign_text'] = recipe.get('sign_text') or name[:20]
            return json.dumps(recipe)
        if not os.environ.get('ANTHROPIC_API_KEY'):
            raise gr.Error('The quick builder is not set up (missing API key). Try Detailed 3D.')
        try:
            return json.dumps(ask_for_recipe(small, name))
        except gr.Error:
            raise
        except Exception as err:
            raise gr.Error(recipe_error(err))
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

    gr.Markdown('## Places\nPhoto of a building or place, from the front -> textured 3D model '
                '([TRELLIS](https://huggingface.co/spaces/trellis-community/TRELLIS)).')
    with gr.Row():
        place_photo = gr.Image(type='filepath', label='Place photo', sources=['upload', 'webcam'])
        place_glb = gr.File(label='Place model (.glb)')
    place_button = gr.Button('Generate place')
    place_button.click(generate_place, inputs=place_photo, outputs=place_glb, api_name='generate_place')

    gr.Markdown('## Quick build\nPhoto of a place + its name -> a building recipe (Claude reads the photo); '
                'the game builds a low-poly model from it.')
    with gr.Row():
        recipe_photo = gr.Image(type='filepath', label='Place photo', sources=['upload', 'webcam'])
        with gr.Column():
            recipe_name = gr.Textbox(label='Name')
            recipe_out = gr.Textbox(label='Recipe (JSON)', lines=8)
    recipe_button = gr.Button('Quick build')
    recipe_button.click(generate_place_recipe, inputs=[recipe_photo, recipe_name], outputs=recipe_out,
                        api_name='generate_place_recipe')

demo.queue(default_concurrency_limit=2)

if __name__ == '__main__':
    demo.launch()
