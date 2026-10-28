extends SceneTree
func _initialize() -> void:
	for f in ["res://scripts/dati.gd", "res://scripts/regole.gd", "res://scripts/ia.gd", "res://scripts/plancia3d.gd", "res://scripts/rete.gd", "res://scripts/main.gd"]:
		var s = load(f)
		print(f, " -> ", "ok" if s != null and s.can_instantiate() else "ERRORE")
	quit()
