# Aero Demons — continuità del paesaggio e occultamento del limite del terreno

**Data:** 8 settembre 2026  
**Stato:** ricerca e conclusioni di advisory; nessuna implementazione autorizzata da questo documento.  
**Autori del confronto:** assistente principale e **Claude Fable 5.1 High**, consultato tramite `devin -p`.  
**Obiettivo:** una vista convincente dal volo basso fino a circa 19–20 km, usando Project Wingman come riferimento visivo, senza noise di background Terrain3D, recinzioni di nuvole o lavaggio uniforme della scena.

## 1. Decisione finale

**Non aggiungere altra foschia o altre nuvole periferiche prima di isolare ciò che sta producendo l'immagine attuale.** Il problema comprende sia la composizione dell'atmosfera sia la continuità del mondo oltre la geometria dettagliata.

La direzione condivisa è:

1. **Isolare Sky3D, atmosfera Sunshine e grandi effectors** con confronti ripetibili, mantenendo terreno e luce invariati.
2. **Usare un solo sistema atmosferico principale**, con terreno, nuvole e sfondo che convergano cromaticamente. Sunshine è il primo candidato da valutare, non una scelta già validata.
3. **Verificare se basta un raccordo atmosferico/cromatico o serve un fondale con variazioni spaziali.** Non impegnarsi subito in un export enorme.
4. **Per un panorama alpino libero e molto leggibile a 20 km, il contesto geometrico realizzato in World Creator è la soluzione di produzione ritenuta più robusta.** Diventa necessario per il progetto soltanto se i prototipi più semplici non soddisfano il risultato visivo concordato.
5. **Correggere e ritarare il modello atmosferico Sunshine**, che presenta un problema dimensionale verificato. Non trattarlo come una sostituzione testuale priva di conseguenze.
6. **Conservare i limiti di volo come margine di sicurezza**, non come principale strumento per nascondere il paesaggio.

Non è stato dimostrato che servano una mappa da 200 km, un renderer planetario, un nuovo addon o nuvole più alte. Nessuna di queste scelte è approvata da questa ricerca.

## 2. Provenienza e affidabilità del confronto

### Consultazione effettiva

- CLI: Devin `3000.6.14`.
- Modello richiesto e verificato nell'export: `claude-fable-5-1-high` / Claude Fable 5.1 High.
- Sessione: `peridot-lyric`.
- Modalità: `-p`, permessi `auto`, istruzioni esplicite di sola lettura.
- Primo avvio: l'advisor ha esaminato le immagini; una richiesta di shell per elencare file è stata bloccata dai permessi non interattivi.
- Ripresa: stessa sessione e stesso modello, usando letture native dei file, senza ampliare i permessi.
- Secondo confronto: l'assistente principale ha verificato i reperti e contestato alcune conclusioni troppo assolute. Fable ha accettato le precisazioni indicate nella sezione 7.
- L'export conferma che tutti i turni dell'advisor hanno usato il modello richiesto. In ripresa il flag `--model` è ignorato dalla CLI, ma il modello salvato nella sessione era quello corretto.

Tracce locali della consultazione, conservate nella directory temporanea dell'utente:

- `aero-fable-advisor-prompt.md`;
- `aero-fable-advisor-output-continued.txt` — prima relazione completa;
- `aero-fable-advisor-followup.txt` — precisazioni conclusive;
- `aero-fable-advisor-session.json` — export della sessione.

Queste tracce temporanee non sono necessarie per leggere il presente documento e possono non essere disponibili su altre macchine.

### Limiti dell'evidenza

- Entrambi gli interlocutori hanno visionato le quattro immagini di Project Wingman e la comparativa iniziale Aero Demons. Fable ha dichiarato esplicitamente di averle aperte tutte dopo alcune letture inizialmente troncate.
- **La comparativa Aero Demons precede la patch di fog/effectors/confini. Non è una fotografia del risultato successivo.** Non può provare che gli effectors aggiunti abbiano causato le nuvole visibili in quello scatto.
- Il footprint Terrain3D è stato misurato dall'assistente principale durante la ricerca precedente, caricando il terreno in sola lettura. Fable lo ha ricevuto come dato, senza riverificarlo in engine.
- I nuovi reperti sono derivati dal codice; **nessuna nuova validazione visiva o profilazione GPU è stata eseguita durante l'advisory**.
- Una formula verificata non dimostra da sola quanto un difetto contribuisca al frame finale: contano attivazione runtime, compositing, luce, tonemapping e camera.
- I test headless precedentemente riportati non certificano qualità estetica né somiglianza a Project Wingman.

## 3. Che cosa sappiamo di Project Wingman

### Documentato

- L'intervista allo sviluppatore Abi Rahmani descrive terreno realizzato con **World Machine**, erosione/fiumi e heightmap importate in UE4, oltre all'impiego di LOD [S1].
- Il devlog Alpha Test 4 Update 1 menziona esplicitamente **trueSKY** e il problema della risoluzione delle nuvole lontane [S2].
- L'annuncio ufficiale della beta 2.0 del 2023 dichiara una revisione completa del sistema cielo/nuvole e del rendering [S3].

### Non determinato

Non è emersa una dimensione numerica affidabile delle mission map dalle fonti consultate. Non sono noti la missione/build degli screenshot, i parametri atmosferici, la geometria esterna o lo shader preciso usato per il raccordo del bordo.

Il riferimento a **512 × 512 km** trovato in un thread Unreal è la necessità ipotizzata da un altro sviluppatore per il proprio progetto: **non è una misura di Project Wingman** [S4].

Distinguere sempre:

| Estensione | Significato |
|---|---|
| Area giocabile | Confini che attivano richiamo/rientro. |
| Terreno geometrico | Superficie renderizzata, eventualmente più estesa dell'arena. |
| Ambiente visibile | Cielo, nuvole, atmosfera ed eventuali fondali. |

La documentazione UE4.27 sulla prospettiva atmosferica [S5] illustra una tecnica pertinente; non dimostra che quella specifica componente produca i nostri screenshot di riferimento.

### Osservazioni condivise sulle immagini

File di riferimento in `C:/Users/sanna/Pictures/Screenshots/`:

- `Screenshot 2026-09-08 211919.png`;
- `Screenshot 2026-09-08 211932.png`;
- `Screenshot 2026-09-08 211935.png`;
- `Screenshot 2026-09-08 211948.png`.

L'altitudine indicata varia da 61.586 a 64.159 piedi: circa **18,77–19,56 km**. I 60.000 piedi esatti corrispondono a 18,288 km.

Si osservano:

- aereo con contrasto elevato rispetto al paesaggio;
- ombre e differenze neve/roccia che convergono verso azzurro-grigio con la distanza;
- nuvole distribuite irregolarmente, che continuano oltre i rilievi dettagliati;
- zone lontane poco dettagliate ma cromaticamente coerenti, invece di un vuoto nettamente separato;
- cielo scuro in alto e banda atmosferica chiara all'orizzonte.

Non possiamo identificare dalle sole immagini se le zone lisce siano acqua, terreno semplificato, cielo inferiore o un fondale. Un apparente cambio di dettaglio non prova un particolare sistema LOD. Neppure l'impressione di curvatura identifica una geometria planetaria: proiezione, camera e shader possono influenzarla.

**Il risultato da perseguire è una perdita progressiva di contrasto dentro un mondo visivamente continuo, non la cancellazione uniforme del paesaggio.**

## 4. Scala del nostro problema

Misura Terrain3D in sola lettura, eseguita dall'assistente principale durante la ricerca:

| Dato | Valore |
|---|---:|
| Regioni caricate | 626 |
| Dimensione regione | 512 campioni |
| Vertex spacing | 4 m |
| Estremi X | −26.624 / +26.624 m |
| Estremi Z | −26.624 / +24.576 m |
| Rettangolo complessivo | **53,248 × 51,200 km** |

È il rettangolo delle regioni caricate, non una prova di copertura continua né della quota del bordo. Non inferire gli estremi dal solo conteggio dei nomi file: ci sono indici negativi e la dimensione effettiva delle regioni non va sostituita con un default presunto.

Il controller, con questo rettangolo e `return_margin = 6000`, ricava un raggio di rientro di **18.576 m**, con avviso 5 km prima. È un'arena centrata sull'origine, non sull'esatto centro del rettangolo. Le distanze al bordo differiscono quindi per lato e posizione.

Geometria illustrativa su piano, senza rilievi o curvatura: a quota H, la distanza orizzontale osservata a depressione θ è `H / tan(θ)`.

| Da 20 km di quota | Distanza orizzontale |
|---|---:|
| Sguardo a 45° sotto l'orizzonte | 20 km |
| 30° | 34,6 km |
| 20° | 55 km |
| 10° | 113,4 km |

Dal centro, il bordo a circa 25–27 km non è confinato all'orizzonte: è dentro la vista verso il basso. Vicino al limite giocabile il problema è ancora più forte.

La quota massima del player nel codice ispezionato è 15 km; le viste da 19,5 km sono pertanto **un requisito diagnostico/artistico**, finché il game design non autorizza di cambiare l'inviluppo di volo. Non alzare silenziosamente il limite del player.

## 5. Reperti tecnici verificati e loro conseguenze

I riferimenti sono relativi allo snapshot ispezionato; scene e numeri di riga possono cambiare. La scena attuale è `scenes/maps/garda_lake.tscn`, mentre parte degli script conserva il nome tutorial.

### 5.1 AtmFog: rampa corta e forte opacità

In `scripts/maps/tutorial_boundary_controller.gd`, `_setup_haze()` applica:

```text
fog_density = 0.00025
fog_start   = 4000
fog_end     = 5000
fog_falloff = 0.35
```

In `addons/sky_3d/shaders/AtmFog.gdshader:73–85,139–141`, l'opacità combina:

- `1 − exp2(−distanza × densità)`;
- una rampa fra start/end;
- una funzione della direzione verticale del raggio.

Per i raggi discendenti, oltre il termine della rampa:

| Distanza | Opacità teorica della fog |
|---|---:|
| 5 km | 58% |
| 10 km | 82% |
| 19 km | 96% |
| 30 km | 99% |

**Interpretazione:** non è una nebbia esclusivamente periferica. Può sostituire quasi tutto il colore del terreno osservato dall'alta quota.

Fable ha aggiunto un punto importante: con `fog_falloff = 0.35`, anche lo zenit mantiene un fattore `exp(-0.35) ≈ 0.705`. Se il quad tratta un pixel cielo a grande profondità, la fog può pesare circa il 70% anche guardando in alto. Il rischio di lavare il cielo non riguarda quindi soltanto il terreno. Va verificato con il toggle a runtime.

### 5.2 Correzione della precedente spiegazione: non esiste il limite runtime di 5 km

`addons/sky_3d/src/SkyDome.gd:730–743` usa `@export_range(0,5000)` ma i setter inoltrano il valore senza clamp.

Il commento nel controller che motiva i 4–5 km con un limite dell'addon è **sbagliato**. È un intervallo dell'Inspector, non un limite fisico, del renderer o dello shader.

### 5.3 Composizione: la fog trasparente non conosce automaticamente la profondità delle nuvole

- Sunshine: `effect_callback_type = 3` in `resources/environments/tutorial_clouds.tres`, cioè PRE_TRANSPARENT.
- AtmFog: quad spaziale trasparente che legge `DEPTH_TEXTURE`.
- SkyDome: priorità fog 100 e offset atmosferico fog `(0,0,-1)` nei default ispezionati (`SkyDome.gd:780–800`).

Le nuvole già composte non diventano automaticamente superfici della depth opaca. Il quad successivo può quindi trattarle con la profondità del terreno o dello sfondo e lavarle impropriamente. È un rischio concreto del flusso attuale, non una previsione della percentuale esatta di nuvole cancellate.

Anche il colore ha forti semplificazioni: il calcolo ottico Sky3D clampa le direzioni basse; l'offset della fog favorisce una colorazione di tipo orizzonte su ampie direzioni. La scelta deve essere giudicata su zenit, orizzonte e nadir, non con un solo color picker sul bordo.

### 5.4 Sunshine: problema dimensionale nel modello atmosferico

Reperto di Fable, verificato dall'assistente principale:

`addons/SunshineClouds2/SunshineCloudsPostCompute.comp:185–193` usa:

```text
iHeight = curPos.y / atmosphericHeight
odStepRlh = exp(-iHeight / Rayleighscaleheight) * distanceTraveled
odStepMie = exp(-iHeight / Miescaleheight) * distanceTraveled
```

Le costanti sono `atmosphericHeight = 40000`, `Rayleighscaleheight = 8000`, `Miescaleheight = 1200`. Il calcolo è duplicato nel compute delle nuvole (`SunshineCloudsCompute.glsl:336–344`).

Con coordinate in metri, l'altezza già normalizzata viene divisa per una scala di altezza ancora espressa in metri. A y=20.000 m:

- l'esponenziale Rayleigh attuale è circa `exp(-0.5/8000) ≈ 0.99994`;
- un profilo esponenziale con scala 8 km sarebbe `exp(-20000/8000) ≈ 0.0821`.

Nell'implementazione esiste inoltre il moltiplicatore lineare `1 − clamp(iHeight,0,1)` nell'attenuazione. **Non si può quindi descrivere il sistema come un corretto profilo esponenziale in quota.**

Questi valori non sono un rapporto tra le radianze finali: attenuazione accumulata, fase, blend, clamp e tonemapping impediscono di tradurli in «il frame è N volte più nebbioso».

La futura correzione richiede:

- coerenza fra entrambe le copie, per non separare colore delle nuvole e del terreno;
- nuova taratura, non conservazione automatica dei vecchi coefficienti artistici;
- gestione dei raggi senza geometria e delle quote negative;
- prevenzione di overflow/NaN e risultati degeneri;
- verifica del campionamento, oggi a dieci passi nel post-pass;
- confronto prima/dopo a più quote.

**Riutilizzare Sunshine rimane sensato, ma non significa accettare il modello attuale come fisicamente corretto.**

### 5.5 Effectors: saturazione locale dimostrabile, copertura globale da misurare

Il controller crea dieci effectors con raggi 9–22 km e Power 1,5–3.

`SunshineCloudsCompute.glsl:130–139,174–201` somma contributi lineari con la distanza. Nell'interno dello strato, dove `edgeFade` è prossimo a 1, un additivo ≥1 può portare la shape al clamp superiore e sopprimere la variazione del noise. Con Power 3, il contributo grezzo di un singolo effector resta ≥1 entro due terzi del suo raggio.

È quindi verificato **il meccanismo di saturazione**, non la percentuale di mappa saturata: dipende da quota, layout, sovrapposizioni, edgeFade e campionamento.

Conseguenza condivisa: disattivare gli effectors per la diagnosi e non usarli come sistema primario di occultamento. La foto iniziale non può essere attribuita a questi effectors, perché li precede.

### 5.6 Sfondo oltre il terreno

La scena imposta `world_background = 0`; il terreno non viene prolungato dal background Terrain3D. Nelle zone non coperte da altra geometria è quindi il cielo a contribuire.

`SkyMaterial.gdshader`, nel ramo sotto-orizzonte, usa il colore di terra del cielo e lo scattering; il materiale della scena ha `ground_color = (0.3,0.3,0.3)`. Anche Sunshine tratta i raggi senza geometria e può portarli a un forte blend atmosferico.

**Due candidati distinti per il riempimento uniforme oltre il bordo:** cielo inferiore Sky3D e atmosfera Sunshine. Il loro contributo va separato sperimentalmente. Il colore finale non è rigorosamente costante in tutte le direzioni: possono intervenire sole, fase e altri termini.

### 5.7 Portata e resa delle nuvole dall'alto

- Strato attuale: 750–2.300 m.
- Budget nominale: 700 passi × 140 m = 98 km.
- Il compute include attenuazione legata alle distanze nominali 35–98 km, oltre alle uscite anticipate.

Non è una garanzia di copertura fino a 98 km. La distribuzione dei passi e la distanza alla banda contano anche per il costo.

**Una camera sopra lo strato può vedere le nuvole guardando in basso.** L'uscita anticipata ispezionata non elimina indiscriminatamente quei raggi. Non alzare il tetto nuvoloso a 20 km per risolvere questo problema.

### 5.8 Controlli secondari, non ancora diagnosi

- `directional_shadow_max_distance = 4000`: le shadow map del sole non coprono terreno a decine di chilometri dalla camera. Restano illuminazione delle normali ed eventuali altri contributi: non equivale a «nessuna ombra o lettura del rilievo in assoluto».
- Camera far circa 100 km: non coincide con copertura effettiva della clipmap o con visibilità atmosferica utile.
- Verificare copertura/LOD Terrain3D: il bordo osservato potrebbe includere un limite di rendering, non soltanto il termine dei dati. Non è stato dimostrato nel runtime.
- Ombre più lunghe, cielo variabile con la quota e cirri lontani sono rifiniture successive. Non aumentare alla cieca la distanza ombre: costo, risoluzione e acne vanno misurati.

## 6. Quale fondale adottare: decisione condizionata al risultato

| Opzione | Utilità | Limite / decisione |
|---|---|---|
| Solo raccordo cromatico/atmosferico | Esperimento economico, nessun nuovo asset | Può lasciare un rettangolo texturizzato dentro un campo uniforme. Non considerarlo già sufficiente a 20 km. |
| Fondale con albedo a bassa frequenza | Aggiunge continuità senza terreno dettagliato ovunque | Deve essere ancorato coerentemente al mondo e reggere nadir, moto e viste radenti; un piano uniforme non basta. |
| Contesto geometrico da World Creator | Soluzione più robusta per rilievi esterni ancora leggibili | Nuovo lavoro di authoring/import e raccordo. Solo dopo un prototipo e autorizzazione dell'utente. |
| Anello di montagne in skybox/impostor | Può aiutare viste radenti | Da solo non riempie correttamente la vista verso il basso a 20 km. |
| Noise background Terrain3D | Nessun vantaggio per questa direzione artistica | Escluso per esplicita preferenza dell'utente. |

Fable aveva proposto, come ordine di grandezza esplorativo, un contesto di circa 200 km con campionamento grossolano. **Non lo adottiamo come dimensionamento.** Prima vanno definiti quota, posizione massima, visibilità richiesta, dettaglio distinguibile e budget.

Un eventuale contesto non si raccorda semplicemente abbassandolo di 30–50 m: servono registrazione delle coordinate, compatibilità di altezza e colore al bordo, overlap controllato e verifica di fessure/doppie superfici. Campionamento del bordo esistente soltanto in lettura.

Un piano FLAT nativo, qualora disponibile nella versione di Terrain3D, era stato proposto dall'advisor come prova diagnostica. Non è stato verificato né scelto: per mantenere isolato e read-only il terreno importato, preferiamo che ogni eventuale prototipo di fondale sia un elemento separato.

## 7. Dove il confronto ha cambiato la proposta

| Tema | Posizione iniziale dell'assistente | Intervento Fable | Conclusione dopo replica |
|---|---|---|---|
| Fondale | Lasciare aperto un semplice raccordo atmosferico | Geometria esterna ritenuta indispensabile a 20 km | Non è un teorema. Serve test; contesto WC preferibile per vista alpina libera e leggibile, fondale più semplice possibile se il design accetta lontananza più velata. |
| Atmosfera Sunshine | Esiste già, quindi provarla prima di riscrivere | Individuato problema di unità nell'esponenziale | Confermato nel codice; riuso con correzione coerente e retuning, non un nuovo renderer per default. |
| AtmFog | Rischio di lavare terreno e nuvole | Evidenziato forte contributo anche allo zenit con falloff 0,35 | Verificato analiticamente; confermare il peso visivo con A/B. |
| Effectors | Possibile sovrapposizione invasiva | Saturazione attribuita con eccessiva certezza a gran parte della mappa | Meccanismo locale verificato; estensione e responsabilità nel look da misurare. Foto iniziale non valida come prova post-patch. |
| Raccordo contesto | Da progettare | Ipotesi di mesh abbassata sotto il terreno | Abbassamento non garantisce continuità: matching reale, overlap e viste radenti obbligatori. |
| Ordine del lavoro | Atmosfera, fondo, nuvole, confini | Più enfasi su superficie esterna e correzione fisica | Prima esperimento piccolo; poi decisione su fondale e correzione del modello in confronti separati. |

Estratti conclusivi dell'advisor, dopo il contraddittorio:

> «Contesto geometrico WC = soluzione di produzione più robusta SE si vuole vista alpina libera a 20 km con alta leggibilità; test piccolo prima di autorizzare l'export 200 km».

> «Se il design accetta che a 20 km la vista lontana sia deliberatamente lattiginosa [...] il fondale texturizzato può bastare e l'export WC non serve».

> «Ritengo probabile, non certo, che il match cromatico da solo [...] non basti a 19.5 km [...] ma è esattamente ciò che l'esperimento deve stabilire».

Questa è la divergenza residua: **quanto è probabile che serva geometria di contesto**, non il metodo con cui decidere. Entrambi concordiamo che la prova visiva venga prima dell'impegno produttivo.

## 8. Piano operativo proposto, con condizioni di avanzamento

Queste sono attività future. Il documento non le ha eseguite e non autorizza import o modifiche al terreno.

### Stadio A — esperimento minimo senza nuovi asset

Preparare una prova isolata, senza salvare dati Terrain3D e senza cambiare preset condivisi da altre scene. Fissare posizione, camera/FOV, luce, esposizione e fase temporale delle nuvole.

Prima matrice: centro mappa, quote **5 e 19,5 km**, viste **45° e nadir**, sole di lato. Aggiungere una vista verso zenit/orizzonte per verificare il lavaggio del cielo.

Tre configurazioni, separabili:

- **A:** stato attuale.
- **B:** come A, ma AtmFog ed effectors periferici disattivati; tutto il resto invariato.
- **C:** come B, con sola taratura del raccordo cromatico del cielo inferiore, senza nuova geometria.

C modifica un parametro artistico per volta: se Sunshine sovrascrive il cielo, prima identificare quel contributo invece di compensarlo alla cieca con `ground_color`.

Registrare:

- screenshot comparabili e breve video;
- luminanza/contrasto su coppie di superfici note, a distanze effettivamente misurate;
- salto di colore e di struttura attraverso il bordo;
- colore dello zenit;
- tempi GPU con stessa risoluzione e condizioni di misura.

Distinguere quota della camera e distanza del campione: da 19,5 km il terreno sotto l'aereo non si trova a 5 km. Evitare confronti fra campioni che non esistono geometricamente o che cambiano illuminazione.

**GO:** B chiarisce il contributo della sovrapposizione; C riduce il salto senza distruggere la leggibilità alle altre viste. Si procede sul componente identificato.

**STOP diagnostico:** B non cambia il fenomeno previsto, oppure fog dichiarata attiva non contribuisce. Verificare camera, layer, stato runtime e compositing prima di aggiungere altro.

**Segnale per provare un fondale:** il colore medio coincide ma resta evidente il passaggio da superficie con dettaglio a campo uniforme. Non serve allora aumentare indefinitamente la densità.

### Stadio B — autorità atmosferica e correzione del modello

Usare Sunshine come primo candidato perché già compone atmosfera e nuvole, ma giudicarlo sul risultato.

Correggere il problema delle unità in una prova separata; mantenere coerenti i due shader e ritarare i coefficienti. Verificare raggi orizzontali, discendenti, senza geometria, ad alta quota e sotto il riferimento verticale. Test numerici minimi su finitezza e profilo in quota, più confronto renderizzato.

Non aggiungere Godot Environment fog come terza toppa. `fog_aerial_perspective` [S6] rimane un'alternativa nativa da valutare soltanto in una pipeline isolata e compatibile con le nuvole.

**GO:** miglior controllo del contrasto fra quote e distanze, assenza di discontinuità nuvole/terreno e stabilità del cielo.

**STOP:** il fix introduce NaN, whiteout, cambi di colore fra le due componenti o costo non giustificato. Nessuna promozione del solo test numerico a validazione estetica.

### Stadio C — decidere se basta un fondale semplice

Provare il minimo elemento esterno separato che offra variazione a bassa frequenza, anziché un colore uniforme. Non estendere né riscalare il terreno importato per la prova.

**GO senza nuovo export WC:** il fondale regge il volo e la direzione artistica accetta la leggibilità ottenuta.

**GO verso contesto WC:** le viste alte o radenti richiedono rilievi/silhouette/parallasse che il fondale semplice non può fornire con qualità sufficiente. Preparare una richiesta di authoring con estensione motivata, registrazione e criteri di raccordo.

**STOP:** compare un nuovo bordo del fondale, una costa/scogliera involontaria, ripetizione evidente, fessura o superficie doppia. Non nascondere questi problemi aggiungendo opacità globale.

### Stadio D — nuvole, confini e rifinitura

- Reintrodurre solo gli effectors utili alla composizione, senza saturazione incontrollata.
- Valutare una rappresentazione economica delle nuvole lontane soltanto se il volume attuale lascia una discontinuità visibile.
- Verificare lato, angolo e margine di rientro alla massima velocità, oltre alla vista dal centro.
- Misurare shadow distance/LOD/costi prima di estendere la qualità a grandi distanze.
- Cielo variabile con la quota solo dopo aver risolto la continuità principale.

### Accettazione finale

Matrice ampliata: quote 2/5/10/19,5 km; centro e punti vicini ai confini; lato e angolo; orizzonte, obliqua e nadir; sole davanti e dietro. Se 19,5 km resta fuori dal gameplay, va indicato esplicitamente nel rapporto.

Il risultato passa quando:

1. il bordo rettilineo non cattura subito l'attenzione in volo;
2. aereo e bersagli mantengono leggibilità;
3. il terreno sotto l'aereo conserva struttura, senza patina uniforme;
4. i buchi nelle nuvole mostrano un fondo credibile;
5. non si legge un anello o rettangolo nuvoloso artificiale;
6. virate e spostamenti non rivelano cuciture o fondali incollati alla camera;
7. GPU frame time resta nel budget concordato, documentato con misure.

Le soglie di contrasto/luminanza suggerite inizialmente dall'advisor erano ipotesi di lavoro, non standard validati. Prima fissare baseline, regioni di campionamento ed esposizione; poi concordare soglie utili. Il giudizio del proprietario sulla resa resta necessario.

## 9. Vincoli e cose da non fare

- `wc_data/`, geometria, distribuzione delle texture e maschere importate restano read-only.
- Eventuale nuovo contesto alpino: authoring in World Creator e import separato soltanto dopo autorizzazione.
- Non ridurre il contrasto del terreno alterando maschere o materiali importati come scorciatoia: qui si sta lavorando sull'ambiente.
- Niente noise Terrain3D, renderer planetario o nuove dipendenze per default.
- Niente parete di nuvole, incremento indiscriminato di density o tetto nuvole a 20 km.
- Niente stacking non coordinato di Environment fog, AtmFog e Sunshine.
- Niente modifica dell'inviluppo del player solo per far funzionare una prova visiva.
- Non attribuire a Project Wingman dimensioni o tecniche non documentate.
- Non chiamare «risolto» un intervento visivo soltanto perché gli script vengono caricati senza errori.

## 10. Fonti e prossimo passo

- **[S1]** [PCGamesN — Making it in Unreal: how Project Wingman is taking off](https://www.pcgamesn.com/project-wingman/unreal-engine-4-flight-simulator). Intervista: World Machine, UE4 e LOD; nessuna dimensione numerica.
- **[S2]** [RB-D2 — Project Wingman Alpha Test 4 Update 1](https://rb-d2.itch.io/wingman/devlog/1337/project-wingman-alpha-test-4-update-1). trueSKY e qualità delle nuvole lontane nelle prime versioni.
- **[S3]** [Annuncio ufficiale — Platform Update 2.0](https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/5220291886505774663). Revisione del sistema cielo/nuvole nel 2023.
- **[S4]** [Epic Forums — How to create skyline?](https://forums.unrealengine.com/t/how-to-create-skyline/222164). Fonte del numero 512 km da non attribuire a Wingman.
- **[S5]** [Epic — Sky Atmosphere, UE4.27](https://dev.epicgames.com/documentation/en-us/unreal-engine/sky-atmosphere?application_version=4.27). Principi replicabili, non prova dell'implementazione PW.
- **[S6]** [Godot — Environment](https://docs.godotengine.org/en/4.7/classes/class_environment.html). Fog e aerial perspective.

**Prossimo passo raccomandato:** autorizzare soltanto lo Stadio A, con confronto visivo a camera fissa e nessun nuovo asset. È il modo più piccolo e verificabile per decidere se il lavoro successivo debba concentrarsi sul compositing, sul modello atmosferico o sul contesto esterno. Il contesto WC rimane la strada preferita se il target richiede rilievi esterni leggibili a 20 km, non un investimento già deciso.
