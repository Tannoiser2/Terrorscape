## Collaudo online: due copie del gioco contro un finto Firebase (tests/firebase_mock.py).
## Uso: FR_DB_URL=... godot --headless --path . --script tests/online_auto.gd -- host|ospite <file_codice> [seme]
extends SceneTree

var main: Node

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var ruolo := a[0]
	var file_codice := a[1]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	main.nome_giocatore = "Host" if ruolo == "host" else "Ospite"
	if ruolo == "host":
		main._prep = {"ruolo": "K", "killer": OS.get_environment("TS_KILLER") if OS.get_environment("TS_KILLER") != "" else "assassino", "sopr": ["anna", "george", "caleb"], "mappa": OS.get_environment("TS_MAPPA") if OS.get_environment("TS_MAPPA") != "" else "villa"}
		main._crea_stanza()
		while main.codice == "":
			await create_timer(0.3).timeout
		var f := FileAccess.open(file_codice, FileAccess.WRITE)
		f.store_string(main.codice)
		f.close()
		print("stanza ", main.codice)
	else:
		var codice := ""
		while codice == "":
			await create_timer(0.5).timeout
			if FileAccess.file_exists(file_codice):
				codice = FileAccess.get_file_as_string(file_codice).strip_edges()
		main._entra_stanza(codice)
	while main.partita == null:
		await create_timer(0.3).timeout
	print(ruolo, ": partita avviata, io sono ", main.mio_lato)
	var mio := IA.new(main.partita, main.mio_lato, 4242 if ruolo == "host" else 777)
	var giri := 0
	while main.partita.s["vincitore"] == "" and giri < 20000:
		giri += 1
		await create_timer(0.05).timeout
		var p: Partita = main.partita
		if not p.attesa.is_empty() and p.attesa["lato"] == main.mio_lato and main._richiesta_mostrata == p.decisioni:
			var n := p.decisioni
			print("test: decido ", n, " ", p.attesa["req"]["tipo"])
			var dd: Dictionary = mio.decidi(p.attesa["req"])
			print("test: deciso ", dd)
			main._decidi(dd)
			while p.decisioni == n and not p.attesa.is_empty():
				await create_timer(0.05).timeout
	var s: Dictionary = main.partita.s
	print("%s FINE: vincitore=%s turno=%d log=%d decisioni=%d chiavi=%d radio=%d" % [ruolo, s["vincitore"], s["turno"], s["log"].size(), main.partita.decisioni, s["chiavi"], s["riparazione"]])
	quit()
