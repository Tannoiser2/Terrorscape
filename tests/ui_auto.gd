## Collaudo dell'interfaccia: partite complete in cui il lato "umano" decide passando dall'interfaccia
## (costruzione delle richieste, pannelli, _decidi), con le scelte prese dall'IA.
## Uso: xvfb-run godot --path . --rendering-driver opengl3 --script tests/ui_auto.gd -- <ruolo S|K> <partite>
extends SceneTree

var main: Node
var finite := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var ruolo := a[0] if a.size() > 0 else "S"
	var n := int(a[1]) if a.size() > 1 else 2
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	var killers := ["macellaio", "spettro", "assassino"]
	var pool := ["anna", "william", "sophia", "marco", "johnson", "george", "ophelia", "dylan", "caleb"]
	for g in n:
		pool.shuffle()
		main._prep = {"ruolo": ruolo, "killer": killers[g % 3], "sopr": pool.slice(0, 3), "mappa": "villa"}
		main.velocita = 0.01
		main._avvia_locale()
		var mio := IA.new(main.partita, ruolo, g + 999)
		var turni := 0
		while main.partita != null and main.partita.s["vincitore"] == "" and turni < 4000:
			turni += 1
			await process_frame
			var p: Partita = main.partita
			if not p.attesa.is_empty() and p.attesa["lato"] == ruolo:
				var req: Dictionary = p.attesa["req"]
				# esercita l'interfaccia della richiesta
				main._mostra_richiesta()
				main._aggiorna_hud()
				var d: Dictionary = mio.decidi(req)
				# per i movimenti dei Sopravvissuti passa anche dalla selezione sulla plancia
				if req["tipo"] == "azione_s" and d.get("a", "") == "muovi":
					main._scegli_movimento(int(d["i"]), "muovi", 2)
					main.plancia._scelta_luoghi = [d["percorso"][-1]]
					main._su_luogo(d["percorso"][-1])
				else:
					main._decidi(d)
		var p2: Partita = main.partita
		print("partita %d (%s, %s vs %s): %s — %s al turno %d" % [g, ruolo, p2.s["killer"]["id"], str(main._prep["sopr"]), p2.s["vincitore"], p2.s["motivo"], p2.s["turno"]])
		await create_timer(2.0).timeout
	quit()
