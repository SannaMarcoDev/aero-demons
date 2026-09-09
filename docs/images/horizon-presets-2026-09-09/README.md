# Confronto preset orizzonte — 9 settembre 2026

**Scelta applicata dopo il confronto: C standard, D come opzione grafica.**

In freeroam e tutorial, **F7** alterna C/D e salva `graphics/horizon_blur` in `user://graphics.cfg`. Alla prima esecuzione, senza preferenze salvate, parte C. D aggiunge solo il DOF lontano sulla camera di volo, conservando l'esposizione; F6 resta indipendente. Nessuna modifica a terreno, esportazioni World Creator o shader.

Verificati `tests/horizon_graphics_check.gd` (headless e render D3D12, cambio anche in pausa, persistenza e ripristino C), `tests/boundary_return_check.gd` e `tests/sunshine_atmosphere_check.cjs`. Il costo GPU aggiuntivo di D non è ancora stato misurato.

I collage e i manifest sottostanti sono **catture storiche precedenti all'applicazione**: A mostra la vecchia baseline. Il loro footer «produzione invariata» descrive quel run, non lo stato attuale del progetto.

- [Collage a 12 km](collage-12000.png)
- [Collage a 19,5 km](collage-19500.png) — quota diagnostica, non modifica del limite di volo.
- [Dettaglio 1:1 a 19,5 km](collage-dettaglio.png)

## Varianti

| Preset | Densità Sunshine | `use_environment_fog` | Colore atmosfera / sampled fog | DOF lontano |
|---|---:|---:|---|---|
| A — attuale | 1,25 | 0,35 | (0,518; 0,553; 0,608) | spento |
| B — foschia morbida | 1,60 | 0,55 | (0,55; 0,64; 0,75) | spento |
| C — sfumatura più marcata | 2,00 | 0,65 | come B | spento |
| D — C + blur lontano | 2,00 | 0,65 | come B | amount 0,08; inizio 35 km; transizione 45 km |

A ripristina i valori effettivi letti all'avvio, non i valori nominali della tabella. D differisce da C soltanto per il DOF nativo di Godot. Sono prove dei controlli esistenti: non è stata introdotta una nuova rampa atmosferica né eliminato selettivamente il contributo sul cielo. Il cielo più chiaro di B/C è parte della differenza da valutare.

## Metodo e verifica

Scena `scenes/levels/freeroam.tscn`, mappa `garda_final`, Godot 4.7.1 Forward+ / D3D12, 1920×1080, FOV 70°, far plane 100 km. Camera di inseguimento esistente congelata su pose diagnostiche. Le due quote hanno inclinazioni diverse; confrontare A/B/C/D **entro la stessa quota**.

Luce, forma e fase delle nuvole, camera, antialiasing ed esposizione mantenuti invariati fra varianti. Nessuna nebbia Sky3D, nessun anello di effectors. HUD/F6 nascosti in tutte le catture. 96 frame di assestamento prima di ogni screenshot. Collage ridimensionati uniformemente senza ritocco colore; il dettaglio è un ritaglio identico a scala 1:1. Originali PNG 1920×1080 inclusi.

- PASS: check headless di ripristino A dopo ciascun candidato e camere finite/in-frustum.
- PASS: dieci catture grafiche A/B/C/D/A_repeat, manifest completo, nessun errore di script/rendering nei log.
- PASS: confronto automatico delle pose e della ripetizione A. Differenza RGB media assoluta normalizzata nella fascia superiore (55% dell'immagine): **0,00000424** a 12 km, **0,000000987** a 19,5 km. Campionamento ogni quattro pixel; non è una misura di qualità visiva.
- La differenza sull'intero frame è circa 0,00024: restano animazioni materiali/effetti del velivolo, quindi non si dichiara identità pixel assoluta.
- Restano warning già noti di deprecazione dell'interpolazione e RID Sunshine al termine del processo.

Il confronto non certifica ancora prestazioni, comportamento in movimento, coerenza del DOF sulle nuvole o occultamento completo del limite di rendering. La discontinuità distante nella zona sinistra della vista alta resta visibile: questa prova serve a scegliere la resa, non a dichiarare risolto ogni bordo.

## Riproduzione

Dalla radice del progetto. Il tool legge A dalla configurazione corrente: dopo l'applicazione di C, A non ricrea più la vecchia baseline dei PNG storici.

```powershell
$godot = 'C:\Users\sanna\Workspace\Godot\Godot_v4.7.1-stable_win64_console.exe'
& $godot --headless --path . --script tools/horizon_preset_capture.gd --quit-after 600 -- --check
& $godot --path . --script tools/horizon_preset_capture.gd --fixed-fps 30 --quit-after 1800
# Il run stampa la nuova directory sotto user://horizon_presets/.
# Usare una Destination nuova: il generatore rifiuta di sovrascrivere collage esistenti.
powershell -NoProfile -File tools/build_horizon_collage.ps1 -Source '<directory del run>' -Destination '<nuova directory>'
```

Origine delle catture: `user://horizon_presets/2026-09-09T21-37-40-12140/`. Parametri effettivi e pose in `manifest.json`; metriche in `repeatability.json`.
