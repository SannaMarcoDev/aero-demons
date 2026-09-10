# Benchmark freeroam — 2026-09-11

Setup: Godot 4.7.1, Forward+ / D3D12, **AMD Radeon RX 9070 XT**, finestra 1920×1080.
Metodo: `tools/freeroam_benchmark.gd` (SceneTree standalone), player teletrasportato
in 8 punti, chase camera reale, warmup 3,5 s + misura 6 s, 2 round rotati.
Metriche: frametime p50/p90/p99, **tempo GPU misurato** via
`viewport_get_measured_render_time_gpu`, tempo CPU di render, draw call, primitive, VRAM.

Nota: il VSync non si è disattivato (`vsync: 1` nel JSON) — le celle a 120,0 FPS sono
al cap del monitor (120 Hz); per i confronti vale `gpu_median_ms`, non il FPS cappato.
Dati grezzi: `user://freeroam_benchmark_2026-09-11T00-46-21.json` (143 celle).

## Punti misurati

| id | vista |
| --- | --- |
| spawn_orizzonte | spawn (0, 7114, 0), orizzonte sopra le nuvole |
| dentro_nuvole | x=-60 km, 3800 m, dentro lo strato volumetrico (2000–5500 m) |
| lago_sotto_nuvole | x=-60 km, 1200 m, lago sotto le nuvole, vista verso i monti |
| raso_acqua | x=-70 km, 650 m, radente sull'acqua |
| costa_monti | x=-10 km, 1000 m, transizione costa→montagne |
| cime_alte | x=+25 km, 7000 m, creste alte (~5900 m) |
| nadir_terreno | 1200 m, camera a picco sul terreno |
| volo_radente | tratta in movimento ~900 m/s sopra l'acqua |

## FPS medi (cap 120 Hz) — matrice punti × preset

| location | fxaa | no_aa | taa | fsr2_1.0 | fsr2_.67 | bil_.67 | bil_.50 | ssaa_1.25 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| spawn_orizzonte | 120 | 119 | 116 | 108 | 120 | 119 | 119 | 77 |
| dentro_nuvole | 91 | 94 | 103 | 76 | 120 | 119 | 120 | 62 |
| lago_sotto_nuvole | 83 | 81 | 80 | 79 | 119 | 120 | 119 | 62 |
| raso_acqua | 95 | 90 | 88 | 83 | 120 | 119 | 120 | 63 |
| costa_monti | 118 | 111 | 120 | 120 | 120 | 120 | 120 | 97 |
| cime_alte | 120 | 120 | 120 | 120 | 120 | 120 | 120 | 115 |
| nadir_terreno | 120 | 120 | 120 | 120 | 120 | 120 | 120 | 120 |
| volo_radente | 84 | 89 | 92 | 92 | 120 | 120 | 120 | 65 |

## Tempo GPU mediano (ms) — il dato affidabile

| location | fxaa | no_aa | taa | fsr2_1.0 | fsr2_.67 | bil_.67 | bil_.50 | ssaa_1.25 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| spawn_orizzonte | 6,8 | 6,9 | 7,4 | 7,8 | 4,9 | 4,4 | 4,1 | 10,5 |
| dentro_nuvole | 9,4 | 9,1 | 7,8 | 8,6 | 4,7 | 4,3 | 3,7 | 13,7 |
| lago_sotto_nuvole | 10,1 | 10,5 | 10,5 | 10,7 | 5,8 | 5,8 | 4,8 | 14,3 |
| raso_acqua | 9,4 | 9,6 | 9,9 | 10,3 | 6,0 | 5,7 | 4,2 | 14,0 |
| costa_monti | 6,7 | 7,3 | 6,2 | 6,3 | 4,8 | 4,5 | 4,2 | 8,9 |
| cime_alte | 5,2 | 5,4 | 5,3 | 5,2 | 5,5 | 5,1 | 3,6 | 7,5 |
| nadir_terreno | 2,4 | 2,4 | 2,6 | 3,0 | 1,8 | 1,4 | 1,0 | 3,2 |
| volo_radente | 9,9 | 9,7 | 9,5 | 9,6 | 5,4 | 5,3 | 4,3 | 13,2 |

FPS reali stimati senza cap (1000/gpu_ms, preset default): spawn ~147, dentro nuvole
~106, lago ~99, raso acqua ~106, costa ~150, cime ~193, nadir ~420, volo ~101.

## Fase B — costo dei sistemi (default_fxaa, GPU ms)

| location | base | nuvole off | ombre off | entrambe off | Δ nuvole |
| --- | --- | --- | --- | --- | --- |
| dentro_nuvole | 9,4 | 1,2 | 10,1 | 1,1 | **−87 %** |
| lago_sotto_nuvole | 10,1 | 1,2 | 11,1 | 1,1 | **−88 %** |
| costa_monti | 6,7 | 1,9 | 6,6 | 1,6 | **−72 %** |
| cime_alte | 5,2 | 1,4 | 4,7 | 1,3 | **−73 %** |

**SunshineClouds è il costo dominante**: 4–9 ms a 1080p a seconda di quanta nuvola
riempie lo schermo. Tutto il resto (terreno 250 km, cielo Sky3D, acqua, aereo, HUD)
costa **1,1–1,9 ms**. Ombre direzionali: ~0,3–1 ms, marginali.

## Fase C — scaling in risoluzione (lago_sotto_nuvole, default_fxaa)

| finestra | GPU ms | FPS |
| --- | --- | --- |
| 1280×720 | 6,1 | 120 (cap) |
| 1920×1080 | 10,1 | 83 |
| 2560×1440 | 16,9 | 50 |
| 3840×2160 | 32,9 | 26 |

Quasi lineare nei pixel (~4–5 ms/MPx) → il collo di bottiglia è fill-rate del
raymarching volumetrico, non geometria né draw call.

## Altri dati

- Draw call: 104–189 in tutte le viste; CPU render submit 0,25–0,5 ms → la CPU è
  lontanissima dal limite, scena 100 % GPU-bound.
- Primitive in frame: 460–730 k.
- VRAM: 4,0–5,5 GB.
- Varianza round-to-round: ±5–10 % sulle viste pesanti (attenzione a delta <1 ms).
- Streaming terreno durante volo_radente: nessun costo anomalo vs. viste statiche.

## Lettura e raccomandazioni

1. **Le nuvole volumetriche decidono il frame rate.** In `tutorial_clouds.tres`
   `resolution_scale = 0` (Native) con `max_step_count = 700`: il default dell'addon è
   Half (1) e 300 step. Portare la marcia a mezza risoluzione è il singolo
   intervento più efficace (atteso ~×3–4 sul pass nuvole); poi step 700→300 e
   `lighting_travel_distance` 3000→~2000 se serve altro margine.
2. **Preset AA**: FXAA (default progetto) è il più economico; TAA ≈ neutro
   (+0,3–0,6 ms); FSR2 nativo costa ~0,5 ms in più di no-AA senza guadagno perf.
   FSR2 0,67 e bilinear 0,67 si equivalgono in costo (~×1,8 più veloci del nativo)
   — FSR2 0,67 preferibile per qualità.
3. **SSAA 1,25** costa ~+40 % GPU: da escludere come default.
4. Ombre e terreno sono già economici: nessun intervento utile lì.
5. Per 1440p/4K il cloud pass scala coi pixel: senza `resolution_scale=1` (o FSR2)
   la scena resta sotto i 60 fps a 1440p su questa GPU.

Caveat: camera benchmark senza modello aereo in primo piano (impatto <0,1 ms,
trascurabile); VSync attivo durante il run; ±5–10 % varianza tra round.
