## Simulazione: IA contro IA, molte partite, per collaudare il motore.
## Uso: godot --headless --path . --script tests/sim.gd -- [partite] [killer]
extends SceneTree

var vittorie := {"K": 0, "S": 0}
var motivi := {}
var turni_tot := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 20
	var killers: Array = Dati.KILLER.keys()
	if args.size() > 1 and args[1] != "tutti":
		killers = [args[1]]
	var tutti_s := Dati.SOPRAVVISSUTI.keys()
	for g in n:
		var p := Partita.new()
		p.veloce = true
		root.add_child(p)
		var rr := RandomNumberGenerator.new()
		rr.seed = g * 7919 + 13
		var scelti := []
		var pool: Array = tutti_s.duplicate()
		for k in 3:
			scelti.append(pool.pop_at(rr.randi_range(0, pool.size() - 1)))
		var killer: String = killers[g % killers.size()]
		var mappe := ["villa", "baita", "castello", "tomba"]
		var mp: String = mappe[(g / killers.size()) % 4] if args.size() < 3 else args[2]
		p.prepara({"mappa": mp, "killer": killer, "sopravvissuti": scelti, "seme": g + 1})
		var ia_k := IA.new(p, "K", g + 100)
		var ia_s := IA.new(p, "S", g + 200)
		p.richiesta.connect(func(lato, req):
			var d: Dictionary = ia_k.decidi(req) if lato == "K" else ia_s.decidi(req)
			p.rispondi(d))
		var risultato := [""]
		p.finita.connect(func(v, m): risultato[0] = v + ": " + m)
		await p.gioca()
		var v: String = p.s["vincitore"]
		vittorie[v] = vittorie.get(v, 0) + 1
		var m: String = p.s["motivo"].split(" ")[0] if v == "K" else p.s["motivo"].substr(0, 18)
		motivi[v + " " + m] = motivi.get(v + " " + m, 0) + 1
		turni_tot += p.s["turno"]
		print("partita %d [%s] %s vs %s: %s al turno %d (chiavi %d, radio %d, livello %d)" % [g, p.s["mappa"], killer, str(scelti), risultato[0], p.s["turno"],
			p.s["chiavi"], p.s["riparazione"], p.s["killer"]["livello"]])
		p.queue_free()
	print("Vittorie: ", vittorie, "  turni medi: ", float(turni_tot) / n)
	print(motivi)
	quit()
