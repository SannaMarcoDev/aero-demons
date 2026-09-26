#!/usr/bin/env python3
"""Reimport AirbaseDemoMap placement from the original Unity package.

Run: uv run --with pyyaml tools/reimport_airbase_layout.py PACKAGE [--check]
Uses the existing converted meshes, restores source marking materials, and leaves
shared prefab scenes unchanged.
--check verifies the generated layout without writing it.
"""
import argparse
import copy
from pathlib import Path
import re
import tarfile

import yaml

BASE = Path(__file__).resolve().parents[1] / "assets/environment/military_airport"
SOURCE = "Assets/FreshCan3D/MilitaryAirport/"


def documents(text):
    parts = re.split(r"(?m)^--- !u!(\d+) &(-?\d+)(?: stripped)?\s*\n", text)[1:]
    return {int(uid): (int(kind), next(iter(yaml.safe_load(body).values())))
            for kind, uid, body in zip(*[iter(parts)] * 3)}


def transform(t, mesh=False):
    # Unity scene coordinates reflect Z. Blender's FBX conversion instead
    # reflects X relative to Unity mesh coordinates: adapt ONLY placed meshes
    # by a local Y half-turn. Do not rotate their positions or parent groups.
    p, q, s = (t[k] for k in ("m_LocalPosition", "m_LocalRotation", "m_LocalScale"))
    x, y, z, w = -q["x"], -q["y"], q["z"], q["w"]
    length = (x*x + y*y + z*z + w*w) ** 0.5
    x, y, z, w = (v / length for v in (x, y, z, w))
    sx, sy, sz = s["x"], s["y"], s["z"]
    if mesh:
        sx, sz = -sx, -sz
    # Text .tscn Transform3D stores basis rows, unlike the Vector3 constructor.
    values = [(1-2*(y*y+z*z))*sx, 2*(x*y-z*w)*sy, 2*(x*z+y*w)*sz,
              2*(x*y+z*w)*sx, (1-2*(x*x+z*z))*sy, 2*(y*z-x*w)*sz,
              2*(x*z-y*w)*sx, 2*(y*z+x*w)*sy, (1-2*(x*x+y*y))*sz,
              p["x"], p["y"], -p["z"]]
    return "transform = Transform3D(" + ", ".join(format(v, ".9g") for v in values) + ")"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    # Stream the archive; never extract package-controlled paths to disk.
    paths, assets = {}, {}
    with tarfile.open(args.package, "r|gz") as archive:
        for member in archive:
            guid, _, kind = member.name.partition("/")
            if kind == "pathname":
                paths[guid] = archive.extractfile(member).read().decode().strip()
            elif kind == "asset" and member.size < 15_000_000:
                data = archive.extractfile(member).read()
                if data.startswith(b"%YAML"):
                    assets[guid] = data.decode()
    scene_guid = next(g for g, p in paths.items() if p == SOURCE + "Scene/AirbaseDemoMap.unity")
    docs = documents(assets[scene_guid])
    prefabs = {g: documents(assets[g]) for g, p in paths.items()
               if p.startswith(SOURCE + "Art/Prefabs/") and p.endswith(".prefab")}
    expected, names, decals = {}, {}, {}
    for uid, (kind, obj) in docs.items():
        if kind == 4 and "m_GameObject" in obj:
            expected[uid] = transform(obj)
        elif kind == 1001:
            guid = obj["m_SourcePrefab"]["guid"]
            prefab = prefabs[guid]
            root_id, root = next((i, o) for i, (k, o) in prefab.items()
                                 if k == 4 and o["m_Father"]["fileID"] == 0)
            t = copy.deepcopy(root)
            for mod in obj["m_Modification"]["m_Modifications"]:
                prop = mod["propertyPath"]
                if not prop.startswith(("m_LocalPosition.", "m_LocalRotation.", "m_LocalScale.")):
                    continue
                field, axis = prop.split(".")
                if mod["target"]["fileID"] == root_id:
                    t[field][axis] = float(mod["value"])
                else:
                    # Child overrides must not overwrite root position (one
                    # road instance has an explicit LOD0 y=0 override).
                    child = prefab[mod["target"]["fileID"]][1]
                    assert float(mod["value"]) == child[field][axis], (uid, mod)
            expected[uid] = transform(t, mesh=True)
            names[uid] = Path(paths[guid]).stem
        elif kind == 114 and "m_Material" in obj:
            go = obj["m_GameObject"]
            tid = next(i for i, (k, o) in docs.items() if k == 4 and o.get("m_GameObject") == go)
            material = Path(paths[obj["m_Material"]["guid"]]).stem
            assert re.fullmatch(r"M_TurnDecal_[123]", material), material
            decals[tid] = (material[-1], obj["m_Size"])
    assert len(names) == 2338 and len(decals) == 24
    scene = BASE / "scenes/AirbaseDemoMap.tscn"
    original = scene.read_text()
    header, *blocks = re.split(r"(?=\[node )", original)
    # Existing native sky/materials are retained; HDRP volumes are not portable.
    for number in ("1", "2", "3"):
        line = (f'[ext_resource type="Texture2D" path="res://assets/environment/military_airport/'
                f'textures/Decals/T_TurnDecal_{number}_BC.png" id="decal_{number}"]\n')
        if line not in header:
            header = header.replace('[sub_resource type="ProceduralSkyMaterial"', line + '\n[sub_resource type="ProceduralSkyMaterial"', 1)
    found, output = set(), []
    for block in blocks:
        first = block.splitlines()[0]
        # Projector children are regenerated, making repeat imports idempotent.
        if first.startswith('[node name="Projector"'):
            continue
        match = re.search(r'name="([^"]*)_(\d+)"', first)
        if match and int(match[2]) in expected:
            uid = int(match[2])
            if uid in names:
                resource_id = re.search(r'instance=ExtResource\("([^"]+)"\)', first)[1]
                assert f'prefabs/{names[uid]}.tscn" id="{resource_id}"' in header, uid
            block = re.sub(r"(?m)^(transform|position|quaternion|scale) = .*\n", "", block)
            block = block.replace(first + "\n", first + "\n" + expected[uid] + "\n", 1)
            found.add(uid)
            if uid in decals:
                number, size = decals[uid]
                parent = re.search(r'parent="([^"]+)"', first)[1] + "/" + match[1] + "_" + match[2]
                block = block.rstrip() + (f'\n\n[node name="Projector" type="Decal" parent="{parent}"]\n'
                    'rotation_degrees = Vector3(90, 0, 0)\n'
                    f'size = Vector3({size["x"]}, {size["z"]}, {size["y"]})\n'
                    f'texture_albedo = ExtResource("decal_{number}")\n'
                    'upper_fade = 0.0\nlower_fade = 0.0\n\n')
        if any(f'parent="{p}"' in first for p in ("Ground",)) or first.startswith('[node name="Foliage"'):
            block = block.replace("visible = false\n", "")
        if first.startswith('[node name="Camera3D"'):
            block = re.sub(r"(?m)^far = .*\n", "", block)
            block = block.replace("current = true\n", "current = true\nfar = 4000.0\n")
        output.append(block)
    assert found == expected.keys(), ("Missing source transforms", expected.keys() - found)
    result = header + "".join(output)
    outputs = {scene: result}
    for name in ("Roads_1_Straight", "Roads_2_Corner", "Runway_Threshold", "Runway_Center", "Runway_AimPoint", "Runway_Stopway"):
        guid = next(g for g, p in paths.items() if p == SOURCE + f"Art/Materials/M_{name}.mat")
        material = next(o for k, o in documents(assets[guid]).values() if k == 21)
        saved = material["m_SavedProperties"]
        textures = {k: v for entry in saved["m_TexEnvs"] for k, v in entry.items()}
        colors = {k: v for entry in saved["m_Colors"] for k, v in entry.items()}
        channel = ", ".join(str(colors["_SignType"][k]) for k in "rgb")
        color = colors["_SignColor"]
        white = color["r"] == color["g"] == color["b"]
        paint = "white" if white else "yellow"
        lines = ['[gd_resource type="ShaderMaterial" load_steps=5 format=3]', '',
                 '[ext_resource type="Shader" path="res://assets/environment/military_airport/materials/runway_markings.gdshader" id="1"]']
        for number, prop in enumerate(("_BaseMap", "_RGB_Mask", "_NormalMap"), 2):
            texture = paths[textures[prop]["m_Texture"]["guid"]].removeprefix(SOURCE + "Art/Textures/")
            lines.append(f'[ext_resource type="Texture2D" path="res://assets/environment/military_airport/textures/{texture}" id="{number}"]')
        lines += ['', '[resource]', f'resource_name = "MI_{name}"', 'shader = ExtResource("1")',
                  'shader_parameter/asphalt = ExtResource("2")', 'shader_parameter/markings = ExtResource("3")',
                  'shader_parameter/asphalt_normal = ExtResource("4")',
                  f'shader_parameter/white_channels = Vector3({channel if white else "0, 0, 0"})',
                  f'shader_parameter/yellow_channels = Vector3({"0, 0, 0" if white else channel})',
                  f'shader_parameter/{paint}_paint = Color({color["r"]}, {color["g"]}, {color["b"]}, 1)']
        outputs[BASE / f"materials/MI_{name}.tres"] = "\n".join(lines) + "\n"
    for path, content in outputs.items():
        if args.check:
            assert content == path.read_text(), f"{path.name} differs from source; rerun without --check"
        else:
            path.write_text(content)
    print(f"PASS: AIRBASE_LAYOUT — {len(names)} prefab transforms, {len(decals)} decals, 6 marking materials; source targets verified")


if __name__ == "__main__":
    main()
