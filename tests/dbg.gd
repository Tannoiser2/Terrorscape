extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var p := Partita.new()
	p.veloce = true
	root.add_child(p)
	p.prepara({"mappa": args[1], "killer": args[0], "sopravvissuti": ["anna", "marco", "george"], "seme": 3})
	var ia_k := IA.new(p, "K", 100)
	var ia_s := IA.new(p, "S", 200)
	var n := [0]
	p.richiesta.connect(func(lato, req):
		n[0] += 1
		var d: Dictionary = ia_k.decidi(req) if lato == "K" else ia_s.decidi(req)
		if n[0] % 1 == 0 and n[0] > int(args[2]):
			print(n[0], " ", lato, " ", req.get("tipo"), " ", req.get("titolo", ""), " -> ", d)
		if n[0] > int(args[2]) + 60:
			quit()
		p.rispondi(d))
	p.evento.connect(func(e): if n[0] > int(args[2]): print("   ev: ", e["t"]))
	await p.gioca()
	print("FINE ", p.s["vincitore"], " ", p.s["motivo"], " turno ", p.s["turno"])
	quit()
