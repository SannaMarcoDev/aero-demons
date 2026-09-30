# Documentazione

La [guida del progetto](../README.md) descrive struttura, scene di ingresso e comandi.
Questa cartella è esclusa dall'import Godot; immagini e misure condivise restano in `images/`.

## Design

- [Piano demo giocabile](design/demo-playable-plan.md)
- [Prototipo dogfight e AI](design/dogfight-prototype-AI.md)
- [Story bible](design/story-bible-aero-demons.md)
- [Schede personaggi](design/schede-personaggi.md)
- [Regia del tutorial](design/regia-missione-1-tutorial.md)

## Funzionalità

- [Replay / Cinema](features/replays.md)
- [Scarico del jet](features/jet-exhaust.md)
- [Sfera energetica](features/energy-sphere.md)

## Ambiente e pipeline

- [Paesaggio Garda](environment/landscape-lookdev.md)
- [Acqua](environment/water-lookdev.md)
- [Superficie Garda](environment/garda-surface-review.md)
- [Boschi Garda — baseline storica](environment/garda-forest-review.md)
- [Scala Garda](environment/garda-scale-correction.md)
- [Editor strade](environment/roads-editor.md)
- [Anti-tiling del terreno](environment/terrain-antitile-review.md)
- [Import Utah / landcover](environment/utah-landcover-250km.md)

Sorgenti, licenze e istruzioni specifiche degli asset restano accanto agli asset,
in `assets/`, `terrain/` e `textures/`. I dati Terrain3D e `wc_data/` non sono cache.

## Resoconti di sviluppo

- [Baseline controller](development/issue-2-controller-baseline.md)
- [Binding controller](development/issue-3-controller-bindings.md)
- [Build interna](development/issue-5-internal-build.md)
- [Flusso UI con controller](development/issue-6-controller-flow.md)
- [Volo protetto](development/issue-7-protected-flight.md)

I report conservano risultati e limiti delle rispettive revisioni. I percorsi sono
aggiornati alla struttura corrente, ma le vecchie misure non certificano le
prestazioni o il superamento dei controlli sul checkout attuale.
