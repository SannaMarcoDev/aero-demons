# Garda: revisione della superficie

## Risultato e perimetro

Nuovo materiale **solo per `scenes/maps/garda_final.tscn`**, quindi per le istanze Garda in freeroam/tutorial. Lo shader condiviso WC e le altre mappe non sono stati modificati da questo intervento. Nessuna rigenerazione di heightmap, control map, collisioni o import; trasformazione, spaziatura, calibrazione geografica e quota dell'acqua restano quelle della scena precedente.

Nelle viste controllate il nuovo materiale elimina la griglia evidente della distribuzione precedente e mantiene dettaglio leggibile vicino e lontano. Non è una dichiarazione di parità con Nuclear Option: mancano soprattutto copertura del suolo riconoscibile, boschi, campi e oggetti. Il risultato va approvato su Garda prima di estenderlo.

## Confronto visivo riproducibile

Stesse posizioni, luce e geometria; 1920×1080, FOV 70°, nuvole/TAA/FXAA/upscaling disabilitati. **Sinistra: shader/materiali precedenti; destra: nuova superficie.** I nomi `alpine_*` e `lowland` sono identificatori delle camere, non classificazioni geografiche.

- [Versante vicino](images/garda-surface-review/alpine_near.jpg)
- [Distanza intermedia](images/garda-surface-review/alpine_mid.jpg)
- [Versante lontano](images/garda-surface-review/alpine_far.jpg)
- [Lago e coste](images/garda-surface-review/garda.jpg)
- [Vista ravvicinata del suolo](images/garda-surface-review/ground.jpg)
- [Valli e rilievi intermedi](images/garda-surface-review/lowland.jpg)
- [Vista di crociera](images/garda-surface-review/cruise.jpg)
- [Confine fra regioni Terrain3D](images/garda-surface-review/region_seam.jpg)

Il ciclo finale ha prodotto **40 catture**, otto camere per cinque varianti. PNG a piena risoluzione, report JSON e log locali sono in `subagent-artifacts/garda-surface/` (ignorato da Git). Le otto tavole sopra sono conservate nel repository.

| Variante | Valutazione |
| --- | --- |
| `baseline` | Configurazione WC precedente: grana legata alla griglia, roccia arancione ripetuta e neve anche alle basse quote. |
| `native` | Shader Terrain3D senza override: riferimento utile e meno costoso, ma conserva la distribuzione importata e non risolve da solo il dettaglio multiscala. |
| `filtered` | Interpolazione dei materiali anche in minificazione: migliora i passaggi, non corregge palette/distribuzione né crea dettaglio intermedio. |
| `no_color` | Esclude il moltiplicatore RGB importato: isola una causa, ma non basta. |
| `surface` | Distribuzione continua e dettaglio in metri: soluzione consegnata. |

Durante le iterazioni sono state scartate una roccia troppo chiara e una modulazione macroscopica troppo simile a mimetismo. Nessun ingrandimento artificiale della colormap e nessuna sfocatura globale: `depth_blur` resta 0.

## Implementazione

- `resources/terrain/garda_surface.gdshader`: mantiene il contratto geometrico/geomorphing e i buchi di Terrain3D 1.0.2. Normali interpolate a tutte le distanze; coordinate materiali in metri; proiezione triplanare; campionamento stocastico con gradienti espliciti e mipmap.
- Dettaglio fine a 4 m, intermedio a 72 m (25,2 m per la scansione erba/pietre), macrovariazione a 4,5 km e 37 km. Il contributo fine sfuma secondo l'impronta del pixel senza riscalare le UV con la distanza. La luminanza normalizzata limita il cambio di palette durante la transizione.
- Erba, erba secca, roccia e neve dipendono da quota, pendenza, esposizione e rumore continuo. Soglia neve predefinita 2700 m, transizione 450 m; parametri esposti nel materiale.
- `resources/terrain/garda_surface_assets.tres`: sette slot mantenuti; sostituita soltanto la vecchia roccia con Marble Cliff 01 2K, CC0. [Provenienza, packing e hash](../textures/terrain/garda/SOURCES.md).
- F6 resta utilizzabile: la modalità 6 segnala che il blending continuo è già attivo; la 7 rimane una prova di blur. Nessuna modifica al percorso dei vecchi shader nelle altre mappe.

**Compromesso esplicito:** il materiale non usa la colormap né i pesi dei biomi WC. Dipingere i materiali nella control map non cambia questa superficie; i buchi restano rispettati. Sono regole procedurali, non una ricostruzione geografica di boschi, campi, spiagge o stagioni. Le maschere originali e gli asset precedenti restano disponibili. La distribuzione desiderata può essere affinata in seguito con dati di copertura del suolo, senza cambiare il DEM.

## Verifiche e limiti

- `tools/garda_surface_review.gd -- --check`: **PASS**, marker esplicito, exit 0, nessun errore di script/shader. Controlla risorse, mipmap 2K, sette slot, 256 regioni, estensione 250 km, invarianza delle quote campionate durante gli scambi di materiale e il vero chiamante F6.
- Esecuzione grafica finale: **PASS**, 40 catture e prove F6 incluse. Restano warning di deprecazione dell'interpolazione fisica e RID al teardown; non vengono confusi con un errore di compilazione shader.
- Via Godot AI MCP: scena Garda aperta; freeroam e tutorial lanciati con `autosave=false`, entrambi confermati `live`, shader effettivo e log della corsa verificati. Nessun errore corrente di boot/script/shader. I precedenti errori editor su asset stradali mancanti non appartenevano a queste corse. Run di prova fermate.
- Nel freeroam sono state ispezionate anche cinque pose di avvicinamento al versante, con nuvole disabilitate solo in memoria. Il primo tentativo di codice diagnostico MCP aveva un errore di indentazione: riavviato e ripetuto correttamente, senza modificare file del gioco. Le pose confermano l'integrazione visiva, **non** una certificazione di stabilità temporale in tutto il volo.
- `tests/garda_final_import_check.gd`: **NON PASSA**, confronto hash heightmap alla riga 69. Riprodotto anche con la scena precedente estratta da Git. Nessun hash/manifest o dato altimetrico è stato riscritto per nascondere il problema.
- `tests/garda_overlay_check.gd`: completa gli assert e stampa `GARDA MAP INTEGRATION PASS`, ma segnala `1 resources still in use at exit`; pertanto **non è un pass pulito**. Identico risultato con scena/materiale precedenti e copie dei livelli riferite a quella scena.
- Restano da valutare in un volo prolungato lo shimmering, le transizioni LOD su più percorsi e le prestazioni su GPU meno potenti. Il materiale non aggiunge geometria fine: a terra il DEM conserva i suoi limiti di risoluzione.

## Costo GPU indicativo

Godot 4.7.1, Terrain3D 1.0.2, Forward+/D3D12, Radeon RX 9070 XT. Mediane GPU del **viewport completo**, 120 campioni dopo 60 frame di assestamento, singola sequenza senza nuvole/TAA. Non sono FPS di freeroam né tempi isolati dello shader; i frame p95 erano più variabili delle mediane, quindi non si deduce una garanzia di fluidità.

| Camera | Prima, ms | Dopo, ms | Differenza |
| --- | ---: | ---: | ---: |
| alpine_near | 2.886 | 3.080 | +6.7% |
| alpine_mid | 2.535 | 2.346 | −7.5% |
| alpine_far | 1.808 | 1.417 | −21.6% |
| garda | 1.807 | 1.730 | −4.3% |
| lowland | 2.663 | 2.715 | +2.0% |
| ground | 2.388 | 2.914 | +22.0% |
| cruise | 2.306 | 2.599 | +12.7% |
| region_seam | 3.000 | 3.565 | +18.8% |

## Ripetere il confronto

Eseguire dalla radice, sostituendo `godot` con l'eseguibile locale. Per automazione usare un supervisore con scadenza di 120 s per il check / 240 s per la suite grafica e terminazione del solo albero di processi avviato dal test. Il marker senza exit 0 e log privi di errori non basta.

```sh
godot --headless --path . --script res://tools/garda_surface_review.gd -- --check
godot --path . --script res://tools/garda_surface_review.gd -- --variants=baseline,native,filtered,no_color,surface --out=res://subagent-artifacts/garda-surface/review
```

Per restringere il confronto: `--views=ground,alpine_near,garda`. Il fixture `tools/fixtures/garda_legacy_material.tres` conserva i parametri del materiale precedente. Il tool non salva scene o Terrain3DData; mantiene le descrizioni texture soltanto nel processo di prova per consentire gli scambi A/B.
