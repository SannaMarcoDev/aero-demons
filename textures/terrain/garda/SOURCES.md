# Garda — marble cliff

Asset: [Marble Cliff 01](https://polyhaven.com/a/marble_cliff_01), Poly Haven.
Downloadable textures are **CC0 1.0 / public domain**: modification and commercial redistribution permitted; attribution appreciated, not required. [License](https://polyhaven.com/license), [CC0](https://creativecommons.org/publicdomain/zero/1.0/).

Marble Cliff was the original added rock asset; the current pass uses Aerial Rocks 02 below. Grass, rocky ground and snow remain the existing project assets. The surface shader's Terrain3D geometry code derives from the installed 1.0.2 minimum shader; its MIT license is in `addons/terrain_3d/LICENSE.txt`.

## Original 2048 × 2048 PNG sources

Base URL: `https://dl.polyhaven.org/file/ph-assets/Textures/png/2k/marble_cliff_01/`

| File | SHA-256 |
| --- | --- |
| `marble_cliff_01_diff_2k.png` | `5688cf9b84ca50408e89f331001be8e4c8798b631abba88b15e951453ca6974e` |
| `marble_cliff_01_disp_2k.png` | `0495ea6fee85d32a9d995de83551cc430335e718c7e7b22da248ae4ac26c56b8` |
| `marble_cliff_01_nor_gl_2k.png` | `a5d620ac4dfb154fc61146f2563876ee9908033609a31c468729ff3592ac39b8` |
| `marble_cliff_01_rough_2k.png` | `341b400bc2a6dca8dedda034eceffbc870de880b0343031ebb1cd3e404b0a7a5` |

## Packed project textures

No rescaling or upscaling. Diffuse RGB + displacement in alpha; OpenGL normal RGB + roughness in alpha. Alpha is data, not opacity. Import generates mipmaps; Terrain3D uploads the textures to arrays.

- `marble_cliff_01_albedo_packed.png` SHA-256: `2c725d083e3699ae0ce5c8f5c8cbf63be8ca9de15f16480c42c4f9ce7de6c251`
- `marble_cliff_01_normal_packed.png` SHA-256: `f60ae4ba206123834398dab6a5a0bc1f10ad0585e07cc446b738f84100510de2`

Repack with Pillow: convert the diffuse and normal images to `RGBA`, `putalpha()` the corresponding displacement/roughness converted to `L`, then save as PNG. Do not invert the OpenGL normal's green channel.

## Current mountain texture — Aerial Rocks 02

[Aerial Rocks 02](https://polyhaven.com/a/aerial_rocks_02), Poly Haven, **CC0** under the license linked above.
Uses the same 2K packing as Marble Cliff; no rescaling. Packed files:
`aerial_rocks_02_albedo_packed.png` and `aerial_rocks_02_normal_packed.png`.
Mipmaps enabled, lossless import, normal-map conversion and alpha-border processing
explicitly disabled because alpha carries height/roughness, not transparency.

Base URL: `https://dl.polyhaven.org/file/ph-assets/Textures/png/2k/aerial_rocks_02/`

| Original file | SHA-256 |
| --- | --- |
| `aerial_rocks_02_diff_2k.png` | `6d0319b0ebc97dae5e7ebeb02fe9252bdc78654b46b276907222a12935c07b18` |
| `aerial_rocks_02_disp_2k.png` | `3f080f5bec4b092ad4a7a6324c727010905c0f10b900a36bdeab4b2ef741147c` |
| `aerial_rocks_02_nor_gl_2k.png` | `53d4c2cac90801132a99054bd7d6132b230ddf9b12cc20c515caa7da0da6f01a` |
| `aerial_rocks_02_rough_2k.png` | `2f5f3f21d17a82378f29ea3501b5f5d5bc827493bc309e5f7ab1c0795880fdb2` |

Source downloads were also checked against the Poly Haven API's MD5 manifest.
The previous Marble Cliff files are retained for older scenes/comparisons.
