# Strade nell’editor — Garda Final

Apri `res://scenes/maps/garda_final.tscn`: la rete con curva e incroci T/X è ora
nella mappa definitiva, nelle stesse coordinate della prova. Compare quindi
anche in freeroam e tutorial. La scena di prova e la copia del terreno sono state
rimosse; non occorre preparare una sandbox.

Le strade leggono `terrain/garda_geographic_250km/` senza modificarlo. I pennelli
Terrain3D, invece, operano ora sul terreno definitivo: fai un backup prima di
ritoccarlo.

## Disegnare

1. Seleziona `RoadManager/TwoLaneRoads` e premi **F** nell’editor 3D. La rete
   contiene due corsie da 3,5 m, banchine asfaltate da 40 cm, una curva, un
   incrocio a T e uno a quattro bracci, a sud-est dell’aeroporto.
2. Prolunga un `RoadPoint` terminale con **Roads / Add**. Muovi punti e maniglie
   Bézier, oppure modifica `Prior Mag` / `Next Mag` nell’Inspector. I punti
   prolungati ereditano il profilo: mantieni **Gutter Profile = (0, 0)** per bordi
   netti senza pareti laterali. Su nuovi punti indipendenti imposta lo stesso
   profilo e due corsie con direzioni opposte.
3. Non servono collisioni in editor: gli strumenti **Roads** possono leggere
   direttamente le altezze attraverso `RoadTerrain`. Il comando esistente
   **Snap to Terrain / Page Down** può riallineare i punti di controllo;
   non è necessario per far aderire la superficie stradale.
4. Usa i `RoadIntersection` nativi per T e quattro vie. Attraversare due curve
   nello spazio **non** crea una connessione: collega esplicitamente i bracci.
   I centri degli incroci vengono proiettati insieme ai tratti stradali.
5. I due esempi usano **Settings → `resources/roads/rounded_rural_junction.tres`**:
   raccordi curvi tangenti ai bracci, anziché il grande poligono del generatore
   predefinito. Carica lo stesso preset nei nuovi incroci. Per regolare l’ingombro
   sposta i punti di ingresso: nella rete attuale sono a 12 m dal centro; non portarli
   tanto vicini da sovrapporre i bracci. Non sono aggiunte frecce o regole di precedenza.

L’asfalto usa dettaglio e normal map in coordinate mondo, continuo fra tratti e
incroci; le UV native restano dedicate alla segnaletica. In questo modo la texture
non riparte in direzioni diverse su ogni triangolo dell’incrocio. I simboli azzurri
visibili selezionando i nodi sono manipolatori dell’editor, non oggetti del gioco.

## Aderenza automatica, senza scavi

`RoadTerrain`, con script `scripts/maps/road_terrain_conformer.gd`, adatta le mesh
prodotte da RoadGenerator alle facce del terreno, comprese curve, banchine e
incroci. Conserva UV e materiali e ricrea le collisioni stradali solo in gioco. Le curve
restano modificabili: non vengono convertite definitivamente in mesh statiche.

- Lascia **RoadManager / Auto Refresh** attivo.
- L’aggiornamento segue le modifiche alle strade e alle altezze Terrain3D; durante
  un trascinamento/scultura viene rinviato al rilascio del mouse.
- **Clearance = 0,05 m** evita la sovrapposizione delle superfici: non è uno
  spessore di asfalto e non genera muri. Non alzarlo per costruire rilevati.
- **Refresh road surface** rigenera solo la strada; normalmente non serve.
- Il profilo verticale finale viene dal terreno, non dalla quota delle maniglie:
  le strade accettano ondulazioni e pendenze trasversali del suolo.
- Per ritocchi eccezionali usa i normali pennelli Terrain3D e il loro salvataggio.
  Non esistono un comando separato di grading né scavi automatici delle strade.
  Non aggiungere il vecchio `RoadTerrain3DConnector`, che modifica il terreno.

Il passo del Garda è **15,26 m**: proiettare soltanto i punti della spline non
basta. Le facce della strada vengono tagliate lungo i triangoli del terreno.
La lettura delle quote evita inoltre l’arrotondamento errato delle API CPU di
Terrain3D 1.0.2 con questo passo frazionario, usando il texel corrispondente a
quello dello shader. Non cambiare `vertex_spacing`: cambierebbe la scala della
mappa, non solo il dettaglio.

## Collisioni e verifica

- `GardaTerrain / Collision Mode` è **Dynamic / Game**: niente collisioni del
  terreno nell’editor, collisioni dinamiche durante il gioco.
- RoadGenerator genera le collisioni di segmenti e incroci **solo in gioco**.
  La stessa regola vale per tutte le sue chiamate di rigenerazione, compreso
  l’adattamento al terreno. Non serve attivare/disattivare collisioni a mano.
- L’aggiornamento delle mesh resta attivo in editor e conserva il proprio costo.

Per giocare avvia `scenes/levels/freeroam.tscn` o `scenes/levels/tutorial.tscn`.
La mappa non include la camera libera della vecchia prova e non altera le camere
dei livelli. Per esaminare le strade nell’editor, seleziona la rete e premi **F**.
Controlla soprattutto da **oltre 50 m**, oltre ai bordi e agli incroci da vicino.

Test automatico, senza salvataggi del terreno:

```sh
node tools/run_godot_check.cjs 120 subagent-artifacts/roads/check.log <percorso-godot> --headless --path . --script res://tools/check_garda_roads.gd
node tools/run_godot_check.cjs 60 subagent-artifacts/roads/editor-check.log <percorso-godot> --headless --editor --path . --script res://tools/check_garda_roads.gd
```

Verifica topologia T/X, raccordi concavi con ingressi continui, ingombri compatti,
due corsie, geometria e collisioni aderenti, normali,
aggiornamento dopo una modifica della spline e una scultura in memoria,
stabilità delle rigenerazioni e assenza di modifiche stradali alla heightmap.
La seconda esecuzione verifica che in editor vengano rimossi i vecchi collider
e non se ne generino di nuovi, senza caricare né modificare il terreno. Su Windows
chiudi prima l’editor principale: due editor simultanei possono contendere la DLL
ricaricabile di Terrain3D; il test normale non richiede di chiuderlo.

## Limiti

- Nessun ponte, tunnel, livellamento ingegneristico o rimozione automatica della
  vegetazione. La rete dimostrativa è nell’esclusione boschiva dell’aeroporto.
- L’aderenza corrisponde alla griglia dettagliata del terreno. I LOD lontani di
  Terrain3D possono differire; non è garantita l’aderenza a qualunque distanza.
- Una scultura aggiorna l’intera rete dopo il rilascio: per reti molto grandi
  andrà limitato l’aggiornamento alla zona modificata.
- Terrain3D 1.0.2 segnala un’API d’interpolazione deprecata su Godot 4.7.1.
  La modalità collisioni è già configurata per il gioco.
