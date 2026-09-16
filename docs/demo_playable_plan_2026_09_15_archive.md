# Aero Demons — Piano della demo giocabile e pubblicabile

Documento di lavoro della sessione di progettazione del 15 settembre 2026.
Stato: **intervista in corso, aggiornata fino alle risposte al round 17**.
Le domande Q49–Q50 del round 18 non hanno ancora ricevuto risposta.

Questo documento conserva le decisioni prese con il responsabile del progetto,
le alternative scartate, i rinvii espliciti e i riscontri dell'ispezione tecnica.
Non è ancora una specifica completa né un'autorizzazione a implementare il gioco.
La creazione del documento, il commit e il push sono stati richiesti esplicitamente.

## 1. Metodo e legenda

Il confronto si svolge nei ruoli di project manager e game designer, per round:
si chiedono le decisioni le cui premesse sono già definite, indicando una proposta,
e si attende la risposta prima di procedere alle decisioni dipendenti.

- **Confermato:** scelta approvata dall'utente.
- **Proposta aperta:** raccomandazione dell'assistente, non ancora approvata.
- **Rimandato:** decisione che l'utente ha esplicitamente scelto di affrontare dopo.
- **Riscontro statico:** quanto individuato nei sorgenti; non prova di funzionamento.
- **Da verificare:** informazione o qualità non dimostrata dall'ispezione.

Prima dell'implementazione occorrerà confermare la comprensione condivisa del piano.
Le raccomandazioni contenute nelle domande non valgono come decisioni senza risposta.

## 2. Obiettivo, pubblico e perimetro confermati

- La demo deve **convincere i giocatori a seguire e acquistare il gioco completo**.
- Destinazione principale: **Windows su Steam**. itch.io è stato menzionato come
  alternativa opzionale, ma non è un requisito concordato.
- Esperienza: missioni spettacolari e narrative, pilotaggio agile e combattimento
  aereo arcade. Non un semplice prototipo tecnico.
- Tono: **esagerato e sopra le righe**, non prevalentemente serio o realistico.
- Quattro missioni collegate, corrispondenti all'**inizio della campagna definitiva**.
- Sblocco sequenziale delle missioni e possibilità di rigiocare quelle sbloccate.
- Prima missione con tutorial integrato; quarta missione con boss.
- Durata indicativa: **15–20 minuti per missione, circa 60–80 minuti complessivi**,
  senza contare morti e tentativi ripetuti. La durata effettiva va misurata.
- Combattimento predominante, alternato a radio, narrativa, avvicinamenti e brevi
  momenti di respiro. Nessun trasferimento lungo inserito per allungare la durata.
- Arco della demo con una conclusione locale soddisfacente e un aggancio al seguito.
- **Nessuna scadenza esterna.**
- Tempo disponibile, collaboratori e budget non vengono affrontati per ora,
  su richiesta dell'utente. Non sono state prodotte stime o assegnazioni di risorse.
- **Niente missioni di escort.** Non sostituirle con protezioni mascherate senza
  una nuova decisione esplicita.

## 3. Identità narrativa confermata

### Mondo e conflitto

Fantascienza militare in un mondo riconoscibile: combattiamo altri aerei e basi
nemiche a terra, con una minaccia aliena incarnata dai boss, in scontri tipo kaiju.

La nostra fazione affronta una **fazione nemica che cerca di usare gli alieni per
distruggerci**. Per questa demo il nemico **riesce a controllare e impiegare il boss**:
non è prevista una perdita di controllo né un cambio di schieramento degli alieni.

La nostra unità è una **squadriglia d'élite di una forza militare regolare**, con
piloti spericolati e metodi discutibili, coerente con il tono sopra le righe.

### Protagonista e personaggi

- Il protagonista è **silenzioso**.
- Gregari, comando e avversari sostengono dialoghi e caratterizzazione.
- Nomi, biografie, fazioni nominate e cast definitivo non sono ancora stati decisi.
- I vecchi nomi `CARCINOPTERAS` e `KENTRIPLOKAME` trovati nell'HUD non sono canon
  approvato: sono residui di codice precedente.

### Presentazione

- Combinazione di **briefing illustrati, comunicazioni radio e sequenze
  cinematografiche**, con doppiaggio.
- Testi in **italiano e inglese**.
- Doppiaggio **momentaneamente solo inglese**.
- Briefing e sequenze narrative **per ora non saltabili**, anche nei tentativi
  successivi. Non introdurre automaticamente un comando di salto.
- La sceneggiatura, la durata delle sequenze e il dettaglio delle singole scene
  non sono ancora definiti.

## 4. Controlli, fallimento e persistenza

### Controlli

La demo è progettata per **solo controller, con rimappatura**.
Deve essere possibile completare anche menu, opzioni, selezione equipaggiamento,
pausa e retry senza tastiera o mouse.

Il supporto tastiera/mouse oggi presente nel progetto non diventa un requisito
pubblico della demo. Non è stata richiesta la sua rimozione dal codice.
Tipi di controller da garantire, prompt, gestione disconnessione e dettagli della
rimappatura restano da definire e verificare.

### Fallimento e salvataggio

- Morte: **riavvio dell'intera missione**, anche nella boss fight.
- Nessun checkpoint e nessun salvataggio interno alla missione.
- Chi interrompe una missione la ricomincia dall'inizio.
- Si salvano tra sessioni **missioni completate e sbloccate**.
- La narrativa rimane non saltabile per ora.

Rischio da verificare nei playtest: combinazione di missioni da 15–20 minuti,
riavvio completo e narrativa ripetuta. Questo rischio non autorizza a cambiare
le regole concordate. I pericoli devono essere leggibili e le morti comprensibili.

## 5. Aerei, missili e upgrade

### Decisioni correnti

- Riutilizzare la dotazione esistente: tre modelli di aereo e cinque tipi di missile.
  Nessun nuovo aereo o missile richiesto per ora.
- **Un solo aereo disponibile inizialmente**; gli altri si sbloccano successivamente.
- Scelta dei missili già nella prima missione, limitata a quelli disponibili.
- Alcuni missili saranno sbloccabili in seguito.
- **Tutte le manovre speciali diventano upgrade degli aerei**, inclusi High-G e
  spin dash.
- High-G deve arrivare **molto presto**, ma senza una missione o un momento fissati.
- Scopo dichiarato degli upgrade: **distribuire l'apprendimento**, evitando di
  spiegare tutti i sistemi nella prima missione.
- Il tutorial si concentra sui comandi fondamentali di volo e combattimento.

### Decisioni esplicitamente rimandate

- Quando si sbloccano gli altri aerei.
- Quali missili sono disponibili inizialmente e quando si sbloccano gli altri.
- Tempi precisi di assegnazione e insegnamento degli upgrade.

### Ulteriori aspetti ancora aperti

- Differenze reali tra gli aerei: oggi le prestazioni sono condivise e la varietà
  è soprattutto visiva.
- Se gli upgrade siano specifici di un modello, trasferibili o condivisi.
- Come si ottengano o equipaggino gli upgrade e come si salvino questi sblocchi.
- Eventuali costi, valuta o altri sistemi di progressione.

La proposta di evitare valuta e acquisti ripetitivi e assegnare gli upgrade con
la storia **non è ancora una decisione approvata**.
Non è approvata neppure la proposta di rendere High-G una capacità di base.

## 6. Struttura confermata delle quattro missioni

| Missione | Mappa | Scopo principale |
|---|---|---|
| 1 — Tutorial | Garda | Collaudare l'aereo riparato, imparare i fondamentali, incontrare nemici inattesi |
| 2 — Assalto | Utah | Distruggere basi nemiche seguendo gli ordini del comandante |
| 3 — Scoperta | Mappa 3, ancora in lavorazione | Scoprire cosa stanno davvero facendo i nemici |
| 4 — Boss | Utah | Affrontare la medusa aliena gigante controllata dai nemici |

Tre mappe distinte, non quattro missioni sul Garda. La mappa 3 non è ancora stata
identificata per nome o percorso nel progetto durante questa conversazione.

## 7. Missione 1 — Collaudo sul Garda

### Premessa e apertura

L'aereo del protagonista è appena stato riparato. Il volo serve a verificare che
funzioni tutto correttamente e dovrebbe essere tranquillo.
Siamo in una zona alleata considerata sicura e lontana dalle operazioni.

Apertura con una **breve sequenza cinematografica sull'aereo riparato**, poi
controllo del giocatore **già in volo**. Nessun decollo manuale richiesto.
Non è un'esercitazione militare generica: il collaudo è l'inizio della storia.

### Insegnamento

- Istruzioni radio integrate nella missione.
- Azioni pratiche verificabili: seguire una rotta, manovrare, selezionare un
  bersaglio, usare cannone e missili.
- Il gioco verifica l'azione richiesta prima di procedere con il passaggio
  didattico corrispondente; non si limita a spiegazioni da ascoltare.
- Istruzioni da rendere coerenti con controller rimappato e missili selezionati.
- Non spiegare tutte le manovre speciali nel tutorial: vengono introdotte come
  upgrade successivamente, con High-G molto presto.

### Incontro e combattimento

Durante il collaudo incontriamo forze nemiche. La loro presenza in questo luogo
lascia perplessi protagonista e compagni e introduce il mistero.

- Fase iniziale protetta.
- Ultimo scontro con minaccia reale al giocatore, ma difficoltà contenuta.
- I due gregari restano **invulnerabili nella prima missione**.
- La vulnerabilità dei gregari nelle missioni successive non è ancora decisa.
- Morte del giocatore: ripartenza dall'inizio della missione.

### Conclusione

Dopo lo scontro, comunicazione di rientro e conclusione della missione, senza
atterraggio manuale. Il collegamento verso Utah verrà stabilito dall'indagine
sull'incursione.

### Ancora da dettagliare

Percorso, singoli esercizi, modalità per provare le armi prima del pericolo reale,
composizione e numero definitivo degli incontri, dialoghi, regia, tempi e criteri
di superamento delle prove. Le tre ondate attuali non sono state confermate come
struttura definitiva del nuovo tutorial.

## 8. Missione 2 — Assalto alle basi in Utah

### Motivazione narrativa

L'incursione sul Garda viene ricondotta a installazioni nemiche in Utah.
Il comandante ordina di neutralizzarle. L'assalto deve lasciare emergere indizi
che porteranno alla terza missione senza spiegare immediatamente tutto sugli alieni.

### Presenza delle basi e ordini

- Le **tre basi sono tutte presenti sulla mappa dall'inizio**, a livello logico.
- La missione segue gli ordini del comandante: non è un assalto libero all'intera mappa.
- Le basi vengono segnalate e rese agganciabili in base alla fase di missione.
- Prima della designazione **non possono essere danneggiate**, neppure anticipando
  l'assalto con il cannone.
- Le difese della base si attivano insieme alla fase corrispondente.
- Evitare che il giocatore venga attaccato da una base che non può ancora colpire.
- Ordine obbligatorio **tra le basi**, libertà di scelta **tra i bersagli della base attiva**.
- Come comunicare visivamente o via radio il divieto di attacco anticipato resta
  un dettaglio da progettare; il richiamo radio è una proposta, non testo approvato.

### Obiettivi e condizioni di completamento

Una base è neutralizzata distruggendo i **bersagli strategici esplicitamente marcati**,
non ogni struttura dello scenario.

Le difese possono essere eliminate per facilitare l'assalto, ma sono obbligatorie
solo quando designate come obiettivi. Eventuali caccia superstiti non impediscono
automaticamente di completare l'obiettivo.

### Sequenza approvata

| Base | Identità e bersagli indicativi | Funzione di gameplay |
|---|---|---|
| 1 | Deposito logistico: carburante e munizioni | Introduzione agli attacchi al suolo, esplosioni spettacolari e antiaerea leggera |
| 2 | Installazione radar e difesa missilistica | Priorità tattiche: distruggere il radar disabilita i SAM collegati |
| 3 | Base aerea: hangar e centro di comando | Alternanza tra attacchi al suolo e combattimenti con intercettori |

Difese concordate: **cannoni antiaerei, SAM e caccia intercettori**, introdotti
gradualmente invece di sovrapporre subito tutte le minacce.

### Conclusione e indizio

Durante l'ultimo assalto viene intercettata una trasmissione nemica che rivela
un sito segreto sulla terza mappa e riferimenti a un carico o programma insolito.

La missione termina con una **vittoria effettiva** e l'ordine di investigare.
Niente recupero a piedi, escort o sconfitta obbligatoria.
Il contenuto esatto della trasmissione dipende dalla scoperta della missione 3.

### Ancora da dettagliare

Layout, modelli e numero delle strutture, distanze tra le basi, valori di salute,
ritmo degli intercettori, attacchi delle difese, marcatori HUD, radio, regia e tempi.
La durata va verificata giocando; non va ottenuta dilatando i trasferimenti.

## 9. Missione 3 — Scoprire il programma nemico

### Confermato

- Ambientazione sulla **terza mappa, ancora in lavorazione**.
- Obiettivo narrativo: scoprire cosa stanno realmente facendo i nemici.
- Collegamento dalla missione 2 tramite trasmissione intercettata e sito segreto.

### Proposte aperte: punto esatto da cui riprendere

**Q49 — Attività principale.** Come si indaga il sito?

Alternative discusse: ricognizione con sorvoli ravvicinati; assalto che espone
ciò che è nascosto; infiltrazione evitando di essere individuati.

Raccomandazione non ancora approvata: **ricognizione armata che evolve in combattimento**,
con punti d'interesse da osservare o scansionare e successiva risposta nemica.
Niente fallimento automatico da missione stealth solo perché si viene individuati.
Queste capacità di osservazione/scansione non sono state accertate nel codice.

**Q50 — Quanto si mostra dell'alieno.** Si vede già la medusa nella missione 3
oppure il boss viene mostrato completamente solo nella quarta?

Raccomandazione non ancora approvata: confermare chiaramente il controllo nemico
su una creatura aliena, mostrarne solo parte o sagoma e scoprire il dispiegamento
in Utah. Conservare per la quarta missione la prima apparizione completa e il primo scontro.

**Nessuna delle due domande ha ancora ricevuto risposta.**
Il finale della missione, gli obiettivi giocabili e il dettaglio della scoperta
non vanno decisi assumendo l'approvazione di queste proposte.

## 10. Missione 4 — Medusa aliena in Utah

### Confermato

- Quarta e ultima missione della demo, ambientata in **Utah**.
- Boss: **medusa aliena gigante volante**, enorme e relativamente lenta.
- Tentacoli che occupano lo spazio aereo; il giocatore deve manovrare intorno alla
  creatura e attraverso aperture per attaccare. Deve distinguersi da un dogfight
  contro un aereo con molta salute.
- Nemico controllato e impiegato dalla fazione avversaria per tutta la demo.
- I modelli sono già disponibili secondo l'utente, ma devono ancora essere importati.
  Non è stata autorizzata alcuna importazione durante questa fase di pianificazione.
- Morte: riavvio completo della missione.

### Ancora aperto

Attacchi, punti deboli, eventuali fasi, vulnerabilità, animazioni, leggibilità,
interazioni con il terreno e con le armi, presenza di altri nemici, introduzione,
esito preciso e aggancio al gioco completo.

Non è confermata una missione di protezione di città o basi: quella proposta era
parte della struttura precedente, sostituita dall'utente.
La disponibilità dei modelli non dimostra che rig, animazioni, collisioni o VFX
necessari siano già pronti.

## 11. Inventario tecnico di partenza

Ispezione statica su `main` al commit `4e7456981c40e170bb358f3b5a9a04a2df2480a6`.
Nessun test, lancio Godot o playtest eseguito nell'inventario.
Nessuna modifica al progetto effettuata dai ricercatori.

### Avvio e flusso corrente

- `project.godot`: entry point `scenes/ui/main_menu.tscn`; configurazione Godot 4.7,
  Forward+, Jolt e D3D12 su Windows.
- `scripts/ui/main_menu.gd` e `scripts/ui/game_session.gd`: menu → operazioni Garda
  → loadout → `scenes/levels/tutorial.tscn`; disponibile anche free flight.
- `GameSession` conserva selezioni tramite stato statico in memoria, non salva
  l'avanzamento della campagna tra processi.
- Scene Utah presenti (`tutorial_utah.tscn`, `freeroam_utah.tscn`), ma non esposte
  dal menu. Non sono state dichiarate pronte dopo un test runtime.

### Volo, armi e IA riutilizzabili

- `scripts/player/player_flight.gd`: volo arcade, High-G, spin dash, salute,
  danni, collisioni, effetti di danneggiamento e gestione confini.
- `scripts/aircraft/aircraft_catalog.gd`: Brown Camo, Twin Engine e F/A-26;
  prestazioni attualmente condivise.
- `scripts/weapons/missile_catalog.gd`: STDM, HSSTDM, BAHM, NCGBM e MTSM.
- `scripts/weapons/weapon_controller.gd`: cannone, due slot missili, cooldown e multi-lock.
- `scripts/combat/targeting.gd`: selezione/aggancio; `combat_hud.gd`: indicatori e radar.
- `scripts/enemies/enemy_fighter.gd` e `scripts/combat/combat_director.gd`: IA di volo,
  ruoli di combattimento e gestione della pressione sul giocatore.

Sono capacità implementate, non una valutazione positiva già dimostrata di feeling,
bilanciamento o qualità visiva.

### Tutorial e fine missione correnti

- `scripts/combat/tutorial_mission.gd`: tre incontri aerei da 2, 4 e 8 nemici,
  annunci radio e spawn collegati ai dialoghi.
- `resources/dialogues/tutorial.dialogue`: dialoghi tattici in italiano,
  personaggi generici Pilota, Wing 1 e Wing 2; non una campagna sceneggiata.
- `scenes/levels/tutorial.tscn`: `allow_player_attacks = false` nel direttore,
  `invulnerable = true` sui due gregari. Stessa protezione nel tutorial Utah.
- `scripts/combat/sortie_controller.gd`: vittoria/sconfitta, overlay risultato,
  pausa e riavvio dell'intera scena. Nessun checkpoint.
- La vittoria generica conta tutti i bersagli vivi; non distingue ancora gli
  obiettivi strategici dai caccia o dalle difese opzionali.

### Combattimento a terra: riscontro mirato

Nelle scene e negli script first-party esaminati non sono stati individuati
basi, bersagli di terra, edifici distruttibili, torrette o SAM implementati.
Le scene mappa contengono terreno, cielo/illuminazione, atmosfera e relativi controller,
non le installazioni militari richieste.

La base tecnica del targeting e del danno è però riutilizzabile:

- Targeting e missili lavorano con nodi `Node3D` del gruppo `targets` dotati di
  `is_alive()` e posizione; il danno usa `apply_damage()`.
- Segnale `destroyed` richiesto dal conteggio corrente degli obiettivi.
- L'HUD usa gruppi e metodi/etichette del bersaglio, non soltanto la classe degli aerei.
- Il cannone usa hitbox `Area3D`; per i bersagli di terra servono collisioni e
  inoltro del danno correttamente configurati. Riferimenti: `bullet.gd` e
  `scripts/combat/aircraft_hitbox.gd`.
- `missile.gd`: l'impatto sul terreno può produrre un'esplosione visiva senza
  danno ad area. Non assumere splash damage già disponibile.
- La vittoria sugli obiettivi selezionati e l'attivazione separata delle basi
  richiedono nuovo lavoro; non basta inserire le strutture nel gruppo `targets`.

Compatibilità statica non significa combattimento aria-terra già completato:
servono entità, hitbox, danni, feedback, difese, logica missione e verifica pratica.

### UI, audio e impostazioni

- Menu, anteprima aereo, loadout, HUD, pausa e opzioni già presenti.
- Numerose impostazioni grafiche e audio; persistenza tramite
  `scripts/ui/settings_manager.gd` in `user://settings.cfg` e configurazione grafica.
- Input tastiera e gamepad presenti; rimappatura UI non individuata.
- Radio testuale temporizzata non saltabile; nessun doppiaggio, briefing illustrato
  separato o sistema cinematografico di campagna individuato.
- UI prevalentemente italiana hardcoded; nessuna traduzione attiva individuata.
- VFX riutilizzabili: scarichi, postbruciatore, fumo/fuoco, esplosioni, effetti armi.

### Mappe e authoring

- `scenes/maps/garda_final.tscn` e `scenes/maps/utah_final.tscn`: mappe esistenti,
  con Terrain3D, cielo e atmosfera.
- Mappa 3 in lavorazione secondo l'utente; stato tecnico non verificato.
- Il terreno resta di competenza **World Creator**, fonte di verità per geometria,
  composizione e maschere.
- Basi, nemici ed elementi di missione sono elementi separati da aggiungere;
  non è autorizzata la modifica del terreno importato o di `wc_data/`.

### Boss e narrativa

- Nessuna implementazione della medusa o di altri boss individuata.
- Vecchie stringhe boss nell'HUD e un audio di ruggito non costituiscono un boss giocabile.
- Nei documenti esaminati non è emerso un design narrativo precedente: i documenti
  sono soprattutto tecnici/look-dev. Questo piano inizia a fissare la direzione.

### Test e pubblicazione

- Presenti diversi check headless in `tests/` per tutorial, menu, IA, armi,
  targeting, impostazioni e mappe; **non eseguiti durante questa ispezione**.
- Nessun `export_presets.cfg` individuato: export Windows ancora da configurare/verificare.
- Autoload/tooling Godot AI, scene demo degli addon e contenuti non necessari
  richiedono verifica della loro inclusione nell'export.
- Licenze addon in parte presenti; provenienza/licenza completa degli asset da verificare.
- Musiche identificate come brani di **Risk of Rain 2**: non distribuirle senza
  adeguata autorizzazione. La presenza nel repository non dimostra i diritti
  posseduti dall'utente; prima della pubblicazione servono verifica o sostituzione.
- Da verificare anche modelli aerei, SFX, font, BinbunVFX/Water, SunshineClouds2,
  terrain_snap e relativi obblighi di attribuzione/distribuzione.
- Notate informazioni sul dataset Copernicus DEM GLO-30, ma non svolto un audit legale.
- Icona predefinita Godot presente; identità della build e materiali Steam da preparare.

## 12. Lavoro emerso dal confronto — non ancora una roadmap approvata

Questo è un elenco di gap derivati dalle decisioni, non una stima, un ordine di
implementazione definitivo o un'autorizzazione a partire.

| Area | Lavoro emerso |
|---|---|
| Tutorial | Collaudo sceneggiato, esercizi verificati, istruzioni coerenti con input/loadout, minaccia reale finale |
| Missione 2 | Tre installazioni, bersagli distruttibili, AA/SAM, intercettori, attivazione per fase, radar collegato ai SAM |
| Obiettivi | Separare obiettivi obbligatori, difese opzionali e altri bersagli; vittoria coerente con gli ordini |
| Missione 3 | Completare il design prima di stabilire sistemi e contenuti necessari |
| Boss | Esaminare/importare i modelli quando autorizzato; progettare e implementare la medusa |
| Campagna | Selezione missioni, sblocco sequenziale, replay, salvataggio completamenti e sblocchi |
| Equipaggiamento | Disponibilità iniziale e sblocchi aerei/missili/manovre; tempi e regole rimandati |
| Narrativa | Cast, sceneggiatura, briefing illustrati, radio, cinematografie e doppiaggio inglese |
| Lingue | Testi italiano/inglese e gestione coerente delle traduzioni |
| Controller | Rimappatura, prompt e intero flusso utilizzabile senza tastiera/mouse |
| Mappe | Collegare Utah alle missioni, integrare mappa 3 attraverso il workflow World Creator |
| Audio/asset | Verificare diritti, sostituire contenuti non autorizzati, preparare crediti |
| Pubblicazione | Build Windows, contenuti export, distribuzione Steam, materiali e identità della demo |
| Validazione | Test tecnici, missioni complete, durata, difficoltà, leggibilità, prestazioni e playtest esterni |

Requisiti hardware, obiettivi prestazionali, criteri quantitativi di accettazione,
procedura di raccolta feedback e checklist finale Steam sono ancora da discutere.
Non è stato eseguito alcun avvio che certifichi integrazione, né un playtest che
certifichi qualità visiva o di gameplay.

## 13. Decisioni superate: non reintrodurre implicitamente

- Demo da 30–45 minuti → sostituita da circa 60–80 minuti.
- Checkpoint e ripresa interna alla missione → rifiutati; riavvio completo.
- Briefing/cinematografie saltabili → rifiutati per ora.
- Supporto pubblico sia tastiera/mouse sia controller → sostituito da solo controller rimappabile.
- Tono militare prevalentemente serio → sostituito da esagerato e sopra le righe.
- Guerra interrotta da alieni indipendenti → sostituita da nemici che usano gli alieni.
- Protagonista definito e doppiato → sostituito da protagonista silenzioso.
- Kaiju terrestre → sostituito da medusa volante.
- Nemici che perdono il controllo della medusa → rifiutato per la demo.
- Quattro missioni tutte sul Garda → rifiutato; Garda / Utah / mappa 3 / Utah.
- Missione 2 di difesa/escort → sostituita dall'assalto a basi; niente escort.
- Tutorial come esercitazione generica → sostituito dal collaudo dopo riparazione.
- Tutte le manovre insegnate nella prima missione → sostituito da apprendimento tramite upgrade.
- High-G di base e solo spin dash come upgrade → rifiutato; entrambe sono upgrade.
- Aereo a scelta e missili prestabiliti nel tutorial → sostituito da un solo aereo iniziale e missili a scelta tra quelli disponibili.
- Secondo aereo dopo M1 e terzo dopo M2 → proposta non approvata; tempistiche rimandate.
- Libertà nell'ordine delle basi → rifiutata; ordine del comandante, libertà interna alla base attiva.

## 14. Albero delle decisioni e ripresa del lavoro

```text
Demo per convincere a seguire/acquistare — confermato
├── Windows / Steam — confermato
│   └── Export, licenze, prestazioni, accettazione pubblicazione — da approfondire
├── Arcade aereo spettacolare + narrativa sopra le righe — confermato
│   ├── Fazione nostra vs nemici con alieni controllati — confermato
│   ├── Protagonista silenzioso, squadriglia d'élite — confermato
│   └── Cast, sceneggiatura, regia — da dettagliare
├── Testi IT/EN, voci EN, narrativa non saltabile per ora — confermato
├── Solo controller rimappabile — confermato
│   └── Dispositivi, prompt, disconnessione e UX — da dettagliare
├── Quattro missioni sequenziali e rigiocabili — confermato
│   ├── M1 Garda: collaudo + incontro inatteso — macrodesign confermato
│   ├── M2 Utah: tre basi ordinate + intercettazione — macrodesign confermato
│   ├── M3 mappa 3: scoperta — Q49/Q50 aperte
│   │   └── Obiettivi, finale e passaggio a M4 — dipendono dalle risposte
│   └── M4 Utah: medusa volante controllata — concept confermato
│       └── Attacchi, fasi, integrazione modelli, finale — aperti
├── Riavvio completo, salvataggio missioni sbloccate/completate — confermato
├── Un aereo iniziale, missili selezionabili, manovre come upgrade — confermato
│   └── Tempi e modalità degli sblocchi — rimandati
└── Roadmap, verifiche e conferma condivisa finale — ancora da completare
```

**Prossimo passo:** riprendere dalle Q49–Q50 della sezione 9. Non assumere che
ricognizione/scansioni, rivelazione parziale del boss o suo dispiegamento annunciato
siano già stati approvati.

I dettagli volutamente lasciati aperti non vanno trasformati in implementazione
silenziosa. Le decisioni sugli sblocchi restano parcheggiate finché l'utente non
sceglie di tornarci. Nessuna modifica a scene, codice, terreno o asset è inclusa
nell'autorizzazione a salvare e pubblicare questo documento nel repository.
