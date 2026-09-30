# Controlli storici non eseguibili

`controller_remap_check.gd` e `controller_ui_flow_check.gd` dipendono dalla classe
`OptionsPanel` e dalla precedente interfaccia opzioni. Classe e scena non erano
più presenti prima della riorganizzazione: entrambi davano già errore di parsing.

Sono conservati come riferimento, non contati tra i controlli superati.
`.gdignore` evita che Godot importi questi script obsoleti durante l'uso normale
dell'editor; eseguirli esplicitamente non risolve le dipendenze mancanti.

Per riattivarli occorre adattarli alla UI corrente e spostarli nel dominio
appropriato. Il check backend dei binding resta in `tests/input/`.
