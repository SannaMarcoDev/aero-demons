# Tutorial map — analisi ambientale e ripresa lavori

## Stato e obiettivo

Richiesta: osservare la tutorial map da diverse angolazioni, anche sopra le nuvole, e individuare le migliorie ambientali necessarie per avvicinarla a una mappa finita di qualità AAA.

È stato creato e provato `tools/tutorial_survey.gd`. Non sono state applicate migliorie alla mappa: questa fase comprende osservazione, diagnosi preliminare e proposte.

**Conclusione:** non manca soltanto arredamento. Prima va sistemata la leggibilità di materiali, atmosfera e nuvole; poi si aggiungono landmark e dettagli ambientali.

## Scena effettivamente analizzata

- `scenes/maps/tutorial_map.tscn`: scena indicata come principale in `project.godot`.
- `scenes/levels/freeroam.tscn`: scena aperta nell'editor durante l'analisi; istanzia la stessa tutorial map e aggiunge player/HUD. Player a `(0, 2000, 0)`.
- `tutorial_map.tscn` nella root: copia non tracciata già presente, non modificata né usata per il survey. Fa riferimento a un diverso percorso della risorsa nuvole.
- Ambiente: Sky3D + SunshineClouds2 + Terrain3D.
- Nuvole: `resources/environments/tutorial_clouds.tres`.
- Dati terreno: `wc_data/WC_Terrain/`.

La scena della mappa contiene terreno, cielo/luci e driver nuvole, senza nodi dedicati a infrastrutture, landmark, acqua o effetti ambientali locali.

## Script di osservazione

File: `tools/tutorial_survey.gd`.

Da PowerShell, nella root del progetto:

```powershell
& "..\..\Godot_v4.7.1-stable_win64.exe" --path . --script tools/tutorial_survey.gd -- --hold
```

L'eseguibile trovato durante la sessione è:

```text
C:\Users\sanna\Workspace\Godot\Godot_v4.7.1-stable_win64.exe
```

Lo script carica la mappa separatamente dalla scena di gioco e crea otto viste:

1. Spawn del freeroam.
2. Nord, vicino al terreno.
3. Est, vicino al terreno.
4. Sud, vicino al terreno.
5. Ovest, vicino al terreno.
6. Sopra le nuvole, verso il terreno.
7. Sopra le nuvole, verso l'orizzonte.
8. Zenitale.

Le viste sopra le nuvole sono a 7.800 m con la configurazione attuale, ossia 1.800 m sopra il cloud ceiling. Le posizioni vengono calcolate dai limiti del terreno e dalla risorsa nuvole; lo spawn riprende le coordinate attuali del freeroam.

- Cattura PNG a 1280×720 e un `views.json` con le coordinate.
- Aspetta tre secondi per vista prima dello screenshot.
- `--hold`: resta aperto dopo le catture; frecce sinistra/destra cambiano vista, Esc esce.
- Senza `--hold`: termina dopo le catture.
- `--no-clouds`: disabilita le nuvole solo nel processo di osservazione, per un confronto diagnostico. Non salva modifiche alla risorsa.
- `--check`: verifica geometria delle otto viste, senza richiedere rendering grafico.

Esempi:

```powershell
# Confronto senza nuvole
& "..\..\Godot_v4.7.1-stable_win64.exe" --path . --script tools/tutorial_survey.gd -- --no-clouds

# Check headless
& "..\..\Godot_v4.7.1-stable_win64.exe" --headless --path . --script tools/tutorial_survey.gd -- --check
```

Gli screenshot richiedono un renderer grafico Forward+, non headless.

## Catture e dati raccolti

Directory base:

```text
%APPDATA%\Godot\app_userdata\Aero Demons\tutorial_survey\
```

Passaggi finali:

- `2026-09-07T10-14-10`: con nuvole, viste laterali abbassate vicino al terreno.
- `2026-09-07T10-14-46`: senza nuvole, confronto diagnostico.
- `2026-09-07T10-12-55`: primo passaggio esplorativo; le viste laterali erano troppo alte e risultavano coperte dalle nuvole. Preferire i due passaggi finali.

Le immagini sono locali, fuori dal repository; non sono state copiate in `docs`.

Limiti del terreno riportati dallo script:

- X: −26.624 .. +26.624 m.
- Z: −26.624 .. +24.576 m.
- Altezze: 0 .. 3.468,276 m.

Questi sono limiti delle regioni Terrain3D, non una misura del percorso effettivamente giocabile.

## Findings e migliorie proposte

### P1 — Materiali del terreno

**Osservazione:** neve e roccia producono un effetto “sale e pepe”, visibile anche da lontano. Il dettaglio fine domina la lettura delle forme.

**Evidenza tecnica:** Terrain3D segnala mipmap mancanti per le texture albedo e normal dei sette asset. In `wc_data/textures/Texture_0_Albedo_packed.png.import` è stato verificato `mipmaps/generate=false`.

**Proposta:** abilitare mipmap, verificare filtraggio e scala dei materiali, poi rendere più ampie e coerenti le zone di neve, roccia e detrito. Non attribuire tutto il rumore alle mipmap prima del confronto visivo: anche distribuzione dei materiali e contrasto possono contribuire.

### P1 — Nuvole viste da sopra

**Osservazione:** sopra lo strato nuvoloso compare una distesa quasi bianca, con pochissimo rilievo leggibile e una fascia scura all'orizzonte. Lo mostrano soprattutto `06_above_clouds.png` e `07_cloud_horizon.png`.

**Configurazione attuale:**

- `clouds_coverage = 0.965`.
- `clouds_density = 0.1`.
- `cloud_floor = 2000.0`.
- `cloud_ceiling = 6000.0`.

**Proposta:** verificare prima illuminazione, esposizione e compositing, quindi lavorare su copertura, aperture e scala dei volumi. Aumentare semplicemente la qualità del raymarch non garantisce di correggere l'aspetto. La causa precisa della fascia scura e della perdita di rilievo non è stata diagnosticata.

### P1 — Profondità atmosferica

**Osservazione:** montagne vicine e lontane mantengono contrasti simili; la separazione tra piani è debole.

**Evidenza tecnica:** la nebbia Sky3D è disattivata nella scena. Questo non significa che SunshineClouds non applichi alcun contributo atmosferico.

**Proposta:** introdurre foschia atmosferica progressiva e banchi locali nelle valli, mantenendo leggibili ostacoli e percorso tutorial. Verificare l'interazione con l'atmosfera già applicata dalle nuvole, evitando sovrapposizioni eccessive.

### P2 — Confini del mondo

**Osservazione:** la zenitale senza nuvole rivela bordi rettangolari netti sul vuoto. `world_background = 0` nel materiale Terrain3D.

**Proposta:** montagne di sfondo semplificate e una transizione periferica coerente. Non affidarsi soltanto alle nuvole per nascondere i bordi, dato che il giocatore può salire sopra lo strato nuvoloso.

### P2 — Identità e orientamento

**Osservazione:** il paesaggio è quasi esclusivamente terreno innevato; mancano riferimenti costruiti riconoscibili nelle viste e nodi dedicati nella scena.

**Proposta:** pochi landmark grandi e leggibili in volo, per esempio:

- Una base aerea.
- Un radar su una cresta.
- Un'infrastruttura importante nella valle.

Collegarli visivamente tramite strade e infrastrutture secondarie. La loro posizione deve supportare orientamento e percorso tutorial, non essere decorazione casuale.

### P3 — Dettaglio ambientale

**Osservazione:** fondovalle e pendii non raccontano usi o processi differenti. Nella vista ovest emerge un bacino/fondovalle molto scuro; non è stata verificata la sua destinazione artistica.

**Proposta:** ghiacciai, accumuli e cornici di neve, ghiaioni e strade di servizio. Acqua o ghiaccio nel bacino soltanto se coerenti con la direzione artistica. Non assumere che la zona scura sia già un lago.

### P3 — Vita ambientale

**Evidenza:** la scena della mappa non contiene effetti ambientali locali dedicati. Audio e resa in movimento non sono stati valutati nel survey statico.

**Proposta:** neve sollevata sulle creste, pennacchi localizzati, luci di segnalazione e audio del vento variabile con quota/esposizione. Distribuire gli effetti in punti significativi, non uniformemente su tutta la mappa.

## Opzioni di intervento

### A — Polish tecnico

Materiali, atmosfera, nuvole e bordi.

È il miglior primo investimento: migliora tutta l'immagine senza riempire la mappa di asset. Non richiede di sostituire preventivamente i sistemi già installati.

### B — Scenario alpino militare (consigliato)

Polish tecnico più tre landmark collegati visivamente da strade/infrastrutture.

Dà identità e aiuta l'orientamento nel tutorial. È una proposta di direzione artistica, non una scelta già approvata dall'utente.

### C — Scenario cinematografico

Aggiunge meteo articolato, ghiacciai/acqua e dettagli localizzati lungo il percorso.

Richiede più lavoro artistico e un budget GPU misurato. Non è ancora disponibile una stima prestazionale o temporale affidabile.

**Raccomandazione:** partire da A, poi aggiungere i landmark di B. Vegetazione e particelle non correggono i problemi dominanti attuali. Il livello “AAA” non deriva dal numero di effetti, ma dalla coerenza artistica e tecnica del risultato.

## Verifiche eseguite e limiti

- Check headless finale: superato, otto viste valide e due sopra il cloud ceiling.
- Due passaggi grafici finali completati: con/senza nuvole, otto PNG ciascuno.
- Rendering: Godot 4.7.1 stable, Forward+, D3D12, AMD Radeon RX 9070 XT.
- Immagini selezionate aperte e osservate, incluse spawn, viste laterali, sopra nuvole e zenitale senza nuvole.
- Nessun `SCRIPT ERROR` o `ERROR:` nei log dei due passaggi grafici finali.
- Presenti warning sulle mipmap e sul rilascio di risorse GPU alla chiusura. La causa dei warning di rilascio non è stata isolata; non sono stati corretti.
- `git diff --check` senza segnalazioni.
- Prestazioni/frame time, stabilità temporale delle nuvole, audio e navigazione manuale del viewer non ancora validati.
- L'attesa fissa di tre secondi è una semplificazione: non misura la convergenza della history delle nuvole. I confronti non sono garantiti pixel-identici, anche perché il vento continua ad aggiornarsi.

Documentazione API consultata: Godot 4.7, cattura del viewport dopo `RenderingServer.frame_post_draw` e script standalone che estendono `SceneTree`.

## Riprendere al prossimo incontro

1. Rileggere questo documento e confrontare le immagini dei due passaggi finali.
2. Confermare la direzione artistica, se si procede oltre il polish tecnico.
3. Iniziare con una modifica circoscritta a materiali/mipmap e ripetere il survey per il confronto.
4. Diagnosticare il bianco delle nuvole e la fascia scura dall'alto prima di aggiungere effetti.
5. Lavorare sulla profondità atmosferica e sui bordi.
6. Solo dopo, collocare landmark e dettagli lungo il percorso di gioco e misurare il costo in movimento.

### Protezione del lavoro esistente

All'inizio della sessione erano già presenti modifiche a:

- `addons/SunshineClouds2/SunshineClouds.gd`
- `project.godot`
- `scenes/player/player.tscn`
- `scripts/camera/follow_camera.gd`
- `scripts/player/player_flight.gd`
- `scripts/vfx/explosion_fx.gd`
- `wc_data/WC_Terrain/terrain3d_12_04.res`

Erano inoltre già non tracciati `scenes/levels/`, `tests/player_camera_check.gd`, il relativo UID e `tutorial_map.tscn` nella root.

Non ripristinare né sovrascrivere questi file per ripartire dall'analisi. Le aggiunte di questa attività sono lo script di survey e questo documento; nessun commit è stato creato.
