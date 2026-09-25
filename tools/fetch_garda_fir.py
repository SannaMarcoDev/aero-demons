"""Fetch CC0 Fir Tree 01 (Poly Haven), verify upstream hashes, prepare variant B.
Only authoring inputs go into ignored subagent-artifacts; Godot bakes the shipped LODs.
Run: python3 tools/fetch_garda_fir.py
"""
import concurrent.futures
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent / 'subagent-artifacts/garda-lookdev/sources'
FOLDER = ROOT / 'fir'


def fetch(url):
    with urlopen(Request(url, headers={'User-Agent': 'AeroDemons-Lookdev/1.0'}), timeout=120) as response:
        return response.read()


def main():
    FOLDER.mkdir(parents=True, exist_ok=True)
    data = json.loads(fetch('https://api.polyhaven.com/files/fir_tree_01'))
    (ROOT / 'fir_tree_01.json').write_text(json.dumps(data, indent=2))
    gltf = data['gltf']['1k']['gltf']
    alpha = data['twig_alpha']['1k']['png']
    files = {'fir_tree_01.gltf': gltf, **gltf['include'], 'textures/twig_alpha.png': alpha}

    def download(item):
        name, entry = item
        path = FOLDER / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and hashlib.md5(path.read_bytes()).hexdigest() == entry['md5']:
            return
        content = fetch(entry['url'])
        assert hashlib.md5(content).hexdigest() == entry['md5'], name
        path.write_bytes(content)

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(download, files.items()))
    # The upstream glTF points at a JPEG despite alphaMode=BLEND; restore the separate alpha.
    diffuse = Image.open(FOLDER / 'textures/fir_tree_01_twig_diff_1k.jpg').convert('RGBA')
    mask = Image.open(FOLDER / 'textures/twig_alpha.png').convert('L')
    assert mask.size == diffuse.size
    diffuse.putalpha(mask)
    diffuse.save(FOLDER / 'textures/twig_rgba.png')
    scene = json.loads((FOLDER / 'fir_tree_01.gltf').read_text())
    scene['meshes'] = [scene['meshes'][1]]
    scene['nodes'] = [scene['nodes'][1]]
    scene['nodes'][0]['mesh'] = 0
    scene['scenes'] = [{'nodes': [0]}]
    scene['scene'] = 0
    scene['images'][7]['uri'] = 'textures/twig_rgba.png'
    scene['images'][7]['mimeType'] = 'image/png'
    (FOLDER / 'fir_b.gltf').write_text(json.dumps(scene))
    print('PASS: VERIFIED FIR SOURCE')


if __name__ == '__main__':
    main()
