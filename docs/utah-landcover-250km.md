# Utah landcover — scala geografica 250 × 250 km

Scena: `res://scenes/maps/utah_landcover_250km.tscn`.
Dati e manifest: `res://terrain/utah_landcover_250km/`.
La scena principale e la precedente validazione a 50 km non sono sostituite.

## Conversione verificata

- 8192² campioni, 64 regioni da 1024², `vertex_spacing = 30.517578125` m.
- Estensione 250000 × 250000 m, limiti X/Z ±125000 m. Nessun ridimensionamento del nodo Terrain3D.
- Stessa rotazione globale 90° oraria della versione validata: pixel sorgente `(x,y)` → `X=(8191-y-4096)*spacing`, `Z=(x-4096)*spacing`.
- Nessun ricampionamento aggiuntivo. Colormap e controlli delle otto classi identici byte per byte alla versione a 50 km.
- Camera con piano lontano a 300 km; limite di rientro calcolato dalla geometria a 119 km.

Il RAW geografico `terrain/source/utah_250km/utah_250km_worldmachine.r16` codifica 0–65535 come **893,52–3872,37 m**, secondo il relativo `utah_250km_info.txt`.
Lo stamp dell'archivio `outputs/utah_landcover_v1.wcr` lo rimappa invece su **11–3000 m**, con `HeightScale=1`, `HeightOffset=0`, operazione Overwrite.
L'importatore verifica questi parametri e ripristina il riferimento altimetrico con:

```text
Y = (WC_EXR_R - 11) × (3872.37 - 893.52) / (3000 - 11) + 893.52
  = WC_EXR_R × 0.9966042154566744 + 882.5573536299765
```

Non è una regressione, una moltiplicazione Y×5 o una normalizzazione sugli estremi dell'EXR. È l'inversa della rimappatura documentata dello stamp, applicata uniformemente durante il nuovo import. La forma WC non viene sostituita dal DEM, scolpita o rielaborata localmente. Le altezze finali RF sono **1034,19885–3838,67163 m**; l'export WC originale resta **152,15825–2966,18677 m**.

### Limite altimetrico, non nascosto dalla conversione

Ripristinare il riferimento altimetrico non annulla la lavorazione/interpolazione già avvenuta in WC. Gli estremi e tutti i pixel non coincidono con il DEM originale.
Su una griglia di 262144 punti (passo 16 pixel), il residuo `WC convertito − RAW geografico` ha RMS **9,903 m**, 99° percentile assoluto **38,637 m**, estremi campionati **−139,659 / +125,567 m**. Questi estremi non sono un limite certificato sull'intero raster. Per fedeltà pixel-per-pixel al DEM occorre correggere e riesportare la geometria in **World Creator**, non rimpiazzarla in Godot.

| Riferimento | X / Z mondo (m) | WC originale (m) | WC convertito (m) | RAW geografico (m) | Differenza (m) |
|---|---|---:|---:|---:|---:|
| A, bacino NW | 46844,482 / −97656,250 | 1819,953 | 2696,330 | 2696,330 | +0,000 |
| B, Lake Powell sud | −116729,736 / −58593,750 | 249,841 | 1131,550 | 1114,564 | +16,986 |
| C, corridoio fluviale | −48248,291 / 8789,063 | 426,349 | 1307,459 | 1300,427 | +7,032 |

I confronti usano il RAW16 documentato. Durante la diagnosi il TIFF master è stato letto senza modificarlo: il writer `tools/fetch_utah_250km.cjs` memorizza float32 ma omette il tag TIFF SampleFormat=3; una normale apertura Pillow lo interpreta come interi. La lettura dei byte float è stata verificata contro il RAW16 (scarto massimo campionato 0,026 m). Il TIFF non è utilizzato per costruire questa importazione.

## Verifiche eseguite

- `tools/import_wc_utah_native.py --check`: PASS, comprese le estremità della conversione altimetrica.
- Import `--geographic`: PASS, 64 regioni, checksum degli input invariati.
- Test 250 km headless: PASS, exit 0.
- Test 250 km Forward+ / D3D12, AMD Radeon RX 9070 XT: PASS, exit 0.
- Regressione 50 km headless con lo stesso test parametrizzato: PASS, exit 0.
- Avvio standalone tramite Godot AI MCP (`custom`, `autosave=false`): stato `live` confermato, Terrain3D con spacing 30,517578125 e trasformazione identità, camera corrente con far 300000 m. Riproduzione poi fermata; editor lasciato sulla nuova scena. Il timeout iniziale della chiamata MCP non era un fallimento del caricamento.
- 96 campioni indipendenti di height/control/colormap, inclusi tre riferimenti lontani e ambo i lati delle separazioni fra regioni; 192 hash delle mappe; tutti i 67108864 pixel control verificati, otto ID, flag inferiori zero.
- Mappe colore/control confrontate con la versione a 50 km; dati e scena a 50 km confrontati con lo snapshot precedente. Anche il baseline dei file originali e dell'import vecchio a 250 km passa.
- Collisione allo spawn reale: hit **1503,56 m**, altezza interrogata **1503,59 m**. Spawn a `(15.2587890625, 3600, 15.2587890625)`, oltre 2 km sopra il terreno.

Il primo raycast esattamente a X=Z=0 non colpiva la collisione. Una diagnosi separata ha riprodotto il miss su quel vertice condiviso e hit a ±0,001 m e nei punti vicini. Lo spawn e la camera della nuova scena sono quindi al centro di una cella, non sul vertice comune di quattro regioni/shape. Il test controlla la scena così com'è, senza correggere collisione o materiali durante il caricamento. Non è una correzione generale dell'intersezione dei raycast del motore: il caso puntuale all'origine resta documentato in `logs/collision_probe.log`; i corpi con volume non sono stati sottoposti a una prova esaustiva su tutte le cuciture.

Restano i warning Godot/Terrain3D di deprecazione e rilascio risorse, incluso `resources still in use at exit` nel test headless. I log completi distinguono il primo tentativo renderer fallito dalle successive verifiche finali PASS. Materiali di dettaglio e atmosfera sono quelli provvisori della scena precedente, senza un nuovo passaggio di look-development. Non sono stati aggiunti acqua, alberi, edifici o un player. Il controller dei confini calcola correttamente l'estensione ma segnala `no player in scene; boundary inactive` nell'avvio standalone: è una scena di validazione, non un nuovo livello giocabile.

## Riproduzione ed evidenze

Da PowerShell nella radice del progetto, sostituendo i percorsi degli eseguibili se necessario:

```powershell
$python = 'C:\Users\sanna\AppData\Local\Programs\Python\Python313\python.exe'
$godot = 'C:\Users\sanna\Workspace\Godot\Godot_v4.7.1-stable_win64.exe'
& $python tools/import_wc_utah_native.py --check
# Solo per rigenerare in una directory NUOVA: l'importatore rifiuta sovrascritture.
& $python tools/import_wc_utah_native.py --geographic --destination terrain/utah_landcover_250km_rebuild
& $godot --headless --path . --script res://tests/utah_landcover_import_check.gd -- --geographic
& $godot --path . --script res://tests/utah_landcover_import_check.gd -- --geographic
# Regressione della scena nativa a 50 km:
& $godot --headless --path . --script res://tests/utah_landcover_import_check.gd
```

Le esecuzioni effettuate sono state racchiuse in subprocess con timeout esterno e controllo dell'exit code e del marcatore PASS. Il test punta alla scena consegnata, non alla directory facoltativa `_rebuild`.

Evidenze esterne:
`C:/Users/sanna/Documents/Codex/2026-09-14/new-chat/outputs/godot_validation_v1/validation_250km/`

- `delivery_manifest.json`: checksum degli artefatti e risultato delle verifiche.
- `import_manifest.json`: copia del manifest dell'import, con conversione, input/checksum e residui.
- `baseline_50km.json`: snapshot di preservazione della scena/dati a 50 km.
- `logs/final_headless.log`, `logs/final_forward_plus.log`, `logs/regression_50km_headless.log`.
- `screenshots/overview_topdown.png`, `landmark_A.png`, `landmark_B.png`, `landmark_C.png`, `detail_ground.png`: render reali 1920×1080, non immagini generate.

I percorsi degli export WC, dei mask di riferimento e dei baseline nei test/importatore sono locali e assoluti: non è un bundle portabile. Nessun computer use/UI automation, nessun commit; originali ed export sorgenti preservati.
