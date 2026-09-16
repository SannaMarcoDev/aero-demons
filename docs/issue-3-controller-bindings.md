# Issue #3 — rimappatura controller applicata e persistente

Implementazione e prova fisica completate; chiusura della issue e commit
richiesti esplicitamente dall'utente. Nessun push richiesto.
La UI di rimappatura (#4), prompt (#6) e disconnessione non sono inclusi.

## Implementazione

- `scripts/ui/controller_bindings.gd`: profilo di pulsanti e semiasse positivo/negativo,
  deadzone per azione, default derivati da `project.godot`, validazione prima
  dell'applicazione. Per spostare/invertire una coppia analogica si inviano
  entrambe le azioni nello stesso profilo. Trigger Xbox: solo semiasse positivo.
- Conflitti vietati nello stesso contesto (UI oppure volo), consentiti fra i due.
  Profili incompleti ereditano le azioni mancanti; profili invalidi o conflittuali
  caricati da disco ricadono sui default come insieme, evitando conflitti
  introdotti da un ripristino parziale. Un tentativo di salvataggio invalido
  restituisce `ERR_INVALID_DATA` senza cambiare file o InputMap.
- Vengono sostituiti solo eventi joypad, con device `-1` (anche per direzioni UI,
  prima vincolate a device 0). Gli eventi tastiera/mouse restano invariati.
  La rimozione di un binding tenuto premuto rilascia l'azione; riapplicare
  un profilo immutato non interrompe un comando tenuto premuto.
- `settings_manager.gd`: carica `controls/bindings` da `settings.cfg`, applica
  il profilo dai percorsi esistenti (`apply_settings`, `ensure_controls_loaded`).
  Scrittura dedicata mediante file temporaneo adiacente e rename dopo successo,
  senza riscrivere audio, video, inversione, sensibilità o sezioni estranee.
  Il normale salvataggio opzioni conserva la sezione binding già presente.
- Nessun cambiamento a `PlayerFlight`, camera o IA: leggono già azioni InputMap;
  l'IA compila i propri campi prima del volo condiviso, senza leggere il joypad.

API per il prossimo incremento (gestire sempre il codice Error):

```gdscript
var settings := SettingsManager.load_settings()
var profile: Dictionary = settings.controls_bindings.duplicate(true)
profile.fire_gun.events = [{"button": JOY_BUTTON_B}]
var error := SettingsManager.save_controller_bindings(profile)
# Reset del solo profilo controller:
# error = SettingsManager.reset_controller_bindings()
```

Dopo un salvataggio riuscito la futura UI deve ricaricare il proprio snapshot
settings prima di riapplicarlo: non conservare una copia precedente del profilo.
Le API di salvataggio/reset accettano un percorso opzionale per i test isolati.

## Verifiche eseguite

Godot 4.7.1. Supervisor Node esterno al repository: deadline di 60 s per processo,
cleanup su timeout/errore con `taskkill /PID <pid-spawnato> /T /F`, verifica marker
esplicito ed exit 0. Nessun processo ha superato la deadline.

```text
godot --headless --path . res://tests/controller_bindings_check.tscn -- --write-profile <nuovo-percorso-assoluto.cfg>
godot --headless --path . res://tests/controller_bindings_check.tscn -- --read-profile <stesso-percorso.cfg>
godot --headless --path . --script res://tests/enemy_fighter_check.gd
godot --headless --path . --script res://tests/flight_inertia_check.gd
```

- Nuovo check: `PASS: controller bindings write` e `PASS: controller bindings restart`,
  in processi separati, exit 0, nessun errore script/assert. Verifica la lettura reale
  `_update_controls` del giocatore tramite una sonda priva del tick di volo:
  X non spara più, B sì; coppie assi invertite/spostate, forza analogica/deadzone,
  trigger scambiati, reset anche a comando premuto, persistenza e conservazione
  delle altre impostazioni. Controlla inoltre file assente, profilo invalido,
  conflitti, errori di scrittura e INI corrotto senza sovrascriverlo.
- Il caso INI sintatticamente corrotto viene eseguito solo headless, con stampa
  degli errori nativi disattivata esclusivamente durante le due chiamate negative;
  ripristinata prima delle assert. Il primo giro MCP aveva mostrato i due errori
  intenzionali del ConfigFile nel debugger; il giro finale non li genera.
- Check IA: marker `Dogfight check passed`, exit 0, nessun errore script/assert.
- Check inerzia: marker `Flight inertia checks passed`, exit 0, nessun errore
  script/assert, ma warning ObjectDB e una risorsa ancora in uso alla chiusura.
  Anche un wrapper temporaneo che ferma la musica prima del check conserva quel
  residuo: non è un'uscita pulita, non corretto modificando sistemi fuori scope.
- Warning UID F/A-26 con fallback a percorso presenti nei test, già noti dalla #2.

## Verifiche MCP

Tutte le scene avviate con `autosave=false`, poi fermate:

| Scena | Run | Riscontro |
|---|---|---|
| Menu principale | `r2310245-3` | `live`, nessun nuovo errore gioco/editor |
| Tutorial Garda, avvio diretto | `r2356488-4` | `live` dopo caricamento; nessun nuovo errore gioco/editor |
| Nuova scena check, giro finale | `r2511546-6` | `live`, marker PASS, nessun nuovo errore |

L'apertura del tutorial ha inizialmente superato il timeout MCP; il successivo
stato ha confermato la scena aperta. Anche il run è diventato live dopo il primo
riscontro di caricamento: nessun retry sovrapposto.

Nella sonda finale: eventi joypad inviati via MCP, B premuto →
`PlayerFlight.gun_trigger=true`, B rilasciato e X premuto → `false`,
osservati nel testo runtime. Questa è una prova sintetica, non fisica.
Restano errori stradali trattenuti precedenti al run e warning di script esistenti;
non sono stati confusi con errori della modifica né corretti fuori perimetro.

## Limiti e prova fisica

Prova fisica Xbox Series USB confermata dall'utente: tenendo B la sonda mostra
`gun_trigger=true`; rilasciando B e premendo X resta `false`.
Il run utente `r2940150-7` riporta anche il marker PASS ed è già fermato.
Per ripetere la prova senza toccare il profilo reale: aprire
`tests/controller_bindings_check.tscn` e avviare la scena (F6); dopo PASS,
tenere B e verificare `gun_trigger=true`, poi X e verificare `false`.
La sonda usa e cancella un file temporaneo; chiudere il run al termine.
La persistenza è verificata nei due processi headless, non tramite UI (ancora assente).
L'avvio del tutorial verifica integrazione, non un nuovo playtest completo.

Controllo finale: `git diff --check` senza errori; hash SHA-256 di `settings.cfg`
invariato prima/dopo le verifiche, `graphics.cfg` rimasto assente. Preservate le
modifiche utente a `docs/demo-playable-plan.md` e `tests/utah_levels_check.gd.uid`.
Nessuna modifica a terreno, maschere o asset importati.
