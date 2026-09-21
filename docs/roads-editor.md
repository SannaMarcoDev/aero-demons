# Strade nell’editor — prova Garda

Apri `res://scenes/maps/garda_roads_test.tscn`. La scena eredita il Garda senza
modificarlo. Terrain3D usa una **copia fisica indipendente**, non un collegamento
alla sorgente. Su un nuovo checkout, preparala prima di aprire la scena:

```sh
node tools/prepare_road_sandbox.cjs
```

La copia occupa circa 1,9 GB ed è esclusa da Git. Il comando rifiuta una
destinazione già esistente. La sandbox locale è stata ripristinata dal terreno
originale: non occorre applicare alcun raccordo o scavo.

## Disegnare

1. Seleziona `RoadManager/TwoLaneRoads` e premi **F** nell’editor 3D. La prova
   contiene due corsie da 3,5 m, banchine asfaltate da 40 cm, una curva, un
   incrocio a T e uno a quattro bracci, a sud-est dell’aeroporto.
2. Prolunga un `RoadPoint` terminale con **Roads / Add**. Muovi punti e maniglie
   Bézier, oppure modifica `Prior Mag` / `Next Mag` nell’Inspector. I punti
   prolungati ereditano il profilo: mantieni **Gutter Profile = (0, 0)** per bordi
   netti senza pareti laterali. Su nuovi punti indipendenti imposta lo stesso
   profilo e due corsie con direzioni opposte.
3. Gli strumenti nativi posizionano i punti sulle collisioni. La sandbox usa
   **Dynamic / Editor**, raggio 256 m: lavora vicino alla superficie. Il comando
   esistente **Snap to Terrain / Page Down** può riallineare i punti di controllo;
   non è necessario per far aderire la superficie stradale.
4. Usa i `RoadIntersection` nativi per T e quattro vie. Attraversare due curve
   nello spazio **non** crea una connessione: collega esplicitamente i bracci.
   I centri degli incroci vengono proiettati insieme ai tratti stradali.
5. I due esempi usano **Settings → `resources/roads/rounded_rural_junction.tres`**:
   raccordi curvi tangenti ai bracci, anziché il grande poligono del generatore
   predefinito. Carica lo stesso preset nei nuovi incroci. Per regolare l’ingombro
   sposta i punti di ingresso: nella prova sono a 12 m dal centro; non portarli
   tanto vicini da sovrapporre i bracci. Non sono aggiunte frecce o regole di precedenza.

L’asfalto usa dettaglio e normal map in coordinate mondo, continuo fra tratti e
incroci; le UV native restano dedicate alla segnaletica. In questo modo la texture
non riparte in direzioni diverse su ogni triangolo dell’incrocio. I simboli azzurri
visibili selezionando i nodi sono manipolatori dell’editor, non oggetti del gioco.

## Aderenza automatica, senza scavi

`RoadTerrain`, con script `scripts/maps/road_terrain_conformer.gd`, adatta le mesh
prodotte da RoadGenerator alle facce del terreno, comprese curve, banchine e
incroci. Conserva UV e materiali e ricrea le collisioni stradali. Le curve
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

## Verificare

Avvia la scena con **F6**: WASD, Q/E per l’altezza, Shift per accelerare, mouse
per guardare. Esc libera il mouse; un secondo Esc chiude la prova. La scena
principale del gioco non cambia. Controlla soprattutto da **oltre 50 m**, oltre
ai bordi e agli incroci da vicino; un avvio senza errori non prova la qualità
visiva.

Test automatico, senza salvataggi del terreno:

```sh
node tools/run_godot_check.cjs 120 subagent-artifacts/roads/check.log <percorso-godot> --headless --path . --script res://tools/check_road_sandbox.gd
```

Verifica topologia T/X, raccordi concavi con ingressi continui, ingombri compatti,
due corsie, geometria e collisioni aderenti, normali,
aggiornamento dopo una modifica della spline e una scultura in memoria,
stabilità delle rigenerazioni e assenza di modifiche stradali alla heightmap.

## Limiti

- Nessun ponte, tunnel, livellamento ingegneristico o rimozione automatica della
  vegetazione. La rete dimostrativa è nell’esclusione boschiva dell’aeroporto.
- L’aderenza corrisponde alla griglia dettagliata del terreno. I LOD lontani di
  Terrain3D possono differire; non è garantita l’aderenza a qualunque distanza.
- Una scultura aggiorna l’intera rete dopo il rilascio: per reti molto grandi
  andrà limitato l’aggiornamento alla zona modificata.
- Terrain3D 1.0.2 segnala un’API d’interpolazione deprecata su Godot 4.7.1.
  Prima di una release, sostituisci la modalità collisioni **Editor** con **Game**.
