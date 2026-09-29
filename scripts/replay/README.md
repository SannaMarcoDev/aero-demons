# Replay / Cinema

Apri **REPLAY / CINEMA** dal menu principale, oppure **F7** durante un volo.
Le quattro missioni Garda/Utah registrano automaticamente a 30 Hz, anche fuori
inquadratura: aerei, missili, proiettili, esplosioni, flash, danni e suoni 3D.
Il playback interpola i campioni: non riesegue fisica, AI, armi o danni.

## Comandi

- **F6** avvia/ferma e salva una ripresa; **F9** salva senza fermarla.
- **F7** chiede conferma, salva e lascia la missione per aprire il viewer.
- **Spazio** play/pausa; **← / →** ±5 secondi. Timeline e pulsanti ±1f (30 Hz).
- Camera **libera**, **inseguimento**, **orbita**, **originale**, **regia salvata**.
- **RMB + WASD**, **Q/E** quota, **Shift** rapido; rotella velocità/distanza.
- In orbita, **RMB + mouse** cambia l'angolo; scegli il soggetto nel menu a fianco.
- **K** inserisce un keyframe; **C** registra il movimento della camera.
  Registrando da metà timeline si sostituisce la regia successiva, non il volo.
- **Salva regia** conserva la camera nel replay. Uscire dal viewer o aprire un
  altro replay salva automaticamente le modifiche; un errore impedisce l'uscita.
- **H** nasconde/mostra i controlli; **Esc** libera il mouse e mostra i controlli.

## File ed export

I `.aeroreplay` compressi sono in `user://replays/` (**Cartella replay** nell'archivio).
La registrazione si ferma e salva a 2 ore o al budget di memoria (~128 MiB stimati);
un file non compresso non può superare 256 MiB. Conserva anche la versione del
progetto: i replay riutilizzano le sue scene e risorse, non incorporano gli asset.

**Esporta · 60 fps** salva la regia e avvia Godot Movie Maker in un processo
separato. Usa la regia salvata se presente, altrimenti la camera originale.
La risoluzione del progetto è 1920×1080; il video non include l'interfaccia.

- **AVI**: MJPEG + audio PCM; limite nativo di **4 GiB**.
- **PNG**: sequenza lossless numerata + **WAV**, consigliata per montaggio e riprese lunghe.

Il processo si chiude al termine; non interromperlo durante la scrittura.
Il log è `<output>.log`: cerca `REPLAY_EXPORT_COMPLETE` e il riepilogo Movie Maker.
Per evitare di sovraccaricare il computer, avvia un export alla volta.

Le particelle sono ricostruite con un preroll fino a 6 secondi: lo scrubbing può
richiedere tempo e la distribuzione delle particelle non è un bake identico al volo.
Le scene/proprietà ammesse sono esplicite in `replay_data.gd`: nuovi tipi di attori
richiedono di aggiornare la cattura/proxy. Nessun replay può caricare script arbitrari.

## Verifica integrata

```sh
godot --headless --path . res://scenes/replay/replay_viewer.tscn -- --replay-self-check
```

Il marker finale è `REPLAY_SELF_CHECK_COMPLETE`. Controlla formato, interpolazione,
attori, cattura combattimento, riavvio registrazione e salvataggio della camera.
