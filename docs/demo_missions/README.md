# Aero Demons — Design delle prime quattro missioni

**Revisione:** 16 settembre 2026. **Stato:** proposta di completamento progettuale richiesta dall'utente; non implementazione e non approvazione retroattiva delle scelte precedentemente aperte.

Questo dossier completa il [piano della demo](../demo-playable-plan.md) con attività giocabili, storia, ritmo, incontri, installazioni, alleati, regia e criteri di verifica. I vincoli confermati nel piano restano validi. Le soluzioni nuove, inclusi titoli, numeri e battute, sono proposte concrete da valutare come un insieme. Le Q49–Q50 ricevono qui una soluzione di design, non vengono falsamente registrate come risposte dell'utente.

## Lettura e identità delle missioni

| Missione | Documento | Identità | Durata nominale di progetto |
|---|---|---|---|
| 1 — Ritorno in servizio | [Collaudo sul Garda](mission_01_garda.md) | Familiarità, sorpresa, primo combattimento vero | 16 min 30 s |
| 2 — Terra bruciata | [Assalto in Utah](mission_02_utah.md) | Aggressione, scelta delle priorità, alternanza aria-terra | 17 min 30 s |
| 3 — Dietro il segnale | [Scoperta sulla mappa 3](mission_03_discovery.md) | Ricognizione armata, resistenza crescente, rivelazione | 17 min |
| 4 — Il cielo ha tentacoli | [Medusa in Utah](mission_04_medusa.md) | Spettacolo, lettura dello spazio, attacchi al boss | 18 min 30 s |

**Totale nominale: 69 min 30 s.** Sono obiettivi per il primo completamento riuscito, non durate misurate né attese da imporre. Ogni cronologia parte dalla conferma di avvio e include briefing, introduzione e chiusura; esclude menu/loadout, caricamenti e tentativi falliti. L'intervallo confermato resta 15–20 minuti per missione. Un giocatore esperto può finire prima: non si aggiungono attese, salute artificiale o ondate infinite per impedirlo.

La progressione non è «quattro volte elimina tutti»: **impara a pilotare → scegli cosa distruggere → capisci cosa stai attaccando → usa tutto contro una creatura enorme**.

## 1. Vincoli che questo dossier non cambia

Garda / Utah / mappa 3 / Utah; tre mappe, quattro missioni sequenziali rigiocabili. Nessuna escort, nessun mezzo alleato da tenere in vita, nessuna città con barra di salute. Il protagonista rimane silenzioso. La squadriglia appartiene a una forza militare regolare ma ha un comportamento spericolato e sopra le righe.

La medusa è impiegata e controllata dal nemico fino alla propria distruzione. Non si libera, non diventa alleata e non attacca casualmente il proprio esercito. La missione 2 è una vittoria reale. La missione 4 risolve la minaccia locale e apre la campagna successiva.

Morte del protagonista: riavvio dell'intera missione, anche durante il boss. Nessun checkpoint o salvataggio interno. Briefing e cinematografie restano non saltabili anche al retry. Si salvano completamenti e sblocchi delle missioni tra sessioni. Intero flusso utilizzabile con controller rimappabile; testi italiani e inglesi, doppiaggio inglese.

Un solo aereo iniziale, missili selezionabili fra quelli disponibili. Nessun nuovo modello di aereo o tipo di missile. High-G e spin dash restano upgrade; il primo deve arrivare molto presto, ma questo dossier **non decide** calendario, economia, equipaggiamento o persistenza degli upgrade. Le missioni devono essere completabili con il volo fondamentale e ogni loadout legalmente selezionabile. Gli eventuali suggerimenti sulle manovre compaiono solo quando l'upgrade è effettivamente disponibile.

Nessuna modifica a codice, scene, modelli, terreno o dati World Creator è contenuta in questa proposta. Posizioni e descrizioni spaziali sono requisiti di composizione, non coordinate già verificate sulle mappe.

## 2. Arco narrativo e continuità

**M1 — L'incursione non è casuale.** Durante il collaudo di un aereo riparato, una pattuglia nemica attraversa una zona che dovrebbe essere sicura. Il nemico sta rilevando tempi di risposta e copertura radar, non tentando di conquistare il Garda con pochi caccia. Le registrazioni alleate permettono di risalire alla sua rete logistica in Utah.

**M2 — La logistica nasconde altro.** Si distruggono davvero tre basi della rete. Le comunicazioni dell'ultima installazione rivelano che una parte delle risorse serviva a un programma di calibrazione e a un sito remoto sulla mappa 3. Non si vede ancora un alieno e non si spiega tutto via briefing.

**M3 — Non stanno costruendo un'arma: la stanno comandando.** Nel sito remoto si acquisiscono dati di alimentazione, accoppiamento biologico e comandi. Una registrazione parziale mostra una massa tentacolare rispondere a ordini umani. Il sito è una struttura di ricerca e calibrazione a distanza: la creatura è **già in Utah**, in un'area diversa dalle tre basi distrutte. Non serve farla viaggiare istantaneamente fra le mappe. I dati acquisiti identificano sia il dispiegamento sia vulnerabilità fisiche sfruttabili.

**M4 — Il programma funziona, ma l'arma può essere abbattuta.** La creatura appare per intero e obbedisce all'operatore nemico. Distruggerne organi offensivi e nucleo non significa interrompere il controllo e renderla selvaggia. La squadriglia elimina quella medusa; altre designazioni nel registro provano che non era l'intero programma.

L'incursione M1 serviva a preparare un futuro attacco. Le basi M2 fornivano logistica ordinaria e materiale per il programma. Il laboratorio M3 spiega il sistema. L'arma M4 è la conseguenza concreta. Ogni missione risponde a una domanda e ne apre una più grande.

## 3. Cast funzionale e alleati

Non si fissano nomi propri o fazioni definitive. Queste etichette consentono di scrivere e implementare le scene senza fingere che il cast sia già canonico.

| Ruolo | Voce e funzione narrativa | Funzione in gioco |
|---|---|---|
| Protagonista | Silenzioso; la personalità passa dalle azioni e dalle reazioni altrui | Decide traiettoria, priorità e finestre d'attacco |
| Gregario 1 | Veterano spaccone, battute brevi, coraggio autentico quando la situazione cambia | Ingaggia minacce laterali, segnala direzione dei rinforzi, mostra una traiettoria sicura quando utile |
| Gregario 2 | Tecnico e sarcastico, interpreta anomalie e vulnerabilità senza monologhi | Conferma scansioni, marca punti rilevanti, spiega cause ed effetti |
| Comando | Asciutto e operativo, in contrasto con la squadriglia | Assegna obiettivi, autorizza le basi, certifica esiti e ordina il rientro |
| Capotecnico | Presente soprattutto nel collaudo, orgoglioso delle riparazioni e irritato dall'uso che ne facciamo | Trasforma il tutorial in un controllo tecnico concreto |
| Operatore nemico | Professionale, inquietantemente tranquillo; considera la medusa un sistema d'arma | Conferma il controllo attraverso ordini seguiti da attacchi visibili |

M1 mantiene i due gregari invulnerabili come confermato. **Proposta per M2–M4:** mantenerli presenti e invulnerabili nella demo, senza obiettivi di protezione. Questa estensione è una scelta nuova, non una decisione già presa. Se in seguito si preferisse renderli vulnerabili, la loro perdita non deve bloccare la missione né eliminare informazioni indispensabili: Comando sostituisce le relative battute e i trigger non dipendono da `wing_alive()`.

Gli alleati devono risultare utili, non onnipotenti. Possono abbattere difese e caccia opzionali. Non completano gli esercizi del tutorial al posto del giocatore, non consumano i bersagli investigativi e non possono saltare le fasi del boss. L'abbattimento alleato di un ostile obbligatorio conta dove non è richiesto esplicitamente un gesto didattico del protagonista. Nessuna IA alleata riceve una missione da scortare.

## 4. Regole comuni di incontri, obiettivi e ritmo

### Obiettivi leggibili

Tre categorie: **TGT obbligatorio**, **minaccia opzionale**, **elemento investigativo**. Sagoma, icona e testo distinguono le categorie senza affidarsi soltanto al colore. Una quarta condizione, «non autorizzato», identifica gli impianti futuri di M2: niente aggancio e niente danno, ma le loro difese sono anch'esse inattive.

La vittoria dipende dai requisiti della missione, non dal numero globale di nodi `targets` vivi. Un caccia in fuga, una decorazione o una torretta opzionale non devono produrre un blocco. Nessun conteggio nascosto o ordine di eliminazione non comunicato.

### Pressione controllata

Il numero totale di nemici, il massimo contemporaneo e il numero di attaccanti diretti sono parametri diversi. Un gruppo di quattro aerei non autorizza quattro attacchi missilistici simultanei. Le schede propongono un budget iniziale; non certificano il comportamento corrente del `CombatDirector`.

Gli ingressi arrivano da bordi e direzioni plausibili, non materializzandosi davanti alla camera. Dopo l'ultimo aereo di un gruppo si procede subito: nessun timer riempitivo. Nessun rinforzo infinito. La difficoltà nasce dall'incrocio leggibile di compiti, non dall'aumento indiscriminato della salute.

I collegamenti fra spazi consecutivi puntano a circa 20–40 secondi di volo utile, spesso coperti da una comunicazione. La verifica deve usare velocità, virate, portate e terreno reali. Non si trasferiscono automaticamente questi secondi in coordinate e non si utilizza l'intera dimensione geografica della mappa come percorso obbligatorio.

### Radio e cinematografie

Un messaggio operativo alla volta. Priorità: pericolo immediato, nuovo obiettivo, indizio indispensabile, caratterizzazione. Le battute non essenziali possono essere interrotte dal sistema; ciò non introduce un pulsante per saltare la narrativa. Le informazioni decisive restano anche nell'HUD o nel riepilogo.

Le brevi scene che tolgono il controllo sospendono coerentemente danni, fisica pericolosa e proiettili; il rientro in gioco ripristina una traiettoria sicura e non consegna il velivolo a un impatto. Questa è una funzionalità richiesta, non già verificata. Mai una telecamera esterna mentre l'aereo controllabile continua a subire danni fuori campo.

Le battute bilingui delle schede sono **campioni di tono e cue di regia**, non una localizzazione completa né copioni di doppiaggio definitivi. I prompt mostrano l'azione associata al controller rimappato, non pulsanti scritti a mano nelle registrazioni audio.

## 5. Armi, resistenze e prove di compatibilità

Il [catalogo missili](../../scripts/weapons/missile_catalog.gd) letto durante questa revisione contiene STDM, HSSTDM, BAHM, NCGBM e MTSM. STDM infligge 60 danni diretti, HSSTDM 30, BAHM 120; NCGBM associa 5 danni diretti a 75 nel tempo; MTSM usa sub-missili e multi-lock. Questi dati sono un riferimento statico, non una prova del danno effettivo contro nuove entità.

Le salute suggerite nelle schede sono valori iniziali per un prototipo e non modificano il catalogo. Nessuna missione richiede splash damage, penetrazione delle superfici, nuove contromisure, nuovi comandi al gregario o capacità di scansione già esistenti. Dove servono sistemi nuovi, sono indicati.

Per gli edifici e il boss, verificare esplicitamente impatti, danno nel tempo, multi-lock, vita dei sub-bersagli e distruzione. I danni di un nodo distrutto non devono migrare a un altro; una finestra che si chiude non deve produrre numeri ingannevoli. Nessuna immunità segreta a un missile legalmente equipaggiabile. Il cannone resta una risorsa utilizzabile, ma non deve essere necessario esaurire tutti i missili per scoprire un loadout impossibile.

## 6. Dipendenze e stato tecnico

La fonte dell'inventario generale resta la sezione 11 del [piano](../demo-playable-plan.md), esplicitamente basata su un'ispezione statica precedente. In questa revisione sono stati letti anche [README](../../README.md), [istruzioni di progetto](../../AGENTS.md) e catalogo missili. Non sono stati eseguiti Godot, test runtime o playtest; non si attribuisce a una funzionalità lo stato «pronta» perché descritta qui.

| Area | Da riutilizzare o verificare | Lavoro richiesto dal design |
|---|---|---|
| Missioni | Flusso menu/loadout, radio, esiti e retry esistenti | Stati obiettivo espliciti, condizioni locali, cancellazione corretta degli eventi al retry |
| Volo e combattimento | Volo, armi, targeting e IA | Tutorial a condizioni, budget per incontro e prova di ogni loadout |
| Terra | Interfacce di danno/targeting | Edifici, AA, SAM, radar collegati, autorizzazioni e feedback di distruzione |
| Scoperta | Nessun sistema di scansione dato per esistente | Volumi investigativi, progressione mantenuta, prove narrative e jamming locale |
| Boss | Modello dichiarato disponibile dall'utente, non ancora validato | Import quando autorizzato, rig, collisioni, sub-target, animazioni, VFX e tre fasi |
| Presentazione | UI e radio testuale di partenza | Briefing illustrati, cinematografie sicure, voci EN, testi IT/EN, prompt rimappabili |
| Campagna | Stato delle selezioni in memoria | Sblocco e salvataggio delle quattro missioni; nessun checkpoint |

La mappa 3 non è identificata per percorso: la scheda specifica funzioni degli spazi senza inventare una geografia già approvata. Qualsiasi necessità di cambiare geometria o maschere del terreno resta un'attività da fare in World Creator, non una licenza a scolpire in Godot.

## 7. Criteri di revisione e accettazione

Per ciascuna missione misurare separatamente tempo totale, combattimento, trasferimenti, radio obbligatoria, tentativi, causa di morte, consumo missili e tempo senza un obiettivo comprensibile. Non dichiarare rispettati i 15–20 minuti sulla sola base delle tabelle.

Una prima sessione di verifica deve coprire un giocatore inesperto con tutorial, un giocatore che conosce già il volo e ogni combinazione di equipaggiamento effettivamente sbloccabile. Le verifiche determinanti sono: completamento senza upgrade speciali obbligatori; nessuna escort implicita; assenza di bersagli inaccessibili che bloccano lo stato; riavvio che ripristina correttamente basi, scansioni e boss; leggibilità al controller; nessun nemico letale durante una scena non controllabile.

I dettagli quantitativi vanno rivisti attraverso queste prove. Calendario degli sblocchi, nomi definitivi, cast, geometria della mappa 3 e vulnerabilità dei gregari M2–M4 restano decisioni di progetto riconoscibili, non lacune nascoste. Nessuna stima di budget, personale o calendario produttivo viene introdotta.
