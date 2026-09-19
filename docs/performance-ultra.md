# Performance — 1080p Ultra

> Rapporto storico, con i vecchi budget Ultra. Per i preset integrati Half/700/16,
> misure native ripetute e limiti residui: [performance-budget.md](performance-budget.md).
> Le baseline dei due rapporti non vanno sommate.

## Stato operativo — export release, 1080p nativi

**Target non raggiunto.** Resta il guadagno convalidato dell'**1,3–2,1%** del pass
precedente. Il pass dopo il riavvio non aggiunge ottimizzazioni al renderer.
Il precedente +25–28% sotto riportato appartiene a una diversa baseline, non a
export release nativi confrontabili.

### Ripresa dopo il riavvio dell'editor

Il riavvio eseguito dall'utente ha eliminato il forte rallentamento: **lo stesso
eseguibile release**, senza ricostruirlo, è tornato a **100–155 FPS** sulle sei
viste. Nessuno dei 13.901 frame misurati supera 16,667 ms; massimo 11,100 ms.
Prima del riavvio la sonda dava ~80–92 FPS e picchi di 87–119 ms.

| Contatore Windows durante il benchmark | Prima | Dopo il riavvio |
|---|---:|---:|
| Editor, memoria dedicata | 8.592 MiB | 1.098 MiB |
| Benchmark, memoria dedicata | 1.500 MiB | 4.913 MiB |
| Benchmark, memoria condivisa | 3.624 MiB | 210 MiB |

Il recupero sullo stesso binario, insieme alla diversa residenza, sostiene
fortemente la diagnosi ambientale legata alla memoria GPU. **Non isola la memoria
da ogni altro stato azzerato dal riavvio** e non è un guadagno dello shader.
I dati precedenti restano in `end-to-end/pressure-*` e `restored-probe/`.

Una nuova esportazione del renderer invariato ha replicato i valori iniziali.
Sono state poi provate sei varianti: unrolling lighting, rifiuto del dettaglio
vuoto con bound UNORM, rimozione della dipendenza dalla densità nel lighting,
gruppi 8×4, 8×16 e 16×4. **Nessuna conservata:** le sonde non convalidano un
vantaggio ripetibile; 8×4 è nettamente più lento. Le sonde `--quick` hanno una sola
finestra da 3 s: non confrontare il loro percorso temporizzato con quello da 6 s.

Controlli completi, stesso renderer, tre finestre da 6 s per vista; FPS e percentili
ricavati dalle timeline unite:

| Vista | FPS stesso binario dopo riavvio | FPS controllo finale | p95 finale (ms) | p99 finale (ms) |
|---|---:|---:|---:|---:|
| Spawn | 155,2 | 149,7 | 7,18 | 7,40 |
| Nuvole | 146,0 | 141,6 | 7,49 | 7,65 |
| Lago | 131,2 | 127,7 | 8,26 | 8,45 |
| Alpi | 100,2 | 98,4 | 10,61 | 10,90 |
| Aeroporto | 120,8 | 118,0 | 8,88 | 9,04 |
| Percorso | 118,3 | 115,5 | 9,37 | 9,79 |

Resta quindi una deriva minore a codice invariato, **non una regressione della
patch**: GPU mediana finale 6,41–9,83 ms; CPU render aumentata di circa
0,04–0,07 ms. I contatori del successivo volo mostrano ancora editor ~1.100 MiB
dedicati e benchmark 210 MiB condivisi, non la precedente pressione estrema.
Controllo finale: **13.525 frame**, zero >16,667 ms, massimo **11,151 ms**.
Volo con simulazione, tre ripetizioni: spawn **148,8**, nuvole **145,8**, aeroporto
**108,3 FPS**; 7.257 frame, zero >16,667 ms, massimo **10,562 ms**. Queste finestre
non risolvono né escludono gli stutter osservati nel pass precedente.

- Renderer GDScript/compute/postcompute ripristinato byte per byte allo snapshot
  iniziale; import compute verificato (`6bd929087bee883951d2e3d3dd462f53`). Nessun
  esperimento attivo; risoluzione, qualità, contenuti e budget invariati.
- PASS pulito per densità/occlusione, atmosfera, ombre, runner, metriche e confronto
  immagini in progetto vuoto; `git diff --check` pulito. Cinque statiche + 12 motion
  confrontate sullo stesso renderer: RGB medio massimo 0,084/255, PSNR minimo
  54,64 dB; nessuna differenza evidente nel montage. Percorso temporizzato escluso.
- MCP inizialmente disconnesso, poi ristabilito: freeroam `r2627561-1` e tutorial
  `r2668094-2` confermati `live`, `autosave=false`, nessun nuovo errore registrato
  gioco/editor dal cursore 0. Entrambi fermati. Bootstrap benchmark aperto;
  livelli lanciati come scene custom senza caricarli nelle schede 3D dell'editor.
  Editor finale sul pannello opzioni, `ready`, circa 1.100 MiB dedicati.
- Gli export restano diagnosticamente non puliti per risorse stradali mancanti e
  cleanup dummy. Il primo ha riportato anche un errore di copia della DLL debug
  Terrain3D, assente nell'ultimo. I benchmark release completano senza errori/leak;
  restano i warning UID/interpolazione. Il check pipeline non è stato rieseguito:
  il precedente fallimento di cleanup resta aperto.
- Hash delle modifiche utente e delle preferenze verificati. Durante la sessione
  è cambiato solo l'ordine della lista dei plugin in `project.godot`: conservato,
  verificando che plugin e resto del file coincidano con lo snapshot iniziale.
  Nessun editor o processo estraneo terminato; nessun nuovo commit.

Artefatti di questa ripresa: `.pi/performance/restart-pass/`, inclusi `same-build/`,
`baseline/`, `restored/`, `live-restored/`, contatori, immagini, log e `summary.json`.
Le tabelle della sezione seguente restano il precedente confronto A/B della patch,
non vanno sostituite o sommate al recupero ambientale.

### Metodo e modifica

- HEAD iniziale `2299d56`; Ryzen 5 7500F, RX 9070 XT, 32 GB, driver
  `32.0.31041.1004`, Godot 4.7.1, Forward+/D3D12. Template Windows **release**
  ufficiale: i JSON confermano `debug_build=false`, `editor_binary=false`.
- **1920×1080 nativi**, scala 1, upscaler OFF, TAA, nessun frame generato,
  VSync off, FPS illimitati. Ultra, terreno/ombre/contenuti e budget nuvole
  **700/32**, risoluzione piena, copertura 0,834 invariati. Preferenze salvate non scritte.
- Sei viste originali, tre ripetizioni: attesa foreste, warmup iniziale 8 s,
  3,5 s assestamento + 6 s misura. Meteo/fisica congelati nel confronto grafico.
  `--gameplay` aggiunge tre voli con fisica, boundary e vento attivi, input neutro,
  meteo ripristinato fra ripetizioni e sorvolo aeroporto a 500 m; verifica aereo vivo,
  non fermo e gioco non in pausa. **Non simula una battaglia completa.**
- Modifica renderer: in `SunshineCloudsCompute.glsl`, interrompere subito il raggio
  oltre la profondità della geometria opaca, prima di campionare/illuminare la nube
  nascosta. Nessun budget ridotto. Test esegue la vera guardia dello shader.
- Migliorato il benchmark: niente effetti collaterali negli `assert` eliminati dalle
  release; timeline grezze, p95/p99/max/stutter, controlli build/viewport, export
  dedicato e runner con deadline/cleanup del solo albero avviato. Profilazione
  opt-in `--profile-gpu`, disattivata durante i confronti finali.

### Misure prima → dopo

FPS = frame totali / tempo totale delle tre finestre; p95/p99 calcolati sulle
**timeline unite**, non sulla media dei percentili. Ogni riga include 18 s di misura.
Riferimento contemporaneo `native-reference`, finale `native-final`; prima replica
con modifica in `depth-full`, baseline iniziale separata in `native-baseline`.

| Vista | FPS medi prima → dopo | p95 prima → dopo (ms) | p99 prima → dopo (ms) |
|---|---:|---:|---:|
| Spawn | 153,3 → 155,6 | 7,17 → 6,88 | 7,45 → 7,15 |
| Nuvole | 143,3 → 146,4 | 7,68 → 7,28 | 7,87 → 7,50 |
| Lago | 129,4 → 131,5 | 8,43 → 8,10 | 8,64 → 8,29 |
| Alpi | 98,2 → 100,2 | 10,94 → 10,55 | 11,13 → 10,74 |
| Aeroporto | 119,4 → 121,0 | 9,11 → 8,77 | 9,34 → 9,03 |
| Percorso | 116,5 → 118,5 | 9,49 → 9,16 | 9,77 → 9,47 |

Nel finale grafico: **13.925 frame, zero >16,667 ms**, massimo 11,072 ms;
GPU mediana per vista 6,31–9,78 ms, risparmio 0,09–0,20 ms.

| Volo con simulazione | FPS medi prima → dopo | p95 prima → dopo (ms) | p99 prima → dopo (ms) |
|---|---:|---:|---:|
| Spawn | 152,9 → 154,7 | 7,02 → 7,22 | 7,32 → 7,49 |
| Nuvole | 147,9 → 150,7 | 7,96 → 7,77 | 8,53 → 8,34 |
| Aeroporto | 109,7 → 110,5 | 9,72 → 9,87 | 10,09 → 10,14 |

`live-reference`/`live-final`: due frame finali >16,667 ms nelle nuvole
(massimo 20,060 ms), nessuno >33,333/50 ms; riferimento senza questi picchi.
**Non tutti i percentili migliorano** e la causa dei picchi non è isolata:
nessuna certificazione di assenza di stutter. Startup e compilazioni a freddo
sono fuori dalle finestre. I tentativi `gameplay-depth` (collisione/pausa) e
`gameplay-reference` (accumulatore vento non azzerato) sono esclusi dal confronto.

### Diagnosi, qualità e limiti

- Ablation release: Alpi ~98 → **596 FPS senza nuvole**, ~107 senza terreno;
  spawn 157 → 488 senza nuvole, ~192 senza terreno. Disattivazioni **solo diagnostiche**.
  Timestamp separati: raymarch ~3,8 ms spawn, ~7,8 ms Alpi; postpass ~0,3–0,4 ms,
  prepass/display ~0,025 ms ciascuno. Il pass dominante da solo supera i 5 ms
  disponibili nelle Alpi. I timestamp grezzi di questo backend sono convertiti
  in ms con delta / 1.000.000, non / 1.000.
- Editor lasciato sul pannello opzioni durante le misure. Campionamento Windows
  della baseline: GPU dominata dal processo benchmark (~94% nei campioni), non
  dal precedente viewport editor (~12–13%). Non spiega retroattivamente tutta
  la deriva storica. Nessun processo editor dell'utente terminato.
- Scartati rifiuto macro prima del curl e rimozione conservativa della dipendenza
  dalla densità nel loop lighting: nessun beneficio utile rispetto alla baseline.
  Sorgenti e log conservati, non presenti nel renderer finale. Provato anche
  unrolling dei 32 campioni lighting con guardia conservativa (`unrolled/`):
  scartato come non convalidato, perché il successivo ripristino mostra lo stesso
  rallentamento ambientale. Non attribuire a questa variante il calo assoluto.
- Confrontate cinque viste statiche e **12 acquisizioni a passi di camera identici**
  (nuvole, Alpi, aeroporto). Nessuna degradazione evidente nelle immagini esaminate;
  differenza RGB media massima 0,153/255, PSNR minimo 52,15 dB.
  La capture del percorso temporizzato non è allineata esattamente: non usata come
  prova quantitativa di equivalenza. `--motion` limita a 60 FPS **solo l'acquisizione
  successiva** alle misure. Non copre ogni frame, meteo o volo lungo.
- PASS pulito: densità/occlusione, atmosfera, ombre, metriche in progetto isolato,
  runner (inclusi errori/leak/timeout), settings live, benchmark release e confronto
  immagini isolato. `git diff --check` e hash di import verificati.
- Il check pipeline D3D12 completa gli assert ma lascia **2 oggetti/1 risorsa**:
  non è PASS pulito. Anche test headless con autoload musicale hanno mostrato
  `AudioStreamWAV`/`AudioStreamPlaybackWAV` residui; per analisi pure usare il
  progetto vuoto, senza nascondere gli errori. Export termina con codice 0 ma
  conserva errori preesistenti di risorse stradali mancanti e cleanup dummy:
  **non è un export diagnosticamente pulito**. I run release finali sono puliti;
  restano warning UID delle texture aereo e API di interpolazione deprecata.
- MCP: freeroam (`r66221596-14`) e tutorial (`r66341319-15`) confermati `live`,
  `autosave=false`, senza nuovi errori gioco/editor dal cursore 8. Freeroam ha
  eseguito anche 90 frame di input controllato rollio/sparo, con rilascio finale;
  entrambi fermati. Editor lasciato sul pannello opzioni per non aggiungere altro
  carico. Queste verifiche non sono benchmark release né collaudi di battaglia.
- Restano: target 200, validazione combattimento/cambi meteo/cold-start e indagine
  stutter/cleanup. Un nuovo pass deve attaccare il costo del raymarch, non ridurre
  risoluzione, passi o contenuti; nessuna garanzia che le micro-ottimizzazioni bastino.

### Riprodurre e riprendere

Artefatti in `.pi/performance/end-to-end/`: log, JSON con timeline e metadati,
PNG, `final-summary.json`, `final-image-check/`, shader sperimentali e snapshot/hash
iniziali. `.pi/` è ignorata da Git. Hash archivio template locale `templates.tpz`:
`86409db6200b6f8fd3230989c2d2002851f3dd18acf11d7bdbafddf5a0dd0f72`.
Il preset usa `templates/windows_release_x86_64.exe` sotto questa cartella.

```text
godot --headless --path . --export-release "Windows Performance" .pi/performance/end-to-end/build/AeroDemons.exe
node tools/run_godot_check.cjs 240 .pi/performance/repeat.log .pi/performance/end-to-end/build/AeroDemons.exe -- --capture --motion --out=C:/PERCORSO/ASSOLUTO/risultati
node tools/run_godot_check.cjs 140 .pi/performance/live-repeat.log .pi/performance/end-to-end/build/AeroDemons.exe -- --gameplay --out=C:/PERCORSO/ASSOLUTO/volo
```

Sostituire `godot` con l'eseguibile locale 4.7.1. Il preset `performance` seleziona
il main loop del benchmark **solo nell'export dedicato**, non cambia l'avvio normale.
Per l'export automatizzato è stato usato il wrapper locale `.pi/performance/run.cjs`
con deadline 180 s; leggere comunque il log, exit 0 non annulla gli errori.
Dopo ogni modifica GLSL: scan editor e verifica MD5 importato **prima** dell'export.
Niente headless/`--fixed-fps` nelle misure GPU e nessun altro run GPU simultaneo.
Il marker `PERFORMANCE BENCHMARK PASS` certifica completamento, **non** il target 200 FPS.

Per immagini e metriche: progetto vuoto con solo `config_version=5`, come
`.pi/performance/end-to-end/image-project/project.godot`; passare a Godot
`--headless --path PROGETTO_VUOTO --script SCRIPT_ASSOLUTO` tramite lo stesso runner.
Script: `tests/performance_metrics_check.gd` oppure `tools/compare_performance_images.gd`
(con `-- PRIMA_ASSOLUTO DOPO_ASSOLUTO OUTPUT_ASSOLUTO`).

## Storico precedente — non export release nativo


**Prima sessione: guadagno misurato 25–28%. Target 200 FPS non raggiunto.** Nessuna riduzione
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

## Passata successiva alle nuvole — dopo `2299d56`

**Nessuna ottimizzazione aggiuntiva conservata:** le varianti provate non hanno
mostrato un miglioramento consistente sulle sei viste. Ripristinati esattamente
shader e script del commit, senza riduzioni di qualità. Le modifiche preesistenti
dell'utente sono rimaste escluse dal commit e intatte.

Provati: ulteriori uscite anticipate sulla densità, limite di estinzione a
underflow float32, specializzazione della pipeline senza luci/effector locali,
workgroup 8×4 e 16×4, fattorizzazione della radiance direzionale e ricorrenza dei
profili atmosferici. Questi esperimenti non sono codice consegnato. Le prove
brevi usano `--quick`; baseline e ripristino finale hanno tre ripetizioni.

| Vista | FPS baseline della passata | FPS dopo ripristino | GPU baseline → ripristino |
|---|---:|---:|---:|
| Quota di partenza | 94,2 | 93,7 | 10,25 → 10,28 ms |
| Dentro le nuvole | 92,9 | 90,6 | 10,35 → 10,49 ms |
| Lago | 98,7 | 96,3 | 9,78 → 10,01 ms |
| Alpi | 92,0 | 91,9 | 10,53 → 10,55 ms |
| Aeroporto | 93,6 | 90,3 | 10,33 → 10,68 ms |
| Percorso in volo | 88,8 | 86,2 | 10,96 → 11,31 ms |

Le due colonne eseguono lo **stesso codice**, non rappresentano un prima/dopo
di un'ottimizzazione. Illustrano anche la deriva della misura. Impostazioni e
budget JSON identici. I valori assoluti della prima sessione non si sono
riprodotti: questa passata va confrontata con la propria baseline, non con
quella storica. Nella nuova sonda spawn, senza nuvole restano 6,17 ms GPU:
non si può attribuire tutto il costo corrente al solo renderer delle nuvole.
La causa della differenza fra sessioni non è stata isolata.

Importante per ripetere gli esperimenti: eseguire una scansione completa del
filesystem dell'editor dopo le modifiche GLSL/include. Il solo comando MCP
`reimport` ha riportato successo ma lasciato il vecchio shader importato;
la prima sonda `probe` è quindi esclusa. `probe-imported` è la ripetizione
successiva alla scansione. Controllare anche hash/data degli import prima di
considerare attendibile una misura.

Artefatti locali: `.pi/performance/clouds-pass/` (sorgenti sperimentali, log,
JSON e screenshot). Benchmark finale: marker PASS, exit 0, nessun errore.
Controlli densità, atmosfera e ombre: PASS; shader ripristinati senza diff.
Il test pipeline D3D12 completa gli assert, ma in questa ripetizione segnala
2 oggetti e 1 risorsa residui in uscita: **non è una chiusura pulita**.
Restano i warning preesistenti degli UID dell'aereo e dell'interpolazione fisica.
Freeroam e tutorial avviati tramite MCP con `autosave=false`, confermati `live`,
senza nuovi errori nei log di gioco/editor dal cursore 8. Fermati entrambi;
editor riportato su `garda_final.tscn`. Nessun nuovo codice runtime consegnato.
