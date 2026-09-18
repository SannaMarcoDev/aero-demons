# Performance — 1080p Ultra

**Guadagno misurato: 25–28%. Target 200 FPS non raggiunto.** Nessuna riduzione
ai preset, alla risoluzione interna, ai dettagli, alle ombre o ai budget delle
nuvole. Le modifiche sono in `SunshineClouds.gd` e `SunshineCloudsCompute.glsl`.

## Ambiente e metodo

- Ryzen 5 7500F, Radeon RX 9070 XT, circa 32 GB RAM, Windows.
- Godot 4.7.1 stable, Forward+/D3D12, finestra **1920×1080**.
- Preset Ultra del gioco, FSR2 a scala **1,0**, copertura nuvole **0,834**,
  nuvole a piena risoluzione, **700** passi principali e **32** di illuminazione.
- V-Sync disattivato e FPS illimitati **solo nel processo del benchmark**.
  Nessuna scrittura a `user://settings.cfg`.
- `tools/performance_benchmark.gd` riusa camere e misurazione di
  `tools/freeroam_benchmark.gd`: cinque viste statiche e un percorso pilotato,
  tre ripetizioni, 3,5 s di assestamento e 6 s di misura per vista.
  Attende la costruzione delle foreste e un riscaldamento iniziale di 8 s.
- Meteo e fisica del player/boundary congelati per confrontare lo stesso lavoro
  grafico. **Non è un benchmark di una battaglia completa né un minimo FPS
  garantito nel gameplay.** Avvio/caricamento esclusi dalle misure.
- FPS in tabella: mediana delle tre medie di ciascuna vista. Tempi GPU e p99:
  mediana dei rispettivi valori delle tre ripetizioni. CPU render circa
  0,26–0,52 ms dopo la modifica: non è il tempo totale di simulazione CPU.

## Prima / dopo

| Vista | FPS prima | FPS dopo | Guadagno | GPU prima → dopo | Frame p99 prima → dopo |
|---|---:|---:|---:|---:|---:|
| Quota di partenza | 115,9 | 144,6 | +24,8% | 8,30 → 6,62 ms | 9,34 → 7,81 ms |
| Dentro le nuvole | 106,8 | 136,5 | +27,8% | 9,03 → 6,99 ms | 10,26 → 7,61 ms |
| Lago | 97,8 | 125,1 | +27,9% | 9,87 → 7,69 ms | 10,90 → 8,37 ms |
| Alpi | 75,5 | 94,5 | +25,2% | 12,85 → 10,23 ms | 13,52 → 10,88 ms |
| Aeroporto | 89,5 | 114,3 | +27,7% | 10,81 → 8,39 ms | 11,75 → 9,58 ms |
| Percorso in volo | 87,7 | 111,9 | +27,6% | 11,08 → 8,67 ms | 12,87 → 9,98 ms |

Configurazioni JSON prima/dopo confrontate: identiche. Risultati e screenshot
locali: `.pi/performance/baseline/`, `.pi/performance/after/`,
`.pi/performance/summary.json`, `.pi/performance/comparison.png`.
Gli artefatti `.pi/` sono ignorati da Git.

## Cause identificate

1. **Raymarch delle nuvole, GPU-bound.** Nella diagnosi alla quota di partenza,
   Ultra dava 117,1 FPS / 8,07 ms GPU; disattivando solo il compositor nuvole
   si ottenevano 422,1 FPS / 2,11 ms. Senza terreno: 136,7 FPS / 6,92 ms;
   senza ombre solari: 118,1 FPS; senza HUD: 116,7 FPS. Sono prove per isolare
   il costo, **non impostazioni adottate per ottenere il miglioramento**.
   Timestamp GPU temporanei collocavano il solo pass raymarch a circa
   5,4 ms nello spawn e 10,3 ms nelle Alpi, prima dell'ottimizzazione.
2. **Lavoro inutile nel campionamento della densità.** Anche nelle zone vuote
   venivano letti i dettagli 3D e valutati i relativi rimappamenti. Ora si
   termina quando il profilo verticale o la forma principale garantiscono
   densità zero. Le coordinate originali del dettaglio e gli effectors positivi
   sono conservati. La fase luminosa direzionale costante lungo un raggio
   viene calcolata una volta; la maschera macro non viene letta fuori dallo
   strato di nuvole. Evitato anche lo 0/0 nella history dei raggi vuoti.
3. **Ricostruzioni GPU quando non cambia la qualità.** Il setter della
   risoluzione invalidava i buffer anche ricevendo lo stesso valore. Questo
   avveniva riapplicando le impostazioni, anche per audio/controlli. Ora non
   invalida nulla se il valore è invariato; la regressione verifica che il RID
   della pipeline rimanga lo stesso. Non è conteggiato come guadagno FPS
   continuativo: evita lavoro e reset della history durante le impostazioni.
4. **Limiti nelle preferenze iniziali.** Il profilo salvato era 2560×1440,
   V-Sync attivo e cap a 120 FPS: non poteva mostrare 200 FPS. Le preferenze
   salvate sono state lasciate intatte. Il confronto qui è realmente a 1080p,
   senza quei limiti in entrambe le versioni.

Vulkan provato nelle stesse sei viste: nessun miglioramento complessivo utile
sulla baseline; backend lasciato invariato. Provati anche gruppi compute da
32/128 thread e ulteriori salti conservativi: nessun vantaggio stabile o
regressioni, quindi scartati. Nessuna di queste varianti sperimentali rimane
nel codice consegnato.

## Resa visiva e verifiche

- Confrontate visivamente le sei coppie di screenshot: nessuna perdita di
  dettaglio evidente. Differenza RGB media 0,16–0,75 su 255; PSNR 39,8–52,0 dB.
  Non sono immagini bit-identiche: sono frame separati con animazioni,
  jitter temporale e, nel percorso, posizionamento temporale leggermente diverso.
  Questo controllo non certifica tutte le condizioni meteo o un volo prolungato.
- `node tests/sunshine_density_check.cjs`: PASS, 2.000 casi di densità,
  effectors positivi/negativi, UV originali, history vuota e fase per raggio.
- `node tests/sunshine_atmosphere_check.cjs` e
  `node tests/sunshine_ground_shadow_check.cjs`: PASS.
- Revisione del diff e `git diff --check`: PASS; modifiche preesistenti preservate.
- `tests/settings_apply_check.gd` su GPU: PASS, compresa riapplicazione senza
  ricostruzione della pipeline e cambio effettivo LOW → ULTRA.
- `tests/sunshine_pipeline_reload_check.gd`: PASS su D3D12. Vulkan/MSAA completa
  gli assert e stampa i marker, ma segnala una risorsa ancora in uso in uscita:
  non è una chiusura completamente pulita.
- Freeroam e tutorial aperti e avviati tramite Godot AI MCP con
  `autosave=false`, entrambi confermati `live`. Log dei due run senza errori;
  nessun nuovo errore editor dal cursore di avvio. Entrambi fermati al termine.
  Gli errori stradali trattenuti dal debugger precedevano questi run.
- Confronto immagini headless: marker finale, exit 0, nessun errore.
- Benchmark finale: marker finale, exit 0, nessun errore script/assert/shader.
  Rimangono warning preesistenti degli UID texture del FA-N26 e deprecazione
  `instance_reset_physics_interpolation()`.

Le esecuzioni standalone sono state avviate con deadline e cleanup del solo
albero del processo di test; mai terminati gli editor dell'utente.

## Ripetizione

Dalla radice, senza headless o `--fixed-fps` per le prestazioni GPU:

```text
godot --path . --script tools/performance_benchmark.gd -- --capture --out=user://performance
```

Opzioni: `--quick` per una sola ripetizione breve, `--views=spawn,clouds` per
limitare le viste, `--diagnose` per isolare nuvole/terreno/ombre/HUD. In
automazione usare una deadline di 240 s con cleanup dell'esatto processo
avviato; un marker senza exit 0 e log privi di errori non basta.

Il wrapper locale usato è `.pi/performance/run.cjs`; non è una dipendenza del
gioco. Le API di misurazione sono documentate in
[RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html),
[RenderingDevice](https://docs.godotengine.org/en/4.7/classes/class_renderingdevice.html)
e [Image](https://docs.godotengine.org/en/4.7/classes/class_image.html).

## Limite residuo

200 FPS richiedono **5 ms per frame**. Dopo gli interventi il solo tempo GPU
resta fra **6,62 e 10,23 ms** nelle viste misurate. Per raggiungere il target
anche nelle viste pesanti serve un intervento più profondo sul renderer
volumetrico, seguito da nuovi confronti visivi: queste ottimizzazioni non
bastano. Non sono state introdotte riduzioni di qualità per dichiararlo raggiunto.
