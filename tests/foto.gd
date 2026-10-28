## Screenshot automatici dell'interfaccia: menu, preparazione, partita come Sopravvissuti e come Killer.
## Uso: xvfb-run godot --path . --rendering-driver opengl3 --script tests/foto.gd -- <cartella> <scenario>
extends SceneTree

var main: Node
var out := "/tmp/foto"

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	var scen := a[1] if a.size() > 1 else "menu"
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _attendi(1.0)
	match scen:
		"menu":
			await _foto("menu")
			main._preparazione(false)
			await _attendi(0.5)
			await _foto("preparazione")
		"sopr":
			main._prep = {"ruolo": "S", "killer": "macellaio", "sopr": ["anna", "william", "marco"], "mappa": "villa"}
			main._avvia_locale()
			await _attendi(2.0)
			await _foto("sopr_turno1")
			main._scegli_movimento(0, "muovi", 2)
			await _attendi(0.5)
			await _foto("sopr_muovi")
		"killer":
			main._prep = {"ruolo": "K", "killer": "spettro", "sopr": ["sophia", "johnson", "george"], "mappa": "villa"}
			main.velocita = 0.2
			main._avvia_locale()
			await _attendi(8.0)
			await _foto("killer_turno")
		"osserva":
			main._prep = {"ruolo": "O", "killer": "assassino", "sopr": ["caleb", "ophelia", "dylan"], "mappa": "villa"}
			main.velocita = 0.15
			main._avvia_locale()
			await _attendi(25.0)
			await _foto("osserva")
	quit()

func _attendi(t: float) -> void:
	await create_timer(t).timeout

func _foto(nome: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out + "/" + nome + ".png")
	print("foto ", nome)
