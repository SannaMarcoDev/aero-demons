# Aero Demons — Piano della demo e design delle missioni 1–4

Aggiornamento di progettazione: **16 settembre 2026**.

**Stato:** completamento proposto del mission design, costruito sulle decisioni confermate nell'intervista del 15 settembre. La richiesta di completare le quattro missioni viene sviluppata qui senza fermarsi alle precedenti domande Q49–Q50. Le nuove soluzioni sono proposte progettuali, non risposte retroattivamente attribuite all'utente e non funzionalità già implementate.

La versione precedente è conservata integralmente, senza modifiche, in [Archivio dell'intervista del 15 settembre](demo_playable_plan_2026_09_15_archive.md). Rimane la fonte delle decisioni approvate, delle alternative scartate e dell'inventario tecnico storico. Questo aggiornamento non autorizza modifiche a codice, scene, terreno o asset.

## 1. Perimetro e legenda

### 1.1 Come leggere il documento

- **Confermato:** requisito proveniente dal piano precedente.
- **Design proposto:** scelta operativa introdotta in questo completamento. Tutti i titoli di missione, nomi nuovi, personaggi, quantità, layout, sequenze dettagliate e dialoghi appartengono a questa categoria, salvo indicazione contraria.
- **Valore iniziale di prototipo:** numero da misurare e correggere giocando, non bilanciamento certificato.
- **Rimandato:** decisione lasciata deliberatamente aperta, senza introdurre dipendenze obbligatorie nelle missioni.
- **Riscontro statico:** informazione letta nei sorgenti o riportata dall'ispezione precedente; non prova di funzionamento o qualità.

### 1.2 Decisioni confermate da conservare

La demo deve convincere a seguire e acquistare il gioco completo: non è una semplice vetrina tecnica. Destinazione principale Windows su Steam; itch.io resta un'alternativa opzionale, non un requisito. Non ci sono scadenze esterne concordate. Disponibilità di tempo, collaboratori e budget restano fuori da questa progettazione, come richiesto.

L'esperienza è un combattimento aereo arcade, spettacolare, narrativo e sopra le righe. Le quattro missioni sono l'inizio della campagna definitiva: Garda, Utah, terza mappa in lavorazione, ritorno in Utah. Obiettivo indicativo: 15–20 minuti per missione, 60–80 complessivi, esclusi morti e retry. Il combattimento deve prevalere; niente trasferimenti dilatati per raggiungere il minutaggio.

Il protagonista è silenzioso e appartiene a una squadriglia d'élite di una forza militare regolare. I nemici usano una medusa aliena volante come arma e **ne mantengono il controllo per tutta la demo**. Non c'è una ribellione della creatura, un'alleanza con essa o un cambio di nemico a metà scontro.

Niente escort, comprese protezioni mascherate di città, basi, convogli o compagni. La morte comporta il riavvio dell'intera missione, anche contro il boss. Nessun checkpoint o salvataggio interno. Si salvano missioni completate e sbloccate; quelle sbloccate sono rigiocabili.

Presentazione con briefing illustrati, radio e cinematografie. Testi italiani e inglesi, doppiaggio per ora solo inglese. Briefing e sequenze narrative rimangono non saltabili, anche nei retry. Il protagonista non riceve battute doppiate.

La demo pubblica è progettata per controller rimappabile, inclusi tutti i menu. Il supporto tastiera/mouse esistente non diventa un requisito pubblico e non va rimosso automaticamente.

Si riutilizzano tre modelli di aereo e cinque missili esistenti. Un solo aereo iniziale, missili selezionabili fra quelli disponibili. Tutte le manovre speciali, High-G e spin dash incluse, sono upgrade; High-G deve arrivare molto presto, ma il momento non è stato fissato. Non sono approvati nuovi aerei, nuovi missili, valuta, acquisti ripetitivi o un calendario preciso degli sblocchi.

### 1.3 Cosa completa questa versione

Per ciascuna missione vengono definiti identità, storia, attività del giocatore, ritmo, obiettivi verificabili, incontri, basi, alleati, momenti spettacolari, finale e requisiti di implementazione. Le Q49–Q50 ricevono una soluzione proposta: ricognizione armata nella terza missione e rivelazione parziale della medusa tramite un collegamento remoto; prima apparizione fisica completa nella quarta.

La mappa 3 non viene identificata arbitrariamente con un luogo o con un file non verificato. Il suo layout qui è funzionale: deve essere adattato alla mappa reale, non ricavato da un'immagine inventata.

## 2. Arco della demo e cast proposto

### 2.1 Le quattro promesse al giocatore

| Missione | Titolo di lavoro | Identità | Domanda narrativa | Durata di riferimento |
| --- | --- | --- | --- | --- |
| 1 | Fuori garanzia | Collaudo che diventa dogfight | Perché ci sono nemici in una zona sicura? | 16 minuti |
| 2 | Tre punti da cancellare | Assalto aria-terra a tre basi | Che cosa protegge questa rete militare? | 18 minuti |
| 3 | Sotto la superficie | Ricognizione armata e sabotaggio selettivo | Che cosa stanno controllando i nemici? | 18 minuti |
| 4 | Cielo occupato | Combattimento spaziale contro un kaiju volante | Come si abbatte qualcosa di così grande? | 18 minuti |

Totale di riferimento: circa 70 minuti. Non sono quattro varianti di «elimina tutte le ondate»: ogni missione ha un verbo dominante diverso e una diversa condizione di conclusione.

### 2.2 Catena causale

L'incursione sul Garda è una missione nemica di ricognizione e raccolta di segnali, preliminare all'impiego dell'arma aliena. Nella prima missione il giocatore non lo sa: intercetta aerei con equipaggiamento insolito e traffico radio non ordinario.

L'analisi dei segnali riconduce gli intrusi alla rete logistica in Utah. Le tre basi della seconda missione sostengono davvero le operazioni nemiche: distruggerle è una vittoria concreta, non un diversivo inutile. Il collasso della rete induce il nemico a trasmettere istruzioni d'emergenza che rivelano un sito di ricerca sulla mappa 3.

Quel sito è un laboratorio di telemetria e controllo. **La medusa non è fisicamente lì:** è già stata trasferita nell'area Utah. La terza missione scopre il programma, ne danneggia il supporto e acquisisce una telemetria utilizzabile per affrontare la creatura. Il collegamento remoto evita un trasferimento del boss senza spiegazione tra M3 e M4.

Il nemico anticipa l'impiego dell'arma dopo la compromissione del laboratorio. Nella quarta missione la squadriglia ritorna in Utah e distrugge la medusa. Il programma subisce una sconfitta reale, ma non coincide con un solo esemplare: questo è l'aggancio al gioco completo.

Garda e Utah rimangono i nomi delle mappe del progetto. Il mondo narrativo e i nomi definitivi delle fazioni non vengono assimilati automaticamente a conflitti reali.

### 2.3 Personaggi e funzione in missione

Tutti i nominativi seguenti sono provvisori; non sostituiscono silenziosamente un cast già approvato.

| Ruolo | Nominativo di lavoro | Voce e funzione | Evoluzione nelle quattro missioni |
| --- | --- | --- | --- |
| Protagonista | Demon 1 | Silenzioso; risponde con il pilotaggio | Da aereo appena riparato a pilota che abbatte la medusa |
| Primo gregario | Fuse / Demon 2 | Spericolato, competitivo, battute brevi | Sdrammatizza M1–M2; smette di scherzare alla scoperta; recupera ironia dopo la vittoria |
| Secondo gregario | Vector / Demon 3 | Preciso, osservatore; traduce sensori e pericoli in indicazioni utili | Nota l'anomalia, collega gli indizi, identifica le aperture del boss |
| Comandante | Argus / Control | Diretto, operativo, autorità radio; non un aereo da proteggere | Assegna le tre basi, autorizza l'indagine, ordina l'abbattimento |
| Capotecnico | Torque | Affetto burbero per l'aereo riparato | Introduce il collaudo; breve richiamo finale alla riparazione |
| Ufficiale nemico | Custode | Sicuro del proprio sistema di controllo, non uno scienziato impazzito | Prima tracce radio; poi voce riconoscibile in M3 e ordini durante M4 |

Il programma alieno viene chiamato **PELAGO**; il sito di ricerca **N-03**; l'area di dispiegamento in Utah **CORONA**; la medusa **NEREIDE**. Sono etichette di lavoro, da sostituire insieme se cambiano. I vecchi nomi boss presenti nell'HUD non diventano canon.

### 2.4 Tono

La spettacolarità nasce dalla sproporzione fra la situazione e l'atteggiamento dei piloti. Non tutte le battute devono essere comiche: lasciare spazio al silenzio quando appare qualcosa di veramente enorme. Le informazioni tattiche vengono prima delle battute. Nessuna conversazione interrompe un avviso missilistico o nasconde un cambio di obiettivo.

## 3. Regole di missione condivise

### 3.1 Ritmo e controllo del giocatore

I tempi indicati nelle tabelle sono finestre-obiettivo per il primo completamento, non timer che bloccano la progressione. Si passa alla fase successiva quando la relativa condizione è soddisfatta. Un giocatore bravo può anticipare il ritmo: non aggiungere ondate o attese soltanto per arrivare a 15 minuti.

I trasferimenti normali devono offrire già il prossimo bersaglio, radio utile o una nuova lettura del paesaggio. Riferimento iniziale: 20–45 secondi tra due zone attive, da ricavare dalla velocità reale del velivolo. Non fissare coordinate o chilometri prima del blockout della mappa.

Le cinematografie durano pochi secondi e vengono collocate in condizioni sicure. Mai lasciare l'aereo sotto attacco mentre il giocatore non ha controllo. Al ritorno dal filmato, ripristinare una situazione leggibile e una direzione di volo sicura. La radio ordinaria mantiene il controllo e si adatta agli eventi, senza accodare minuti di spiegazioni.

### 3.2 Obiettivi e HUD

Separare sempre **obiettivi obbligatori**, **difese opzionali**, **ostili aerei** e **punti informativi**. Il testo HUD dice che cosa fare adesso e quanti elementi restano, non soltanto «elimina i nemici».

Un obiettivo completato non torna incompleto perché una radio arriva in ritardo. Le condizioni già soddisfatte vengono riconosciute entrando nella fase. I segnali di distruzione e le transizioni devono essere idempotenti: missili multipli, incendi e abbattimenti simultanei non devono contare due volte lo stesso bersaglio.

La missione non viene prolungata per distruggere caccia o torrette che non sono obiettivi. Dopo il soddisfacimento dell'ultima condizione, disattivare nuove aggressioni durante la chiusura narrativa. Nessuna morte evitabile soltanto saltando una sequenza che il progetto rende non saltabile.

### 3.3 Gregari

In M1 l'invulnerabilità dei due gregari è confermata. Per M2–M4 la **proposta** è mantenerli invulnerabili nella demo, senza barra da proteggere, per non introdurre una escort implicita. L'approvazione di questa estensione resta distinta dal requisito originale.

Fuse occupa gli intercettori e partecipa agli attacchi alle difese; Vector fornisce letture tattiche e supporto. Devono ottenere abbattimenti visibili, non essere semplici voci. Non completano le prove didattiche al posto del giocatore, non distruggono automaticamente tutti gli obiettivi strategici e non danno il colpo finale al nucleo del boss. In M4 si concentrano su caccia e appendici esterne, lasciando il nucleo al protagonista.

Non serve un nuovo menu di ordini ai gregari per questa demo: gli incarichi cambiano con le fasi. La loro presenza deve ridurre la pressione, non sostituire l'azione del giocatore.

### 3.4 Pressione e fallimento

La difficoltà cresce soprattutto combinando problemi già leggibili. Numero di nemici vivi e numero di aggressori simultanei sono parametri diversi. Una base può avere molte difese, ma non tutte devono avere una soluzione di tiro efficace sul protagonista nello stesso momento.

Morte del protagonista: fallimento e retry integrale. Nessun timer di scorta, nessuna barra di città, nessun compagno la cui perdita faccia fallire. Il rilevamento in M3 non produce game over. I confini devono consentire un rientro segnalato; eventuali penalità vanno definite e testate senza morti istantanee non annunciate.

Le regole di munizioni e danno restano coerenti tra gli incontri. Non aggiungere una ricarica illimitata in combattimento. Prima della pubblicazione va verificato che ogni loadout realmente selezionabile disponga di un margine sufficiente per gli obiettivi obbligatori.

## 4. Missione 1 — Fuori garanzia

### 4.1 Identità e storia

**Mappa:** Garda. **Stile:** collaudo guidato che diventa combattimento aereo. **Sensazione:** tranquillità, complicità con i gregari, sorpresa e prima prova reale.

L'aereo è stato appena riparato. Torque vuole verificare motore, superfici di controllo e sistemi d'arma; Fuse considera il collaudo una scusa per volare; Vector controlla la telemetria. Non si parte per una normale esercitazione militare e non ci si aspetta un attacco.

Una breve inquadratura mostra pannelli sostituiti, vernice nuova o segni della manutenzione. Il giocatore riceve il controllo già in volo, con i due gregari. Non c'è decollo manuale.

### 4.2 Spazio e basi

Usare un settore del Garda che offra acqua aperta, un riferimento di costa e una zona di cielo libera dalle pareti del terreno. Layout funzionale: rotta di collaudo → poligono aereo → anomalia radar → arena di dogfight sopra uno spazio ampio.

Una base alleata con hangar di manutenzione, pista e torre dà contesto all'apertura e al rientro. **Non è un obiettivo da difendere.** Non servono hangar esplorabili, decollo, atterraggio o una sequenza a terra. Due punti di prova aerei impiegano droni bersaglio disarmati, ottenibili riusando silhouette e logica dei velivoli con comportamento semplificato.

Non posizionare esercizi a bassa quota, strettoie obbligatorie o ostacoli che richiedano manovre ancora da sbloccare.

### 4.3 Sequenza giocabile e pacing

| Finestra indicativa | Fase | Cosa fa il giocatore | Condizione per proseguire |
| --- | --- | --- | --- |
| 0:00–0:45 | Aereo restituito al servizio | Guarda l'apertura e prende controllo in volo | Fine della breve introduzione |
| 0:45–3:30 | Collaudo di volo | Segue tre riferimenti larghi, vira, cambia quota, accelera e rallenta | Azioni pratiche riconosciute |
| 3:30–5:45 | Collaudo armi | Seleziona un drone, colpisce col cannone, cambia slot, aggancia e colpisce con un missile | Conferma di ciascuna azione richiesta |
| 5:45–7:00 | Contatti non autorizzati | Raggiunge il settore indicato e identifica la coppia nemica | Ingresso nel settore e identificazione |
| 7:00–10:00 | Prima intercettazione | Abbatte due ricognitori armati con aiuto dei gregari | Due contatti neutralizzati |
| 10:00–15:15 | Risposta nemica | Affronta quattro caccia, introdotti in due coppie | Tutti e quattro neutralizzati |
| 15:15–16:00 | Rientro | Mantiene il volo mentre viene comunicato l'esito | Chiusura radio e risultato |

La parte didattica può essere molto più rapida al replay, perché le azioni vengono riconosciute subito; non si introduce però un comando di salto delle sequenze narrative. La durata reale della missione rimane da misurare.

### 4.4 Esercizi verificabili

La rotta usa volumi ampi, non anelli minuscoli. Ogni prova ha un messaggio breve e una conferma immediata: «virata verificata», «spinta verificata», «bersaglio selezionato». Le soglie vanno riferite al modello di volo, non a un tasto fisso.

Il cannone richiede almeno un impatto sul drone dedicato, non un abbattimento perfetto. La prova missile richiede selezione, acquisizione e impatto sul secondo bersaglio. Il cambio slot viene verificato anche se due slot contengono lo stesso tipo di missile. Il bersaglio didattico resta valido fino alla conferma dell'azione e non può essere rubato dai gregari.

I prompt leggono la rimappatura attiva. Il testo non presume che sia stato scelto STDM: un missile incendiario o multi-lock richiede descrizioni e conferme coerenti. Non si blocca la missione aspettando una funzione che il loadout selezionato non possiede.

Per le prove si propone una dotazione separata da quella operativa: esaurire le munizioni durante l'apprendimento non impedisce di proseguire. All'inizio dello scontro reale viene attivata la dotazione operativa del loadout. Questa è una nuova regola da implementare esplicitamente, non una capacità già verificata.

### 4.5 Nemici e difficoltà

**Budget iniziale:** due droni disarmati, due ricognitori nemici e quattro caccia; sei ostili combattenti totali. È una nuova proposta, non la conferma delle vecchie ondate 2/4/8 del prototipo.

I ricognitori riusano il modello dei caccia con un profilo meno aggressivo. Combattono contro i gregari, offrendo bersagli reali senza introdurre immediatamente pressione sul protagonista. Non fuggono in modo irreversibile e non generano un timer di inseguimento.

Nell'ultimo incontro la minaccia diventa reale: i caccia possono attaccare il giocatore. Riferimento iniziale del direttore: un aggressore diretto alla volta e una prima minaccia missilistica ben annunciata; gli altri impegnano i gregari o si riposizionano. Le coppie entrano da direzioni visibili, non compaiono a distanza di collisione.

Non aggiungere antiaerea, SAM, assi con salute sproporzionata o attacchi alieni. Questa missione insegna a volare e combattere, non tutti i sistemi della demo.

### 4.6 Regia e radio principali

Battute di lavoro in italiano, da localizzare e adattare per il doppiaggio inglese.

| Trigger | Voce | Battuta o contenuto |
| --- | --- | --- |
| Apertura | Torque | «Ho sostituito il motore. Il resto ho preferito non chiedermelo.» |
| Primo input verificato | Vector | Conferma tecnica breve; niente spiegazione ripetuta |
| Collaudo armi | Fuse | «Finalmente un test in cui si può rompere qualcosa.» |
| Anomalia radar | Vector | «Due contatti. Nessun identificativo alleato. Questa rotta non è in programma.» |
| Identificazione | Argus | «Non sono nel nostro piano di volo. Intercettateli.» |
| Ultima coppia in arrivo | Fuse | «Collaudo annullato. Adesso è una recensione sul campo.» |
| Primo missile contro il giocatore | Vector | Avviso tattico prioritario e indicazione di manovrare |
| Vittoria | Vector | «Portavano apparati di rilevamento. Non erano venuti soltanto a cercare noi.» |
| Chiusura | Argus | «Rientrate. Voglio sapere chi li ha mandati fin qui.» |

### 4.7 Esito, ricompensa e test

Vittoria quando le prove obbligatorie sono concluse e i sei ostili degli incontri sono neutralizzati. Il rientro è un ordine radio e una chiusura, non un atterraggio manuale. Si sblocca M2.

L'indagine su telemetria e segnali avviene nel debriefing: niente recupero di rottami a piedi. Gli upgrade non vengono assegnati automaticamente da questo documento; High-G resta candidato a una consegna molto precoce, con momento ancora da decidere.

Verificare soprattutto: prove completabili con ogni loadout disponibile; nessun gregario che rubi la prova; nessun blocco per munizioni; ultimo scontro realmente pericoloso; assenza di attese dopo azioni già eseguite; leggibilità del primo attacco missilistico.

## 5. Missione 2 — Tre punti da cancellare

### 5.1 Identità e storia

**Mappa:** Utah. **Stile:** assalto offensivo aria-terra con crescente pressione aerea. **Sensazione:** potenza, libertà tattica dentro un ordine operativo preciso, sospetto crescente.

L'analisi dell'incursione collega gli aerei nemici a tre installazioni. Argus assegna una sequenza obbligatoria: logistica, radar, base aerea. Non chiede di proteggere una forza a terra o un convoglio. Il giocatore vede gli effetti del proprio assalto e capisce che la rete custodisce qualcosa di più importante della semplice copertura regionale.

### 5.2 Layout e autorizzazione delle basi

Le tre basi esistono dall'inizio, anche quando non sono obiettivi attivi. Disporle lungo una progressione leggibile, con landmark diversi e linee di avvicinamento alternative. Le distanze devono permettere transizioni brevi; non distribuire tre piccoli obiettivi agli estremi della mappa da 250 km soltanto perché il terreno è grande.

Stati di ogni base: **non autorizzata → attiva → neutralizzata**. Prima della designazione non può essere danneggiata da cannone, missili, incendi o eventuali esplosioni ad area. Le difese inattive non attaccano. All'attivazione, autorizzare prima il danno e poi avviare il preavviso delle difese.

Comunicazione proposta: installazioni future in grigio; reticolo con dicitura «NON AUTORIZZATO» se il giocatore tenta di colpirle; nessun hit marker o falso feedback di danno. Un solo richiamo radio, con cooldown, spiega che l'ordine operativo non è ancora arrivato. Non inventare uno scudo alieno per giustificare il vincolo.

Dentro la base attiva tutti i bersagli designati sono colpibili in qualsiasi ordine. Non rendere il bunker invulnerabile finché non è stato distrutto il radar: quello sarebbe un secondo ordine obbligatorio non previsto.

### 5.3 Le tre basi

| Base | Identità e silhouette | Obiettivi strategici obbligatori | Difese opzionali e funzione |
| --- | --- | --- | --- |
| 1 — Fornace | Deposito aperto, serbatoi, piazzali e magazzini bassi | Due impianti carburante e un deposito munizioni | Due cannoni AA; insegnano passaggi di attacco e disimpegno |
| 2 — Ago | Radar riconoscibile, piazzole missili e bunker | Un radar principale e un centro di tiro | Tre SAM collegate al radar e due cannoni AA; il radar distrutto spegne tutte e tre le SAM |
| 3 — Incudine | Grande hangar, hangar secondario, pista e torre comando | Due hangar e un centro di comando | Due cannoni AA e caccia; alternanza fra priorità aeree e terrestri |

Totale proposto: **otto bersagli strategici, sei cannoni AA e tre SAM**. Edifici secondari, veicoli fermi, illuminazione e recinzioni rendono riconoscibile ogni installazione, ma non entrano nel contatore di vittoria.

Il grande hangar della base aerea è un landmark, non una casetta appena più grande dell'aereo. Dimensioni e orientamento vanno ricavati dal modello e dal blockout reali. L'attacco alla base deve funzionare senza volare dentro l'hangar.

Le esplosioni di Fornace sono spettacolari. Non assumere che il danno ad area esista già: una reazione a catena può inizialmente essere una sequenza VFX locale, senza alterare i contatori o colpire una base non autorizzata.

### 5.4 Sequenza e pacing

| Finestra indicativa | Fase | Cosa fa il giocatore | Condizione per proseguire |
| --- | --- | --- | --- |
| 0:00–0:45 | Ordine d'attacco | Legge la sequenza e vede Fornace | Introduzione conclusa |
| 0:45–4:15 | Fornace | Colpisce tre obiettivi; sceglie se eliminare prima l'AA | Tre strategici distrutti |
| 4:15–5:00 | Cambio bersaglio | Vola verso Ago mentre riceve nuove istruzioni | Ago attivata e raggiunta |
| 5:00–9:00 | Ago | Gestisce SAM, radar e bunker; affronta una coppia di intercettori | Radar e centro di tiro distrutti |
| 9:00–9:45 | Ultimo ordine | Si riallinea sulla base aerea | Incudine attivata |
| 9:45–17:15 | Incudine | Alterna dogfight e passaggi su hangar/comando | Tre strategici distrutti |
| 17:15–18:00 | Trasmissione intercettata | Mantiene il volo e ascolta il nuovo indizio | Chiusura radio e risultato |

### 5.5 Incontri, tattica e alleati

A Fornace non aggiungere subito caccia: il giocatore deve capire come individuare un bersaglio a terra, attaccare e uscire dalla traiettoria dell'AA. I colpi traccianti e i lampi delle postazioni mostrano da dove proviene il fuoco.

Ad Ago introdurre una prima acquisizione SAM annunciata prima della salva. Vector evidenzia il rapporto radar–lanciatori. Distruggere il radar interrompe nuove acquisizioni dei tre sistemi collegati; eventuali missili già in volo seguono una regola esplicita e coerente, senza essere semplicemente cancellati senza feedback. Proposta: continuano il volo ma perdono la guida aggiornata, con avviso di radar neutralizzato.

Una coppia di intercettori arriva dopo la prima azione significativa ad Ago. L'evento viene cancellato se la fase è già conclusa, evitando una nuova ondata obbligatoria durante il trasferimento. Non è necessario abbatterli per neutralizzare la base.

A Incudine il budget è di quattro caccia ordinari più una coppia condizionale. Due sono già in pattuglia, due arrivano da una direzione leggibile. La coppia aggiuntiva viene generata solo se l'hangar designato come punto di lancio è ancora intatto al trigger previsto. Distruggerlo presto evita quei rinforzi: è una conseguenza tattica comprensibile, non uno spawn infinito.

Il totale nominale della missione è quindi fino a **sei–otto caccia** se tutti gli eventi previsti hanno luogo; può essere inferiore completando rapidamente le basi e cancellando eventi non ancora partiti. Riferimento di pressione: massimo quattro caccia nel combattimento locale e non più di due aggressori diretti; il coordinamento con le SAM richiede un budget condiviso di minacce, da tarare.

Fuse prende i caccia quando il protagonista attacca il suolo. Vector richiama il radar e le difese pericolose. Non sono richiesti nuovi bombardieri alleati, truppe terrestri o unità da scortare.

### 5.6 Radio e indizio

| Trigger | Voce | Battuta o contenuto |
| --- | --- | --- |
| Briefing | Argus | «Prima gli togliamo il carburante. Poi gli occhi. Poi gli aerei.» |
| Prima esplosione a Fornace | Fuse | «Il carburante è ufficialmente fuori servizio.» |
| Prima acquisizione SAM | Vector | «I lanciatori dipendono dal radar. Spegni quello e smettono di seguirci.» |
| Radar distrutto | Vector | Conferma delle SAM collegate disabilitate |
| Incudine attiva | Argus | «Hangar e comando. I caccia sono un problema, non l'obiettivo.» |
| Hangar di lancio distrutto in anticipo | Fuse | «Due decolli cancellati. Nessun rimborso.» |
| Ultimo strategico in distruzione | Radio nemica | «PELAGO: copertura compromessa. Trasferite l'archivio N-03. CORONA mantiene la finestra Utah.» |
| Debriefing | Argus | «Non stavano coprendo soltanto delle basi. Ora abbiamo un sito da controllare.» |

Il messaggio nomina un programma, un archivio e una destinazione. Non spiega già la medusa o il suo controllo. L'informazione viene registrata automaticamente dal sistema di comunicazione: il giocatore non può perderla distruggendo il centro di comando troppo rapidamente.

### 5.7 Vittoria e continuità

Una base viene neutralizzata quando i suoi strategici sono distrutti. I superstiti non bloccano la progressione. Dopo l'ultima base la missione chiude l'offensiva con successo e sblocca M3: niente sconfitta obbligatoria o ordine improvviso di proteggere qualcuno.

La distruzione delle tre installazioni viene richiamata visivamente in M4 tramite la variante scenica di quella missione. Non serve salvare ogni prop o ogni torretta opzionale tra le sortite.

Verificare: danno anticipato impossibile da ogni sorgente; difese inattive innocue; radar che spegne soltanto le SAM collegate; rinforzi finiti e cancellabili; nessun obbligo di eliminare ostili non strategici; vittoria riconosciuta anche con distruzioni simultanee.

## 6. Missione 3 — Sotto la superficie

### 6.1 Identità e decisioni proposte

**Mappa:** terza mappa del progetto, nome e percorso ancora da verificare. **Stile:** ricognizione armata che evolve in sfondamento selettivo e sabotaggio. **Sensazione:** curiosità, inquietudine, conferma della minaccia, iniziativa offensiva.

Non è una missione stealth con fallimento al rilevamento. Non è un'altra lista di tre basi da spianare. La squadriglia deve capire il funzionamento di un unico complesso, aprirne un settore protetto e acquisire una prova. Il combattimento accompagna la scoperta, non la sostituisce.

La rivelazione proposta è inequivocabile: una creatura aliena viene controllata e impiegata deliberatamente dai nemici. Del corpo si vedono solo parti o una sagoma attraverso immagini trasmesse da Utah. La prima apparizione fisica completa rimane a M4.

### 6.2 Complesso N-03 e layout

Un solo sito con tre settori funzionali vicini, non tre basi indipendenti. Adattare edifici e percorsi al terreno reale senza richiedere un bioma specifico.

| Settore | Aspetto e ruolo | Interazione principale |
| --- | --- | --- |
| Perimetro | Antenna di servizio, contenitori tecnici e poche difese | Prima acquisizione di telemetria |
| Laboratorio | Corpo industriale con due regolatori esterni e una camera schermata | Distruggere due regolatori per esporre il punto informativo centrale |
| Comunicazioni | Ripetitore d'allarme separato e piazzola tecnica | Distruggere il collegamento locale che richiede rinforzi |

Il laboratorio non ospita fisicamente la medusa. Contiene strumentazione, registrazioni e un feed operativo proveniente da CORONA. Il volume centrale non deve diventare un tunnel obbligatorio: il punto informativo esposto deve essere leggibile da un passaggio esterno.

Budget di terra proposto: due regolatori e un ripetitore obbligatori; due AA; un radar locale con una SAM opzionale. Distruggere quel radar riusa l'apprendimento di M2 e disabilita soltanto la SAM di N-03.

### 6.3 Ricognizione concreta

Due acquisizioni obbligatorie: antenna periferica e camera di telemetria esposta. Il giocatore seleziona il punto informativo, lo mantiene nel settore frontale e passa a distanza utile. L'acquisizione è automatica: niente nuovo tasto da memorizzare o menu da aprire.

Valori iniziali da provare: entro circa 2 km, cono frontale sufficientemente largo e 3 secondi cumulativi di visibilità utile. Il progresso non si azzera quando si deve evitare un missile; si mette in pausa e riprende al passaggio successivo. La linea di vista deve essere reale: non si scansiona attraverso il terreno.

Un punto informativo ha un'icona distinta dai bersagli da distruggere e mostra chiaramente portata e avanzamento. Se un suo supporto distruttibile viene abbattuto prima della scansione, l'informazione resta acquisibile dal registratore nel relitto. Nessuna distruzione accidentale può eliminare l'unico oggetto necessario a completare la missione.

Questa funzione di acquisizione è **nuovo lavoro**, non un sistema già accertato nel progetto. Riusa selezione e visibilità dove possibile, senza essere spacciata per una meccanica gratuita.

### 6.4 Sequenza e pacing

| Finestra indicativa | Fase | Cosa fa il giocatore | Condizione per proseguire |
| --- | --- | --- | --- |
| 0:00–0:45 | Ricognizione autorizzata | Riceve le coordinate N-03 | Introduzione conclusa |
| 0:45–3:15 | Primo passaggio | Acquisisce la telemetria periferica e legge il sito | Prima acquisizione completa |
| 3:15–7:00 | Il sito reagisce | Combatte una pattuglia e apre il laboratorio | Due regolatori distrutti |
| 7:00–10:30 | Accesso ai dati | Si riallinea, gestisce le difese e acquisisce la camera esposta | Seconda acquisizione completa |
| 10:30–11:15 | Rivelazione | Riceve il feed e l'identificazione del programma | Breve sequenza sicura conclusa |
| 11:15–16:45 | Sabotaggio ed uscita | Distrugge il ripetitore se ancora attivo; gestisce gli intercettori | Dati acquisiti e ripetitore distrutto |
| 16:45–18:00 | Corridoio libero | Raggiunge la zona d'uscita mentre viene preparata la nuova operazione | Ingresso nell'uscita e chiusura |

I periodi comprendono combattimento, lettura e riposizionamento; non sono richiesti minuti di scansione. Se il giocatore è rapido, il sito non aggiunge bersagli per riempire il tempo.

### 6.5 Allarme e nemici

Una pattuglia di tre caccia risponde alla prima acquisizione o al primo attacco, secondo l'evento che avviene prima. Il rilevamento cambia radio e aggressività, non lo stato di successo. Nessun cono radar provoca fallimento automatico.

Dopo la scoperta vengono inviati due intercettori; un'altra coppia è condizionale alla sopravvivenza del ripetitore d'allarme. Budget massimo iniziale: **sette caccia**, cinque se il ripetitore viene distrutto prima della richiesta aggiuntiva. Non ci sono ondate infinite.

Il ripetitore è colpibile fin dall'inizio di M3. Distruggerlo in anticipo viene ricordato; non va ricreato quando compare il relativo testo obiettivo. Se i rinforzi sono già arrivati, non scompaiono: semplicemente non ne vengono chiamati altri.

Gli intercettori possono essere aggirati o affidati ai gregari. Non è necessario ripulire tutto lo spazio aereo per uscire, purché siano completati acquisizioni e sabotaggi obbligatori. L'uscita non è una fuga da un nemico invulnerabile e non introduce una barra di collegamento da proteggere.

### 6.6 Che cosa si scopre, esattamente

La prima acquisizione mostra che i segnali registrati sul Garda appartengono allo stesso protocollo del sito. La ricognizione nemica era parte della preparazione di un'operazione più grande.

Aprendo il laboratorio si vede un sistema progettato per trasmettere comandi, non soltanto per studiare un reperto. Il feed mostra un tentacolo che si muove e poi si arresta in sincronia con un comando; una sagoma enorme rimane dietro una struttura di contenimento. L'interfaccia indica **CORONA — UTAH / CONTROLLO STABILE**. La voce del Custode conferma l'impiego militare.

La telemetria acquisita identifica quattro dissipatori esterni dell'imbracatura energetica e il ritmo di apertura del nucleo. Non fornisce una soluzione che distrugge il boss con un pulsante: dà al giocatore un piano di attacco comprensibile.

Il ripetitore sabotato gestisce l'allarme locale. **Non è il collegamento primario che controlla la medusa.** La sua distruzione non libera la creatura e non contraddice il requisito del controllo nemico.

### 6.7 Radio e regia

| Trigger | Voce | Battuta o contenuto |
| --- | --- | --- |
| Avvicinamento | Argus | «Prima capiamo cosa c'è. Poi decidiamo quanto deve restarne.» |
| Prima acquisizione | Vector | «È lo stesso protocollo del Garda. Stavano preparando qualcosa.» |
| Primo regolatore distrutto | Fuse | «Ventilazione ridotta. Privacy, anche.» |
| Camera esposta | Vector | «Non è un archivio normale. È un collegamento operativo.» |
| Feed remoto | Custode | «Risposta motoria entro i parametri. Mantenete il controllo e preparate il dispiegamento.» |
| Reazione | Fuse | Una breve pausa, poi: «Dimmi che quella non era la parte piccola.» |
| Identificazione | Vector | «La creatura è in Utah. Questi sono i suoi comandi.» |
| Dati acquisiti | Argus | «Abbiamo la prova e il punto debole. Distruggete il ripetitore e uscite.» |
| Finale | Argus | «Ritorniamo in Utah. Questa volta sappiamo cosa cercare.» |

La rivelazione usa un inserto illustrato o un feed breve, con riduzione temporanea della pressione e senza togliere controllo in una situazione letale. Non richiede una seconda scena giocabile della medusa sulla mappa 3.

### 6.8 Vittoria e test

Condizioni: due acquisizioni complete, due regolatori distrutti, ripetitore distrutto e raggiungimento dell'uscita. Le difese e i caccia superstiti non bloccano. Il laboratorio è realmente compromesso e i dati vengono riportati: vittoria offensiva e informativa, non semplice fuga.

Verificare: acquisizione possibile con normale pilotaggio; progresso cumulativo; distruzione anticipata dei supporti senza softlock; ripetitore distrutto presto riconosciuto; nessun fallimento da rilevamento; uscita funzionante con caccia vivi; coerenza del feed Utah con il luogo fisico del laboratorio.

## 7. Missione 4 — Cielo occupato

### 7.1 Identità e apertura

**Mappa:** Utah. **Stile:** boss fight tridimensionale contro una medusa gigante lenta, con tentacoli che ridisegnano lo spazio di volo. **Sensazione:** meraviglia e paura iniziali, lettura del corpo, padronanza, abbattimento spettacolare.

Non è un caccia con molta salute. La creatura si muove lentamente, ma le sue appendici, i settori di attacco e le aperture del corpo obbligano a cambiare traiettoria. Il giocatore cerca un accesso al punto debole, attacca e si disimpegna.

Il briefing usa ciò che è stato scoperto in M3. La squadriglia parte già in volo verso CORONA. Si riconoscono in lontananza le tre basi colpite, con gli otto obiettivi strategici in variante distrutta. CORONA è un'installazione distinta, non una base di M2 ricomparsa intatta.

L'area di lancio serve a dare scala: piattaforme, torri e hangar sembrano piccoli sotto la medusa. Le difese fisse di CORONA sono già state soppresse dall'attacco preparatorio alleato comunicato nel briefing; non diventano una quarta sequenza obbligatoria di bombardamento. Non esiste una base alleata da difendere.

### 7.2 Scala, arena e forma

La medusa ha una campana riconoscibile, tentacoli lunghi e leggibili, quattro dissipatori esterni aggiunti dal programma nemico e un nucleo ventrale. Il controllo primario è distinto dai dissipatori: distruggere questi ultimi compromette raffreddamento e protezione, non la capacità del nemico di impartire ordini.

Ipotesi di blockout: campana larga nell'ordine di 700–1000 metri e ingombro verticale complessivo nell'ordine di 1–1,5 km. Sono riferimenti da verificare con modelli, velocità, camera, quote e terreno effettivi, non dimensioni già approvate o garantite dagli asset.

L'arena deve offrire giro esterno sicuro, spazio sopra la campana e corridoi larghi fra i tentacoli. La rotta più spettacolare attraversa l'involucro delle appendici; una rotta più larga resta praticabile con il volo normale. Non obbligare a possedere High-G o spin dash.

La creatura segue una rotta lenta interna all'area valida. Altezza e movimento non devono far attraversare i punti deboli al terreno. Le collisioni dei tentacoli devono corrispondere alle forme visibili, senza un'unica sfera invisibile attorno all'intero boss.

### 7.3 Sequenza e pacing

| Finestra indicativa | Fase | Cosa fa il giocatore | Condizione per proseguire |
| --- | --- | --- | --- |
| 0:00–0:45 | Piano di attacco | Riceve il riepilogo dei dati di M3 | Introduzione conclusa |
| 0:45–3:00 | Primo contatto | Supera una coppia di caccia e vede l'intera creatura | Ingresso nell'arena e rivelazione |
| 3:00–7:30 | Fase 1 — Aprire la corazza | Distrugge quattro dissipatori in ordine libero | Quattro dissipatori distrutti |
| 7:30–13:00 | Fase 2 — Sotto la campana | Attacca il nucleo nelle aperture e manovra fra i tentacoli | Nucleo portato alla soglia della fase finale |
| 13:00–17:00 | Fase 3 — Sovraccarico comandato | Gestisce combinazioni più intense e termina l'attacco al nucleo | Salute del nucleo a zero |
| 17:00–18:00 | Abbattimento e chiusura | Assiste all'esito e riceve l'aggancio al seguito | Risultato e completamento demo |

Non imporre cicli minimi di vulnerabilità. Un buon passaggio o un loadout efficace possono accelerare la fase. La difficoltà deve venire dal posizionamento e dalla lettura, non dall'allungare la barra della vita per rispettare la tabella.

### 7.4 Fase 1 — Aprire la corazza

I quattro dissipatori si trovano su lati diversi della campana. Tutti sono attaccabili e l'ordine è libero. HUD: «DISSIPATORI 0/4», con selezione pulita e silhouette leggibile. Il resto della campana è corazzato: non mostra falsi indicatori di danno utile.

Il giocatore impara ad orbitare, cambiare quota e fare passaggi tangenziali senza trovarsi continuamente dentro il corpo. Ogni dissipatore distrutto perde emissione luminosa e riduce l'attività del settore corrispondente, rendendo percepibile l'effetto del proprio attacco.

Sono presenti due caccia iniziali e può arrivare una sola coppia aggiuntiva durante questa fase: **quattro caccia massimi nell'intera missione**. Fuse e Vector li impegnano. Il loro abbattimento non è un prerequisito per colpire il boss. Gli ingressi non avvengono alle spalle del giocatore durante un passaggio già occupato da un attacco principale.

### 7.5 Fase 2 — Sotto la campana

Dopo il quarto dissipatore, il rivestimento ventrale si apre periodicamente e rivela il nucleo. Il nemico è ancora al comando. La nuova attività dei tentacoli è una riconfigurazione ordinata dal Custode, non una perdita di controllo.

Il giocatore osserva una carica, evita l'attacco principale e usa la finestra successiva per raggiungere una linea di tiro sul nucleo. La campana e le appendici bloccano realmente la linea di vista; non basta spammare missili attraverso il corpo. Non introdurre un limite di distanza invisibile solo per impedire i tiri lunghi: la necessità di avvicinarsi deve derivare dalla geometria e dalle aperture.

Riferimento iniziale: finestre di esposizione di circa 12–18 secondi, da verificare con velocità e portate effettive. L'apertura viene annunciata prima che sia utile, così il giocatore può preparare il passaggio.

Nessun nuovo rinforzo aereo dalla fase 2. I gregari prendono gli eventuali superstiti lontano dal passaggio ventrale. Il direttore non combina pressione aerea ravvicinata con la finestra didattica del primo accesso al nucleo.

### 7.6 Attacchi leggibili

I tempi seguenti sono valori iniziali di prototipo. Vanno misurati dalla prospettiva del giocatore, non dalla camera cinematografica.

| Attacco | Segnale prima del danno | Risposta possibile | Limite di equità |
| --- | --- | --- | --- |
| Spazzata dei tentacoli | Contrazione e illuminazione del gruppo interessato per circa 3 secondi | Cambiare settore, quota o passare dal lato lasciato libero | Non chiude tutte le uscite; hitbox aderente alla parte visibile |
| Ventaglio energetico | Impulsi progressivi sulla campana per circa 2,5 secondi | Spostarsi lateralmente attraverso intervalli riconoscibili | Niente proiettili che cambiano improvvisamente bersaglio o nascono sul giocatore |
| Raggio ventrale | Nucleo in carica e direzione indicata per circa 3 secondi | Uscire dal corridoio del raggio e preparare il passaggio successivo | Direzione fissata prima dello sparo; non insegue istantaneamente ogni virata |

Il raggio termina con una finestra favorevole al contrattacco. La spazzata è un problema di spazio, il ventaglio di posizionamento, il raggio di anticipazione: tre domande diverse, non tre effetti visivi sullo stesso danno inevitabile.

Una collisione continuata con lo stesso gruppo di tentacoli non applica decine di colpi in pochi frame. Serve un intervallo di protezione dal danno ripetuto della stessa sorgente, distinto da un'invulnerabilità generale. Evitare attacchi caricati completamente fuori campo senza avviso direzionale.

### 7.7 Fase 3 — Sovraccarico comandato

Soglia proposta: nucleo al 40% della salute. Il Custode ordina una sovralimentazione: emissività e ritmo aumentano, la creatura risponde ancora ai comandi. Non usare una battuta come «non risponde più» o una animazione che implichi fuga dal controllo.

La fase ricombina gli attacchi già visti. Massimo due minacce compatibili alla volta; vietata la combinazione che blocca simultaneamente ogni via di fuga con raggio e tentacoli. Non introdurre nell'ultimo minuto un attacco inevitabile mai insegnato.

Il nucleo rimane accessibile secondo cicli leggibili e tende a offrire aperture più generose mentre il sistema si surriscalda. Niente conto alla rovescia per salvare una città e niente enrage che uccide automaticamente. La tensione viene dall'aggressività e dal danneggiamento visibile.

La soglia di fase non deve cancellare in silenzio una salva già a segno: gestire il danno eccedente e il cambio di stato in modo deterministico. Non resettare la salute del nucleo tra una fase e l'altra.

### 7.8 Armi, punti deboli e budget danno

Tutti i missili e il cannone devono poter contribuire quando il bersaglio è validamente esposto. Nessun missile specifico o upgrade è una chiave obbligatoria. MTSM può distribuire attacchi su componenti disponibili; non deve agganciare parti chiuse o contare ogni hitbox come un boss separato.

Un'ustione applicata validamente a un componente continua a danneggiare quel componente secondo una regola esplicita, anche se una copertura si richiude; la chiusura blocca nuove applicazioni, non cancella retroattivamente un effetto già guadagnato. Componenti distrutti non trasferiscono automaticamente tutte le loro ustioni al nucleo.

Riferimento puramente iniziale: 240 punti per ciascuno dei quattro dissipatori e 1800 per il nucleo, 2760 complessivi. Nel catalogo letto STDM infligge 60 danni diretti: il totale equivale a 46 impatti ideali, prima di errori, overkill e altre armi. Questo serve a stimare l'ordine di grandezza del budget, **non a dimostrare la durata della boss fight**. Danni, portate, cooldown, munizioni e resistenza devono essere verificati insieme.

Una sola applicazione di danno per impatto e componente: un missile non moltiplica il danno attraversando più collider dello stesso dissipatore. Le armi ad area richiedono una regola esplicita per non colpire simultaneamente tutto il boss attraverso la corazza.

### 7.9 Radio, vittoria e aggancio

| Trigger | Voce | Battuta o contenuto |
| --- | --- | --- |
| Avvicinamento | Argus | «Non dobbiamo contenerla. Dobbiamo abbatterla.» |
| Rivelazione completa | Fuse | Breve silenzio, poi: «Quello non entra nel rapporto.» |
| Prima lettura | Vector | «Quattro dissipatori sulla campana. Il nucleo è sotto. Usiamo i dati del laboratorio.» |
| Primo dissipatore distrutto | Vector | Conferma del settore indebolito |
| Fase 2 | Custode | «Riconfigurazione ventrale. Teneteli sotto la campana.» |
| Prima finestra sul nucleo | Vector | «Si apre dopo il raggio. Prepara il passaggio.» |
| Fase 3 | Custode | «Sovralimentazione autorizzata. Continuate l'attacco.» |
| Ultimo colpo | Fuse | «Giù. Adesso resta giù.» |
| Vittoria confermata | Argus | «Contatto distrutto. Aero Demons, obiettivo completato.» |
| Distensione | Torque, nel debriefing | «Avevo chiesto soltanto un collaudo.» |

Il colpo finale produce una rottura leggibile del nucleo, il cedimento della campana e la caduta controllata dalla regia sopra l'area militare sgombra di CORONA. Il giocatore non deve superare a sorpresa una fuga a tempo dopo aver vinto. Non si introduce un danno da esplosione inevitabile mentre parte il filmato.

La medusa è realmente distrutta. I nemici non rivelano che era una proiezione o che l'intera vittoria era inutile. Dopo la conferma, una breve schermata di intelligence mostra altri identificativi del programma PELAGO ancora operativi. Nessun nuovo boss giocabile è necessario per questo aggancio.

### 7.10 Test specifici

Verificare la lotta con il velivolo meno manovrabile e senza High-G/spin dash. Controllare corridoi, camera, linee di tiro, danno ripetuto dei tentacoli, visibilità dei segnali, attacchi fuori campo, bersagli chiusi esclusi dal multi-lock e finale con danni nel tempo attivi.

Il riavvio resta completo: proprio per questo nessuna fase deve insegnare una regola soltanto uccidendo il giocatore senza preavviso. La boss fight va misurata giocando; un caricamento riuscito della scena non prova che funzioni bene.

## 8. Inventario di contenuti proposto

### 8.1 Aerei e difese

Riutilizzare modelli e armi già presenti. Le differenze fra ricognitore, caccia e intercettore possono iniziare da profili IA, ruolo e presentazione, senza commissionare nuovi velivoli. Verificare però che i comportamenti risultino effettivamente diversi e leggibili.

| Famiglia | Introduzione | Funzione |
| --- | --- | --- |
| Drone bersaglio disarmato | M1 | Apprendimento senza pressione |
| Ricognitore armato | M1 | Primo nemico e indizio narrativo |
| Caccia ordinario | M1 | Dogfight di riferimento |
| Intercettore | M2 | Disturba l'attacco al suolo e il riposizionamento |
| Cannone AA | M2 | Pericolo localizzato durante i passaggi bassi |
| SAM con radar collegato | M2 | Priorità tattica e gestione degli avvisi |
| Medusa con componenti | M4 | Navigazione fra pericoli e attacchi a finestre |

### 8.2 Kit ambientale minimo

Un kit riutilizzabile di serbatoi, deposito munizioni, radar, bunker, AA, SAM, hangar grande, hangar secondario e centro di comando copre M2 e parte di M3. M3 aggiunge due regolatori, una camera di telemetria e un ripetitore. M4 richiede piattaforme di lancio e una versione distrutta dei principali obiettivi di M2, senza una nuova mappa.

Per la medusa servono verifica dei modelli, rig/animazioni o movimento procedurale controllato, collider separati, quattro dissipatori, nucleo, VFX di attacco e distruzione. La disponibilità del modello non certifica nessuno di questi elementi.

Il terreno resta di competenza World Creator. Non scolpire o riscrivere `wc_data/` per far entrare un layout; adattare prima la composizione degli elementi separati, oppure registrare una richiesta di modifica del terreno da eseguire nel workflow corretto.

### 8.3 Salute iniziale dei bersagli terrestri

Solo riferimenti di prototipo: AA 60; SAM 120; impianto carburante 120; deposito munizioni, radar e centro di tiro 180; hangar 240; comando 300. Con STDM a 60 danni diretti risultano rispettivamente 1, 2, 2, 3, 4 e 5 impatti ideali, ma armamento, cannonate, overkill, incendi e difficoltà di avvicinamento cambiano il risultato.

Gli otto strategici di M2 totalizzano inizialmente 1560 punti. Non aumentare automaticamente queste resistenze per riempire minuti: prima verificare lettura dei bersagli, ritmo dei passaggi, pressione delle difese e piacere della distruzione.

## 9. Progressione senza dipendenze nascoste

Resta confermato il salvataggio di completamenti e sblocchi missione. Restano rimandati calendario e regole degli sblocchi di aerei, missili e upgrade, differenze prestazionali fra velivoli, condivisione degli upgrade, eventuale valuta e persistenza di questi sistemi.

Le quattro missioni sono progettate senza richiedere una nuova arma o manovra per essere completate. Il carico didattico si distribuisce così: fondamentali in M1; bersagli a terra e radar in M2; acquisizione di informazioni in M3; geometria del boss in M4.

L'eventuale consegna precoce di High-G può avere un richiamo breve all'inizio di una missione successiva, ma non viene incorporata come prerequisito di un corridoio o di una schivata. Spin dash non sostituisce la leggibilità dei pericoli. Nessun upgrade viene dichiarato assegnato a fine M1 o M2 senza una decisione specifica.

## 10. Traduzione del design in sistemi

Questa sezione identifica lavoro necessario; non è un'autorizzazione all'implementazione né una roadmap stimata e approvata.

### 10.1 Stato tecnico e limiti delle fonti

L'inventario storico nell'archivio è riferito al commit `4e7456981c40e170bb358f3b5a9a04a2df2480a6`. Il documento originale è stato pubblicato al commit `f952481e32ef3e33781302af212870033ff5211e`, base di questo aggiornamento. Nessun test Godot o playtest è stato eseguito per redigere questo mission design.

Sono stati consultati il piano, `AGENTS.md`, `README.md`, `scripts/weapons/missile_catalog.gd` e l'inizio di `scripts/weapons/weapon_controller.gd`. Le altre osservazioni implementative sotto riportate derivano dall'inventario storico e non costituiscono una nuova ispezione completa dei sorgenti.

### 10.2 Capacità riutilizzabili e gap

Il piano precedente identifica volo arcade, cannone, due slot missili, targeting, IA aerea, direttore di combattimento, HUD, radio testuale, menu/loadout, retry e mappe Garda/Utah. Questo non significa che la campagna qui descritta sia già presente.

| Area | Lavoro richiesto dal completamento |
| --- | --- |
| M1 | Prove verificabili, bersagli didattici, dotazione prove, passaggio da protezione a pericolo reale |
| M2 | Entità di terra, danni e feedback, AA/SAM, collegamenti radar, otto obiettivi e tre basi a stati |
| M3 | Acquisizione informativa, visibilità, progresso cumulativo, fallback sui relitti, rivelazione remota e uscita |
| M4 | Modello/rig, componenti, attacchi, collisioni, vulnerabilità, direzione della pressione e finale |
| Obiettivi | Separazione da bersagli generici; transizioni deterministiche e completamenti anticipati |
| Campagna | Menu missioni sequenziali, replay e persistenza tra processi |
| Narrativa | Briefing illustrati, regia, localizzazione IT/EN, doppiaggio EN e priorità delle comunicazioni |
| Controller | Rimappatura e flusso interamente navigabile senza tastiera/mouse |

L'inventario storico non aveva individuato bersagli terrestri, SAM, boss, scansioni o un salvataggio campagna completo. Il targeting basato su `Node3D`, gruppi, `is_alive()`, `apply_damage()` e segnali può essere riutilizzato, ma non sostituisce implementazione e test delle nuove entità. L'impatto sul terreno di un missile non garantisce danno ad area.

### 10.3 Contratti di stato proposti

Ogni missione deve possedere uno stato esplicito e una condizione di successo separata dal conteggio di tutti gli ostili vivi. Gli identificativi seguenti sono convenzioni di design, non API già esistenti.

| Missione | Stati principali | Condizione finale |
| --- | --- | --- |
| M1 | intro → flight_checks → weapon_checks → recon_pair → hostile_response → outro | prove completate e sei ostili previsti neutralizzati |
| M2 | intro → base_1 → base_2 → base_3 → outro | otto strategici distrutti nelle basi autorizzate |
| M3 | intro → perimeter_data → expose_lab → core_data → sabotage_exit → outro | due acquisizioni, due regolatori, ripetitore e uscita |
| M4 | intro → reveal → dissipators → core → overload → outro | quattro dissipatori e nucleo distrutti |

Le transizioni non devono dipendere esclusivamente dalla fine di una battuta. Per ogni evento prevedere che il giocatore agisca più rapidamente della radio. Un retry annulla dialoghi, timer, salve pianificate e riferimenti della missione precedente prima di ricostruire lo stato iniziale.

### 10.4 Ordine di prototipazione suggerito

Prima rendere affidabili stati/obiettivi e una singola entità terrestre. Poi verificare il rapporto radar–SAM e la sequenza di M2 in un blockout. Completare M1 con esercizi reali e M3 con acquisizioni robuste. Per M4 provare inizialmente una campana semplice, pochi tentacoli e un solo attacco, misurando navigabilità prima di aumentare VFX e complessità.

Solo dopo validare ogni missione dall'inizio alla fine con durata, retry e loadout reali. Integrare regia e doppiaggio senza congelare troppo presto finestre tattiche ancora da correggere. Nessuna stima di risorse o calendario viene attribuita a questo ordine suggerito.

## 11. Piano di verifica e criteri di accettazione

### 11.1 Prove funzionali

Tutte le missioni devono essere avviabili, completabili, perse e riavviate da controller. Verificare rimappatura dei prompt, pausa, disconnessione del controller, cambio loadout, ritorno al menu e riapertura della sessione. Il salvataggio deve conservare soltanto ciò che è stato deciso, senza introdurre checkpoint impliciti.

Provare distruzioni simultanee, effetti nel tempo, missili ancora in volo durante una transizione, bersagli rimossi dalla scena, rientro dopo allontanamento e conclusione con nemici opzionali vivi. I bersagli futuri di M2 restano immuni anche al danno non proveniente direttamente dal giocatore.

I test headless possono verificare logica e integrazione. Le qualità di volo, leggibilità, spettacolarità, prestazioni e difficoltà richiedono una prova giocata e osservazione visiva. Seguire `AGENTS.md` quando si passa all'implementazione; per questo aggiornamento di soli documenti non si dichiara eseguito il ciclo runtime.

### 11.2 Misure di playtest

Registrare durata totale e per fase, tempo senza azioni significative, danni ricevuti per sorgente, consumo munizioni, tentativi di attaccare basi non autorizzate, scansioni interrotte, numero di passaggi sul nucleo e causa di ogni morte. Separare primo completamento e replay.

Obiettivi iniziali: primo completamento normalmente nell'intervallo 15–20 minuti per missione; trasferimenti usuali brevi; nessuna attesa obbligatoria per «far passare il tempo»; ogni giocatore deve poter descrivere la causa della propria morte e l'azione correttiva. Non convertire questi obiettivi in risultati già ottenuti.

Per le munizioni testare tutti i loadout effettivamente disponibili nella singola missione, non soltanto il più efficace. Calcolare danno richiesto, margine per gli errori e contributo realistico del cannone. Verificare separatamente incendi, multi-lock e componenti del boss.

### 11.3 Rischi da non nascondere

Missioni lunghe, riavvio completo e narrativa non saltabile possono aumentare la frustrazione: è un rischio già registrato, non una ragione per cambiare silenziosamente le regole. La mitigazione proposta è migliorare chiarezza, sicurezza delle sequenze e durata delle parti passive.

La scansione può trasformarsi in una pausa noiosa: richiede acquisizione breve e cumulativa, in movimento. Le basi sequenziali possono apparire arbitrarie: servono designazione chiara e assenza di attacchi da installazioni invulnerabili. Il boss può diventare una spugna di danni o una massa illeggibile: partire da geometria e attacchi semplici prima degli effetti.

L'invulnerabilità proposta dei gregari nelle missioni successive deve essere valutata come scelta di esperienza. Nomi e cast devono mantenere coerenza, evitando di moltiplicare voci o ruoli senza una funzione.

## 12. Pubblicazione e decisioni ancora aperte

Il completamento del mission design non chiude automaticamente gli altri temi del piano. Restano da definire o verificare requisiti hardware, obiettivi prestazionali, tipi di controller garantiti, prompt, rimappatura completa, disconnessione, regole e salvataggio degli upgrade, differenze degli aerei, calendario degli sblocchi, collocazione fisica sulla mappa 3, cast definitivo e registrazione delle voci.

Rimangono inoltre le attività di pubblicazione già registrate: export Windows, contenuti inclusi nella build, verifica delle dipendenze/tooling, licenze e provenienza degli asset, crediti, identità della build e materiali Steam. L'archivio segnala musica attribuita a Risk of Rain 2 e diritti da verificare: il completamento di questa documentazione non costituisce una verifica delle autorizzazioni né un audit legale.

Non vengono reintrodotti: checkpoint, salto della narrativa, escort, quattro mappe Garda, medusa indipendente dal nemico, protagonista parlante, tutte le manovre nel tutorial, High-G di base o libertà nell'ordine delle tre basi.

Le nuove proposte da valutare sono chiaramente individuate: cast e nominativi; dettagli e quantità degli incontri; estensione dell'invulnerabilità dei gregari; acquisizioni di M3; rivelazione remota; dissipatori/nucleo e attacchi di M4. Non occorre attendere nuove risposte per leggere un arco completo: questa versione offre già una soluzione coerente dall'apertura del collaudo alla vittoria sulla medusa.

## 13. Fonti interne e conservazione dello storico

- [Piano/intervista originale, integralmente conservato](demo_playable_plan_2026_09_15_archive.md): decisioni, rinvii, alternative scartate, inventario tecnico e Q49–Q50.
- [Istruzioni del progetto](../AGENTS.md): ciclo di sviluppo, verifiche e vincoli sul terreno.
- [README](../README.md): descrizione del prototipo; non va confuso con questa campagna proposta.
- [Catalogo missili](../scripts/weapons/missile_catalog.gd): tipi e valori letti per i riferimenti iniziali di danno.
- [Controller armi](../scripts/weapons/weapon_controller.gd): dotazione, cannone e due slot nell'implementazione letta.

L'archivio conserva esattamente il blob `ba7b8d7e58149ac3b9fed7de7f0e88482f5b7e52`. Le aggiunte narrative e ludiche di questo documento sono lavoro di progettazione, non informazioni trovate nei sorgenti e non canon già approvato.
