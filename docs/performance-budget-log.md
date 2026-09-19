# Registro operativo — budget 5 ms / 1080p nativi

Riferimento iniziale: `27c3c879805e119867d243bf2e208498d00a59e4`, working tree pulita.
Vecchio Ultra immutabile: `tools/performance_legacy_ultra.json` (parametri, revisione,
SHA-256 dei sorgenti). Nessuna scrittura alle preferenze personali.

## Recupero

- Presenti `.pi/performance/{end-to-end,clouds-pass,restart-pass}`. Report e JSON
  confermano raymarch dominante, prove obsolete/escluse e deriva a codice invariato.
  Confronti quick/percorso da 3 s e full/percorso da 6 s non intercambiabili.
- Conservate nel codice: rifiuto densità vuota, occlusione prima del campionamento,
  riapplicazione della stessa risoluzione senza riallocazione. Nessun tentativo
  workgroup/unrolling attivo. Nessun nuovo test di questi tentativi pianificato.
- Editor PID 22820 fermo sul pannello opzioni, ~1097 MiB dedicati. Nessun altro
  gioco Godot. Browser/Steam/Discord restano aperti; non terminati. Il contatore
  DWM riporta ~15 GiB: non è una somma affidabile della residenza fisica dei
  processi. Rilevazioni complete locali in `budget-pass/*before.json`.
- **Controllo stesso vecchio binario**, quick spawn/Alpi: **156,5 / 99,2 FPS**,
  GPU **6,18 / 9,86 ms**, p99 **7,65 / 11,04 ms**, zero >16,667 ms. Coerente con
  restart-pass; nessun recupero ambientale conteggiato come guadagno.

## Sonde release (quick, 3 s; non certificazione finale)

| Variante | Spawn | Alpi | Aeroporto | Decisione |
|---|---:|---:|---:|---|
| Legacy nativo 700/32 | 153,1 | 99,8 | 117,9 | riferimento |
| High originale | 306,8 | 263,0 | 245,4 | non rinominare: distanza/ombre/glow diversi |
| Half 700/32 | 252,2 | 232,2 | 201,4 | mantenere Half, margine insufficiente da solo |
| Native 384/32 | 192,6 | 95,2 | 153,9 | scartato: Alpi invariate, taglia portata; spike da ripetere |
| Native 700/16 | 168,2 | 135,4 | 143,3 | non sufficiente |
| Quarter 700/32 | 298,9 | 338,4 | 269,3 | non per Ultra: grana più grossa; Half già sufficiente |
| Half 700/16 | 272,1 | 279,6 | 231,9 | candidato |
| precedente + blur_q=1 | 282,0 | 305,4 | 245,9 | candidato: 4 tap bicubici anziché 16 |
| Half 512/16 | 280,4 | 279,9 | 250,2 | scartato per Ultra: portata ridotta senza beneficio Alpi |
| Half 700/16, distanze 60/160 | 253,7 | 281,8 | 227,5 | scartato: peggiore |
| Half 700/16, LOD 0,65 | 288,2 | 280,4 | 245,1 | scartato per Ultra: preservare dettaglio distante |

Tutte a scena nativa, copertura 0,834, stessa struttura/camere. Metadati confermano
anche i passi nel driver e nelle luci (16/32); SPIR-V identico tra le sonde.
Nessun guadagno ambientale sommato. Spike episodici su native384/light16 e 512:
non attribuiti ai preset; i tempi mediani GPU sono coerenti, controlli finali necessari.

Ablation Half700/16 blur1: GPU spawn/Alpi/aeroporto 3,37/3,12/3,88 ms;
senza nuvole 1,87/1,51/1,80; senza terreno 2,20/2,32/2,99;
senza ombre 3,30/3,00/3,65; HUD/acqua marginali. Effetti SSAO+glow
~0,6–0,7 ms nelle prime due viste. Run scaduto a 140 s nell'ultima vista:
processo figlio 2140 ripulito, dati parziali solo diagnostici; ripetere con 220 s.

## Ricostruzione / in corso

Immagini statiche congelano anche il dither: evidenziano grana più grossa Half/Quarter.
Sequenze ora allineano anche il dither per frame (non PNG I/O), includono traslazione,
rotazione 60°/s, cut e convergenza. Il riferimento vecchio renderer è conservato in
`reference-build`. In movimento Half ha sagome e profondità simili, dettaglio fine
più morbido; non è equivalenza pixel per pixel.

**Conservato:** reset su nuovi buffer/cut, letture clampate prima del controllo
fuori schermo; rimossa doppia traslazione della riproiezione. Nessun nuovo
accumulatore. Alps Half700/16/blur1 prima/dopo 303,4/301,9 FPS, GPU 3,10/3,09 ms:
correzione history, NON guadagno prestazionale. Hash SPIR-V runtime verificato
cambiato da d3144c1a… a abb80e36…; import MD5 uguale al sorgente.

## Integrazione e conferma

**Conservato:** Ultra Half/700/16/blur1, High Half/384/12/blur1. Risorsa e driver
Garda/Utah allineati; tutte le altre impostazioni Ultra preservate. Tre finestre
release per sei viste più tre viste in simulazione reale, poi restore dei due
eseguibili: miglioramento confermato, non recupero ambientale. Risultati aggregati
in `performance-budget.md` e `performance-budget-results.json`.

Ultra medio 238,7 FPS aeroporto statico, 301,0 Alpi, 228,3 aeroporto in volo,
226,1 combattimento (otto nemici, due alleati). P99 combattimento 6,57 ms, quindi
NON 200 FPS bloccati. Terza finestra aeroporto 229 FPS contro ~243 prima:
restore stesso codice 245,2, causa puntuale non dimostrata; campione non scartato.

**Conservato:** eliminato ciclo Resource→linea→Resource nel DialogueManager,
emerso nei test combat. Test isolato verifica rilascio weakref e passa senza leak;
combat release finale pulito. Il test tutorial completo ha raggiunto la fine
funzionale ma segnala errori queue_free/renderer dummy: NON superato integralmente.

**Ripetuto e completato:** diagnosi 220 s dopo timeout 140 s. Nuvole ancora ~1,5–2,1 ms,
terreno ~0,8–1,2 ms netti; HUD/acqua marginali. Airport-off peggiora per occlusione:
non trattare le ablation come costi sommabili. Nessun taglio geometrico.

**Inconcluso / da profilare:** primo combat ha stall 1304,81 ms, poi non riprodotto
nelle run calde. Ipotesi first-use shader/risorse, non diagnosi provata. Spike
occasionali 17–44 ms conservati. Non certificati cold combat né hangar/taxi/decollo
in release. Prossimo esperimento concreto: cattura del primo evento combat con
profilazione CPU/GPU e confronto cache fredda/calda, separato dai preset.

Memoria free-flight Godot 4570→4400 MiB; Windows processo 4913/210→4742/210 MiB
dedicata/condivisa. DWM espone contatore impossibile ~17 GiB: non sommato alla
residenza fisica; adapter durante combat ~9927/797 MiB. Editor/app utente non
terminati. Preferenze personali non scritte dai benchmark.
Ogni esito successivo sarà registrato qui con decisione.
