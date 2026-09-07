# Aero Demons Developer Tooling (`tools/dev`)

Piccolo runner Node.js stdlib per la validazione automatica dei test headless e l'audit statico delle risorse.

## Requisiti
- Node.js 18+ (nessuna dipendenza npm, nessun `package.json`).
- Godot 4.3+ (raggiungibile via PATH, variabile d'ambiente `GODOT_BIN` o opzione `--godot`).

## Comandi

### 1. Validazione Test Headless
Esegue l'import headless del progetto e, in sequenza, tutti i test `scripts/tests/*_check.gd`:
```bash
node tools/dev/validate.mjs
```

Opzioni:
```bash
# Specifica percorso binario Godot (ha precedenza su GODOT_BIN e PATH)
node tools/dev/validate.mjs --godot /path/to/godot

# Salta l'import editor quando un addon/vendor blocca l'editor headless
node tools/dev/validate.mjs --skip-import

# Timeout per singolo test in millisecondi (default: 45000ms)
node tools/dev/validate.mjs --timeout 60000
```

Flusso di esecuzione:
1. **Import headless**: `godot --headless --editor --import --quit --path <REPO_ROOT>` (timeout 120s).
2. **Test sequenziali**: `godot --headless --path <REPO_ROOT> --script scripts/tests/<test_name>_check.gd` (timeout 45s ciascuno).
3. **Rilevamento errori**: fallimento se il processo fallisce lo spawn, va in timeout, restituisce status != 0, oppure se nei log compaiono pattern `SCRIPT ERROR:`, `ERROR:` o `FAIL:`.
4. **Log temp**: ogni fase scrive lo stream completo stdout/stderr in una directory temporanea di sistema (`os.tmpdir()`), stampando i percorsi a video.

### 2. Benchmark targeting
Misura il costo della query completa TargetLock con 256 target sintetici, senza avviare la scena di gioco:
```bash
godot --headless --path . --script scripts/tests/targeting_benchmark.gd
```

La query era circa **4326 us** per iterazione prima dell'ottimizzazione; ora è circa **0,65–0,72 ms** sullo stesso ambiente (**0,14 us** con snapshot caldo). Il percorso runtime riusa inoltre uno snapshot per **15 Hz** e il fuoco forza un refresh.

### 3. Audit Statico Read-Only (`--audit`)
Ispezione statica non distruttiva del repository:
```bash
node tools/dev/validate.mjs --audit
```

Include:
- Elenco file tracciati e untracked non ignorati da git (`git ls-files --cached --others --exclude-standard -z`).
- Report file grandi (>= 5 MB) ordinati per dimensione decrescente.
- Riferimenti letterali completi tra virgolette `res://...` in `.gd`, `.tscn`, `.tres` e `project.godot` (supporta spazi nei percorsi).
- Distinzione tra riferimenti mancanti del progetto attivo, warning per percorsi dinamici (`%`, `{`, `+`), commenti (`#`, `;`), demo (`demo/`) e vendor (`addons/`).

## Limiti
- L'audit statico non esegue AST dinamico GDScript: i percorsi costruiti a runtime vengono classificati come warning dinamici.
- L'import completo può riportare errori preesistenti di addon/vendor o di un editor Godot già aperto; `--skip-import` esegue comunque tutti i test headless.
- Il runner non esegue fork background non monitorati ed è progettato per ambienti CI e script headless.
