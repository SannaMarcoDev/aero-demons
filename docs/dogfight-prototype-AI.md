Per questo test farei **un’arena di combattimento, non ancora una missione**: giocatore, due gregari e almeno quattro nemici. Niente obiettivi a terra, rinforzi scriptati o simulazione complessa dei sensori.

Il comportamento da ottenere è questo:

> **Il giocatore trova qualcuno da inseguire, deve occasionalmente difendersi e riceve un aiuto concreto dai gregari. Non passa tutto il tempo a cercare un bersaglio o a evitare missili.**

Userei **un coordinatore dello scontro e un unico cervello di pilotaggio condiviso da tutti gli aerei AI**. Alleati e nemici si distinguono per gli incarichi ricevuti, non per due sistemi completamente diversi.

I valori temporali che propongo sono impostazioni iniziali da provare, non numeri definitivi.

# 1. La struttura del prototipo

```text
CombatArena
│
├── CombatDirector
│   ├── Assegna ruoli e bersagli
│   ├── Limita gli attacchi contro il giocatore
│   └── Gestisce alternanza tra pressione e respiro
│
├── Player
│
├── Wingman_1
├── Wingman_2
│
├── Enemy_1
├── Enemy_2
├── Enemy_3
└── Enemy_4...
```

Ogni aereo AI contiene:

```text
AircraftAI
│
├── Assignment          → Qual è il mio compito e contro chi?
├── TacticalState       → Che cosa sto facendo adesso?
├── ManeuverController  → Quale traiettoria devo seguire?
├── FlightController    → Quali comandi di volo devo applicare?
├── WeaponController    → Posso effettivamente sparare?
└── SafetyController    → Sto per schiantarmi?
```

Per ora **non aggiungerei coordinatori separati per ogni squadra, alberi di comportamento complessi o decine di manovre**. Il `CombatDirector` può gestire direttamente questi pochi aerei.

La distinzione fondamentale è:

**Ruolo:** «Devo mettere pressione al giocatore».

**Stato:** «Sto preparando una passata».

**Arma:** «Non posso ancora lanciare perché la geometria non è valida».

Sono tre decisioni diverse.

---

# 2. Come distribuirei inizialmente i quattro nemici

Non manderei tutti e quattro dietro al giocatore.

| Nemico       | Ruolo iniziale                           | Effetto cercato                                                                                       |
| ------------ | ---------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| **Nemico 1** | **Pressione sul giocatore**              | Cerca una vera occasione per attaccarlo.                                                              |
| **Nemico 2** | **Avversario disponibile per il duello** | Rimane coinvolto in una geometria raggiungibile dal giocatore, senza fuggire continuamente.           |
| **Nemico 3** | **Combattimento contro il gregario 1**   | Produce uno scontro reale e impegna parte della squadra.                                              |
| **Nemico 4** | **Combattimento contro il gregario 2**   | Produce un secondo scontro e impedisce ai gregari di concentrarsi sempre sul bersaglio del giocatore. |

Questi sono **incarichi dinamici**, non identità permanenti.

## Il nemico che offre il duello non è un bersaglio immobile

Questo ruolo è importante per il divertimento.

Il nemico non deve regalare l’abbattimento, ma deve evitare di trasformare ogni inseguimento in una fuga interminabile.

Gli farei adottare traiettorie che permettono al giocatore di avvicinarsi e leggere la manovra: virate riconoscibili, passaggi laterali, tentativi di inversione del vantaggio e brevi momenti di stabilizzazione.

**Si difende, ma non evade perfettamente e senza interruzioni.**

Quando il giocatore sta già inseguendo un nemico, normalmente assegnerei questa funzione proprio a quell’aereo. Non sposterei continuamente l’“avversario disponibile” su qualcun altro, spezzando il duello in corso.

La selezione del bersaglio può aiutare il direttore a capire l’interesse del giocatore, ma **non deve provocare una schivata automatica del nemico**.

## I ruoli non cambiano ogni secondo

Manterrei un incarico per almeno **6–10 secondi**, salvo distruzione, emergenza o perdita evidente della sua utilità.

In particolare, un duello che sta funzionando non va interrotto soltanto perché è scaduto un timer.

---

# 3. Gli stati dei nemici: sette operativi, più distrutto

Questa sarebbe la macchina a stati iniziale.

| Stato             | Quando entra                                                                    | Che cosa fa                                                                   | Quando esce                                                              |
| ----------------- | ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **REPOSITION**    | Non ha una buona posizione per svolgere il proprio ruolo.                       | Cerca una zona utile e una traiettoria praticabile.                           | Può preparare un attacco oppure viene minacciato.                        |
| **SETUP_ATTACK**  | Ha un bersaglio e può costruire un attacco.                                     | Intercetta, corregge distanza, angolo e velocità relativa.                    | Ottiene una soluzione, perde l’opportunità o deve difendersi.            |
| **ATTACK**        | Ha una buona soluzione e l’autorizzazione necessaria.                           | Mantiene brevemente la posizione offensiva; le armi sparano quando possono.   | La passata termina, perde la geometria o emerge una minaccia.            |
| **EXTEND**        | È troppo vicino, ha terminato la passata o sta insistendo inutilmente.          | Crea separazione lungo una direzione scelta.                                  | Ha spazio sufficiente per rientrare.                                     |
| **DEFEND**        | Un avversario gli sta costruendo una minaccia concreta, soprattutto dalla coda. | Esegue una manovra difensiva coerente, non una sequenza casuale di rotazioni. | Ha completato la manovra, ridotto la minaccia o deve evitare un missile. |
| **EVADE_MISSILE** | Ha rilevato un missile effettivamente pericoloso.                               | Prova a evitarlo con una manovra compatibile con le proprie prestazioni.      | Il pericolo termina oppure serve una nuova valutazione.                  |
| **RECOVER**       | Esce da una manovra impegnativa o deve recuperare velocità e controllo.         | Stabilizza il volo e prepara la prossima azione.                              | È pronto a riprendere l’incarico.                                        |
| **DESTROYED**     | È stato abbattuto.                                                              | Interrompe decisioni, armi e incarichi.                                       | Stato terminale dell’AI.                                                 |

## REPOSITION: tornare utili, non vagare

È lo stato di base.

Il punto da raggiungere dipende dal ruolo:

* Il nemico offensivo cerca una posizione da cui preparare un ingresso sul giocatore.
* L’avversario del duello cerca una geometria che mantenga lo scontro raggiungibile.
* Il nemico impegnato contro un gregario si riposiziona rispetto a quel gregario.

**Non sceglierei punti casuali sulla mappa.**

Il punto di riposizionamento deve avere un motivo. Inoltre, non deve cambiare radicalmente a ogni aggiornamento: altrimenti il pilota rincorre una destinazione instabile.

## SETUP_ATTACK: costruire l’occasione

Qui il nemico cerca di arrivare a una situazione da cui possa attaccare.

Non punta sempre la posizione attuale del bersaglio. Può anticiparne il movimento oppure ridurre l’aggressività dell’inseguimento quando rischia di sorpassarlo.

Questo stato deve avere un controllo del progresso:

> «Sto migliorando angolo, distanza o possibilità di tiro?»

Se per **6–8 secondi** non migliora nulla, abbandona quel tentativo e si riposiziona o crea separazione.

È una delle regole principali contro i duelli circolari infiniti.

## ATTACK: una finestra offensiva, non fuoco permanente

Per il primo test darei al nemico una finestra offensiva relativamente breve, indicativamente **2–4 secondi**.

Durante questa finestra può cercare una raffica o un lancio valido. Non deve necessariamente riuscirci.

Il lancio di un missile **non obbliga da solo** a interrompere l’attacco: può ancora esistere una buona posizione. L’uscita dipende dalla geometria, dalla durata della passata e dalle minacce.

L’obiettivo è evitare sia il nemico che spara e scappa immediatamente, sia quello che rimane incollato alla coda per un minuto.

## EXTEND: interrompere una situazione ormai improduttiva

Il nemico sceglie una direzione d’uscita e la mantiene abbastanza da creare spazio.

Non deve continuare a correggerla per puntare nuovamente il giocatore: altrimenti questo stato diventa un altro inseguimento.

La separazione necessaria dipende dal suo modello di volo. Deve essere sufficiente a preparare una nuova manovra, ma non così grande da trasformarsi in una fuga attraverso tutta la mappa.

## DEFEND: contrastare il giocatore senza negargli sempre il tiro

Questo stato entra quando esiste una minaccia plausibile: un inseguitore vicino e ben orientato, colpi in arrivo o una posizione chiaramente sfavorevole.

Il nemico sceglie **una manovra**, la esegue e poi rivaluta.

Per i nemici normali, proverei una difesa impegnata di **1–2 secondi**, seguita da un breve recupero.

Non farei questo:

```text
Il giocatore sta per allinearsi
→ nuova evasione perfetta
→ il giocatore sta per riallinearsi
→ altra evasione perfetta
→ ripeti per sempre
```

Farei invece:

```text
Il giocatore costruisce un vantaggio
→ il nemico tenta una difesa
→ il giocatore può seguirla o anticiparla
→ il nemico deve ricomporsi
→ esiste una finestra sfruttabile
```

La finestra non garantisce un colpo: rende possibile conquistarlo.

## EVADE_MISSILE: pericoloso, ma non infallibile

Il nemico reagisce con un ritardo e una qualità di manovra configurabili.

Non entra in questo stato per ogni missile esistente sulla mappa, ma per quelli valutati come minacce.

Una volta scelta l’evasione, evita di cambiarne continuamente il verso. E non ottiene invulnerabilità: se la manovra non basta, viene colpito.

## RECOVER: il giocatore deve poter leggere un’occasione

Questo stato è essenziale.

Dopo una manovra impegnativa, l’aereo smette temporaneamente di esigere il massimo da ogni asse, recupera velocità quando necessario e prepara la prossima azione.

Proverei **2–3 secondi** di recupero ordinario, modulati dalle condizioni effettive.

Non deve essere necessariamente un tratto perfettamente rettilineo. Deve però essere **meno imprevedibile e meno aggressivo** della difesa precedente.

Durante il recupero non rientra in `DEFEND` ogni istante soltanto perché l’inseguitore è ancora presente. Un nuovo missile pericoloso o il rischio di schiantarsi rimangono interruzioni valide.

---

# 4. Le sequenze che devono emergere

Non voglio che ogni aereo ripeta un’animazione tattica prestabilita. Voglio però che il comportamento abbia una struttura riconoscibile.

## Attacco ordinario

```text
REPOSITION
	↓
SETUP_ATTACK
	↓
ATTACK
	↓
EXTEND
	↓
REPOSITION
```

Se la preparazione fallisce:

```text
SETUP_ATTACK → REPOSITION oppure EXTEND
```

## Nemico inseguito dal giocatore

```text
Stato corrente
	↓
DEFEND
	↓
RECOVER
	↓
REPOSITION oppure SETUP_ATTACK
```

Il contrattacco è possibile soltanto se la difesa ha prodotto davvero una geometria favorevole.

## Missile in arrivo

```text
Stato corrente
	↓
EVADE_MISSILE
	↓
RECOVER
	↓
Rivalutazione dell'incarico
```

**Non riprenderei automaticamente la vecchia manovra:** nel frattempo bersaglio e situazione potrebbero essere cambiati.

La sicurezza contro terreno e collisioni interviene sopra queste sequenze, correggendo la manovra finale. Un solo componente applica poi i comandi al modello di volo.

---

# 5. Il CombatDirector: il componente che protegge il ritmo

Il direttore non pilota gli aerei. Decide **quanti possono impegnare il giocatore e quando autorizzare nuovi attacchi**.

Per il prototipo gli darei due modalità.

## NORMAL

Distribuisce i ruoli e permette gli attacchi entro i limiti.

Partirei così:

| Parametro                                                                         |                Valore iniziale |
| --------------------------------------------------------------------------------- | -----------------------------: |
| Nemici autorizzati a eseguire contemporaneamente un attacco diretto sul giocatore |                          **1** |
| Missili nemici contemporaneamente in volo contro il giocatore                     |                  **Massimo 2** |
| Avversari da mantenere in una situazione di duello raggiungibile                  | **Almeno 1, quando possibile** |

**Un attaccante alla volta non significa un solo nemico coinvolto.** Gli altri preparano posizioni, combattono contro i gregari o stanno difendendosi dal giocatore.

## RELIEF

Quando la pressione si prolunga senza pause, il direttore introduce un breve periodo senza **nuove autorizzazioni offensive contro il giocatore**.

Come prova iniziale: circa **3 secondi di respiro dopo 6–8 secondi di pressione sostenuta**.

Non lo attiverei dopo ogni singolo missile e non lo prolungherei automaticamente a ogni colpo ricevuto.

Durante questa modalità:

**I missili già lanciati continuano a funzionare. Gli aerei continuano a volare e difendersi. Gli alleati continuano a combattere.**

Si rinviano soltanto nuovi attacchi diretti, mentre un avversario rimane disponibile per il contrattacco del giocatore.

Il passaggio fondamentale è:

> Il respiro deve creare un’occasione di gioco, non soltanto qualche secondo senza danni.

## Autorizzazioni separate dai ruoli

Il ruolo offensivo permette di preparare un attacco, ma il permesso di sparare viene richiesto vicino alla finestra utile.

La prenotazione scade se il pilota non riesce a usarla. Al lancio, il missile diventa una minaccia attiva indipendente dal lanciatore.

Abbattere l’aereo **non libera immediatamente il posto occupato dal suo missile ancora in arrivo**.

---

# 6. I due gregari

Userei la stessa macchina a stati dei nemici, con due politiche differenti. Per ora nessun menu di ordini: devono già funzionare autonomamente.

## Gregario 1: copertura

La sua priorità è ridurre una minaccia concreta contro il giocatore.

Normalmente può impegnare un nemico, ma quando un altro avversario ottiene una buona posizione sul giocatore valuta l’intervento.

Il ciclo tipico è:

```text
REPOSITION vicino all'area del giocatore
	↓
SETUP_ATTACK sull'inseguitore pericoloso
    ↓
ATTACK
    ↓
EXTEND
    ↓
Rivaluta la necessità di copertura
```

Non deve inseguire un avversario lontano abbandonando il giocatore. Il limite di inseguimento deve considerare anche quanto tempo impiegherebbe a tornare.

Può essere impegnato dal nemico 3, quindi **non è sempre libero di salvare il giocatore istantaneamente**.

## Gregario 2: supporto offensivo

Il secondo gregario affronta preferibilmente un nemico diverso da quello su cui il giocatore sta già lavorando.

Il suo compito è alleggerire lo scontro e creare combattimenti paralleli.

Se il giocatore è in seria difficoltà o il primo gregario non è disponibile, può contribuire alla copertura.

Entrambi possono difendersi, subire danni e ottenere abbattimenti reali.

**Non impedirei ai gregari di uccidere.** Per evitare che risolvano lo scontro da soli, regolerei aggressività, qualità del tiro e tempo trascorso fuori posizione. Non introdurrei nemici che rimangono magicamente a un punto vita finché non arriva il giocatore.

---

# 7. Quando sparano e quando non sparano

Il `WeaponController` rimane indipendente dalla macchina tattica.

Lo sparo richiede contemporaneamente:

```text
Bersaglio valido
+ arma pronta
+ distanza e angolo utilizzabili
+ soluzione sufficientemente stabile
+ traiettoria iniziale libera
+ manovra compatibile
+ autorizzazione del direttore, quando il bersaglio è il giocatore
```

Un nemico in `ATTACK` può quindi **non sparare**, perché ha perso la soluzione.

Un nemico non deve invece trattenere il fuoco senza una ragione leggibile nel debug.

Mostrerei sempre un motivo, per esempio:

```text
OUT_OF_CONE
TOO_CLOSE
LOCK_UNSTABLE
WEAPON_COOLDOWN
NO_ATTACK_PERMISSION
DEFENSIVE_MANEUVER
```

Questa separazione evita di correggere il comportamento di volo quando il problema è semplicemente un’autorizzazione che non viene rilasciata.

---

# 8. Che cosa cambia con sei o più nemici

**Aumenterei il numero di avversari coinvolti, non proporzionalmente il numero di attacchi sul giocatore.**

Con sei nemici puoi avere un attaccante sul giocatore, un avversario coinvolto nel suo duello, due contro i gregari e due in supporto o in preparazione per rilevare gli incarichi.

I nemici aggiuntivi non devono congelarsi in attesa. Possono prendere posizione, supportare un compagno o completare una separazione. Quando rilevano un ruolo, arrivano da una situazione costruita fisicamente.

Il limite di pressione sul giocatore rimane inizialmente uguale a quello del test con quattro.

Man mano che gli avversari vengono abbattuti, il direttore riduce la distribuzione. **Non mantiene artificialmente quattro ruoli quando sono rimasti due aerei.**

Con un solo nemico, lo stesso aereo alterna attacco, difesa e recupero. Il duello finale deve funzionare anche senza la regia di un gruppo numeroso.

---

# 9. Il test che deve convincerti

Nel debug di ogni aereo mostrerei almeno:

```text
ROLE: PLAYER_PRESSURE
TARGET: Player
STATE: SETUP_ATTACK
STATE_TIME: 1.7
LAST_TRANSITION: TARGET_IN_REACH
FIRE_BLOCK: LOCK_UNSTABLE
```

Nel direttore:

```text
MODE: NORMAL
PLAYER_ATTACKERS: 1 / 1
ACTIVE_PLAYER_MISSILES: 1 / 2
PLAYER_DUEL_OPPONENT: Enemy_2
```

La prima prova deve rispondere soprattutto a queste domande:

| Domanda                                                       | Problema da cercare                                                    |
| ------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Il giocatore trova regolarmente un bersaglio raggiungibile?   | Tutti si allontanano o finiscono dietro di lui.                        |
| Riesce a completare un inseguimento?                          | Il nemico interrompe ogni opportunità con una nuova evasione perfetta. |
| Deve occasionalmente difendersi?                              | I nemici sono presenti, ma non producono minacce concrete.             |
| Dopo essersi difeso può tornare all’attacco?                  | Gli avvisi e i lanci si susseguono senza pausa.                        |
| I gregari aiutano senza monopolizzare gli abbattimenti?       | Sono inutili oppure risolvono tutto prima del giocatore.               |
| I comportamenti continuano a funzionare dopo un abbattimento? | Ruoli, bersagli o autorizzazioni rimangono bloccati.                   |

## La struttura finale, in una frase

**Un direttore assegna quattro funzioni — pressione, duello raggiungibile e due combattimenti con i gregari — mentre ogni pilota usa gli stessi sette stati: riposizionamento, preparazione, attacco, separazione, difesa, evasione missile e recupero.**

La regola più importante per il primo prototipo è questa:

> **Ogni azione forte del nemico deve comportare un impegno: una passata finisce, una difesa richiede di ricomporsi, un inseguimento può fallire. È in quei passaggi che il giocatore trova le occasioni per divertirsi.**
