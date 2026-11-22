"""Deploy the relay as a public Hugging Face Space (free CPU) and set its secrets.

Usage (from the repo root):
    relay/.venv/Scripts/python relay/deploy.py <your-hf-username>/photo-town-relay

Needs in .env.local:
    HF_WRITE_TOKEN=hf_...   a token with Write access (creates the Space, uploads files)
    HF_TOKEN=hf_...         the Read token the Space uses to call AniGen (stored as a Space secret)
Optional:
    ANTHROPIC_API_KEY=...   lets the Space make Quick build places (Claude reads the photo);
                            stored as a Space secret, never sent to the game

Prints the Space URL to put in godot/scripts/relay_client.gd (DEPLOYED_URL).
"""

import os
import sys
from pathlib import Path

from huggingface_hub import HfApi

ROOT = Path(__file__).resolve().parent.parent
RELAY = ROOT / 'relay'
UPLOAD = ['app.py', 'README.md', 'requirements.txt']


def read_env(path):
    values = {}
    if path.is_file():
        for line in path.read_text(encoding='utf-8').splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                key, _, value = line.partition('=')
                values[key.strip()] = value.strip()
    return values


def main():
    if len(sys.argv) != 2 or '/' not in sys.argv[1]:
        sys.exit('Usage: python relay/deploy.py <hf-username>/<space-name>')
    repo_id = sys.argv[1]
    env = {**read_env(ROOT / '.env.local'), **os.environ}
    write_token = env.get('HF_WRITE_TOKEN', '')
    read_token = env.get('HF_TOKEN', '')
    if not write_token.startswith('hf_'):
        sys.exit('HF_WRITE_TOKEN (Write access) is missing from .env.local')
    if not read_token.startswith('hf_'):
        sys.exit('HF_TOKEN (Read access) is missing from .env.local')

    api = HfApi(token=write_token)
    api.create_repo(repo_id, repo_type='space', space_sdk='gradio', exist_ok=True)
    for name in UPLOAD:
        api.upload_file(path_or_fileobj=str(RELAY / name), path_in_repo=name, repo_id=repo_id, repo_type='space')
    api.add_space_secret(repo_id, 'HF_TOKEN', read_token)
    if env.get('ANTHROPIC_API_KEY'):
        api.add_space_secret(repo_id, 'ANTHROPIC_API_KEY', env['ANTHROPIC_API_KEY'])
    else:
        print('Note: ANTHROPIC_API_KEY is not in .env.local, so Quick build places will be off on the Space.')

    subdomain = repo_id.replace('/', '-').replace('_', '-').replace('.', '-').lower()
    print(f'Deployed: https://huggingface.co/spaces/{repo_id}')
    print(f'Relay URL (set DEPLOYED_URL to this): https://{subdomain}.hf.space')
    print('The Space takes a few minutes to build on first deploy.')


if __name__ == '__main__':
    main()
