## La plancia 3D: il tabellone del lato che gioca (Killer o Sopravvissuti), le sagome dei personaggi
## e i segnalini. Si gira trascinando col tasto destro (o con due dita), si avvicina con la rotella.
class_name Plancia3D
extends Node3D

signal luogo_cliccato(l: String)
signal porta_cliccata(p: String)

const W := 20.0          # larghezza del tabellone in unità 3D
const H := 10.0

var p: Partita
var lato := "S"          # di chi è la vista
var cam: Camera3D
var perno: Node3D
var tabellone: MeshInstance3D
var _mat_tab: StandardMaterial3D
var sagome := {}         # chiave -> Node3D ("k", "s0", "s1", "s2")
var segnalini: Node3D
var evidenze: Node3D
var _scelta_luoghi := []  # luoghi cliccabili ora
var _scelta_porte := []   # porte cliccabili ora
var _yaw := 0.0
var _pitch := -60.0
var _dist := 15.5
var _trascina := false
var _tocchi := {}
var _tex_cache := {}
var fantasmi := {}        # per il Killer: ultime posizioni note dei Sopravvissuti {i: {luogo, turno}}
var luce_k: OmniLight3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.015, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.45, 0.5)
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color(0.08, 0.03, 0.04)
	e.fog_density = 0.012
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sole := DirectionalLight3D.new()
	sole.rotation_degrees = Vector3(-62, 25, 0)
	sole.light_energy = 0.9
	sole.light_color = Color(1.0, 0.92, 0.85)
	sole.shadow_enabled = true
	add_child(sole)
	luce_k = OmniLight3D.new()
	luce_k.light_color = Color(1.0, 0.15, 0.1)
	luce_k.light_energy = 2.5
	luce_k.omni_range = 4.0
	luce_k.position = Vector3(0, 1.5, 0)
	add_child(luce_k)
	# tavolo
	var tav := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	tav.mesh = pm
	var mt := StandardMaterial3D.new()
	mt.albedo_texture = load("res://assets/varie/tavolo.webp")
	mt.uv1_scale = Vector3(6, 6, 1)
	mt.albedo_color = Color(0.55, 0.4, 0.42)
	tav.material_override = mt
	tav.position.y = -0.06
	add_child(tav)
	# tabellone: il cartone (un parallelepipedo scuro) con sopra la mappa
	var cartone := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W + 0.1, 0.12, H + 0.1)
	cartone.mesh = bm
	var mc := StandardMaterial3D.new()
	mc.albedo_color = Color(0.08, 0.06, 0.06)
	cartone.material_override = mc
	cartone.position.y = -0.065
	add_child(cartone)
	tabellone = MeshInstance3D.new()
	var plm := PlaneMesh.new()
	plm.size = Vector2(W, H)
	tabellone.mesh = plm
	_mat_tab = StandardMaterial3D.new()
	_mat_tab.roughness = 0.85
	tabellone.material_override = _mat_tab
	tabellone.position.y = 0.0
	add_child(tabellone)
	segnalini = Node3D.new()
	add_child(segnalini)
	evidenze = Node3D.new()
	add_child(evidenze)
	perno = Node3D.new()
	add_child(perno)
	cam = Camera3D.new()
	cam.fov = 50
	perno.add_child(cam)
	_aggiorna_camera()

func imposta(partita: Partita, quale_lato: String) -> void:
	p = partita
	lato = quale_lato
	var m: Dictionary = p.mappa
	var path: String = m["tabellone_k"] if lato == "K" else m["tabellone_s"]
	# "tutti": chi guarda la partita vede anche il Killer furtivo
	_mat_tab.albedo_texture = _tex(path)
	for k in sagome:
		sagome[k].queue_free()
	sagome.clear()
	fantasmi.clear()
	var kd: Dictionary = Dati.KILLER[p.s["killer"]["id"]]
	sagome["k"] = _sagoma(kd["mini"], Color(0.75, 0.05, 0.05), 1.9)
	for i in p.s["sopr"].size():
		var sd: Dictionary = Dati.SOPRAVVISSUTI[p.s["sopr"][i]["id"]]
		sagome["s%d" % i] = _sagoma("res://assets/mini/%s.webp" % p.s["sopr"][i]["id"], sd["colore"], 1.45)
	aggiorna(true)

func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]

## Da posizione sul tabellone (0..1) a coordinate 3D.
func xy3d(xy: Array, y := 0.0) -> Vector3:
	return Vector3((float(xy[0]) - 0.5) * W, y, (float(xy[1]) - 0.5) * H)

func pos_luogo(l: String) -> Vector3:
	return xy3d(p.mappa["luoghi"][l]["xy"])

func _sagoma(img: String, colore: Color, altezza: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.46
	cm.height = 0.12
	base.mesh = cm
	var mb := StandardMaterial3D.new()
	mb.albedo_color = colore
	mb.metallic = 0.3
	mb.roughness = 0.4
	mb.emission_enabled = true
	mb.emission = colore * 0.25
	base.material_override = mb
	base.position.y = 0.06
	n.add_child(base)
	var spr := Sprite3D.new()
	spr.texture = _tex(img)
	var t: Texture2D = spr.texture
	spr.pixel_size = altezza / float(t.get_height())
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.shaded = false
	spr.double_sided = true
	spr.position.y = 0.12 + altezza * 0.5
	spr.name = "img"
	n.add_child(spr)
	return n

# ---------------------------------------------------------------- camera

func _aggiorna_camera() -> void:
	perno.rotation_degrees = Vector3(_pitch, _yaw, 0)
	perno.position = Vector3(0, 0, 0.6)
	cam.position = Vector3(0, 0, _dist)
	cam.h_offset = 0.9

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			_dist = clampf(_dist - 1.0, 7.0, 26.0)
			_aggiorna_camera()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			_dist = clampf(_dist + 1.0, 7.0, 26.0)
			_aggiorna_camera()
		elif ev.button_index == MOUSE_BUTTON_RIGHT or ev.button_index == MOUSE_BUTTON_MIDDLE:
			_trascina = ev.pressed
		elif ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			_clic(ev.position)
	elif ev is InputEventMouseMotion and _trascina:
		_yaw -= ev.relative.x * 0.3
		_pitch = clampf(_pitch - ev.relative.y * 0.3, -88.0, -18.0)
		_aggiorna_camera()
	elif ev is InputEventScreenTouch:
		if ev.pressed:
			_tocchi[ev.index] = ev.position
		else:
			_tocchi.erase(ev.index)
	elif ev is InputEventScreenDrag and _tocchi.size() >= 2:
		_tocchi[ev.index] = ev.position
		_yaw -= ev.relative.x * 0.15
		_pitch = clampf(_pitch - ev.relative.y * 0.15, -88.0, -18.0)
		_aggiorna_camera()
	elif ev is InputEventMagnifyGesture:
		_dist = clampf(_dist / ev.factor, 7.0, 26.0)
		_aggiorna_camera()

func vista_dall_alto() -> void:
	_yaw = 0
	_pitch = -89.0
	_dist = 14.0
	_aggiorna_camera()

func vista_inclinata() -> void:
	_yaw = 0
	_pitch = -60.0
	_dist = 15.5
	_aggiorna_camera()

func _clic(pos: Vector2) -> void:
	if p == null:
		return
	var o := cam.project_ray_origin(pos)
	var d := cam.project_ray_normal(pos)
	if abs(d.y) < 0.0001:
		return
	var t := -o.y / d.y
	if t < 0:
		return
	var hit := o + d * t
	var fx := hit.x / W + 0.5
	var fy := hit.z / H + 0.5
	# porte (se se ne sta scegliendo una)
	if not _scelta_porte.is_empty():
		var best := ""
		var bd := 0.05
		for pt in _scelta_porte:
			var xy: Array = p.porta(pt.split("|")[0], pt.split("|")[1])["xy"]
			var dd := Vector2(fx - xy[0], (fy - xy[1]) * 0.5).length()
			if dd < bd:
				bd = dd
				best = pt
		if best != "":
			porta_cliccata.emit(best)
			return
	var best_l := ""
	var bdl := 0.09
	for l in p.mappa["luoghi"]:
		var xy: Array = p.mappa["luoghi"][l]["xy"]
		var dd := Vector2(fx - xy[0], (fy - xy[1]) * 0.5).length()
		if dd < bdl:
			bdl = dd
			best_l = l
	if best_l != "":
		luogo_cliccato.emit(best_l)

# ---------------------------------------------------------------- scelte evidenziate

func mostra_scelta(luoghi: Array, porte := [], colore := Color(1.0, 0.85, 0.3)) -> void:
	pulisci_scelta()
	_scelta_luoghi = luoghi.duplicate()
	_scelta_porte = porte.duplicate()
	for l in luoghi:
		var m := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.62
		tm.outer_radius = 0.78
		m.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colore
		mat.emission_enabled = true
		mat.emission = colore
		mat.emission_energy_multiplier = 2.2
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		m.position = pos_luogo(l) + Vector3(0, 0.05, 0)
		evidenze.add_child(m)
	for pt in porte:
		var ab: PackedStringArray = pt.split("|")
		var xy: Array = p.porta(ab[0], ab[1])["xy"]
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.28
		sm.height = 0.56
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.3, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(1, 0.3, 0.2)
		mat.emission_energy_multiplier = 2.5
		m.material_override = mat
		m.position = xy3d(xy, 0.35)
		evidenze.add_child(m)

## Gli anelli delle scelte pulsano piano.
func _process(_d: float) -> void:
	if evidenze == null or evidenze.get_child_count() == 0:
		return
	var f := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.006)
	for c in evidenze.get_children():
		if c is MeshInstance3D and c.mesh is TorusMesh:
			c.scale = Vector3(f, 1, f)

func pulisci_scelta() -> void:
	_scelta_luoghi.clear()
	_scelta_porte.clear()
	for c in evidenze.get_children():
		c.queue_free()

# ---------------------------------------------------------------- disegno dello stato

func aggiorna(subito := false) -> void:
	if p == null:
		return
	# raggruppa chi sta nello stesso luogo
	var gruppi := {}
	var kpos := p.posizione_killer_per(lato)
	var k_vis := kpos != ""
	if k_vis:
		gruppi[kpos] = gruppi.get(kpos, []) + ["k"]
	var mostra_s := lato == "S" or lato == "tutti"
	for i in p.s["sopr"].size():
		var key := "s%d" % i
		var sp: Dictionary = p.s["sopr"][i]
		var vis: bool = mostra_s and sp["vivo"]
		if lato == "K" and sp["vivo"] and fantasmi.has(i):
			vis = true
		if not sp["vivo"]:
			vis = true
		sagome[key].visible = vis
		if vis:
			var l: String = sp["pos"]
			if lato == "K" and sp["vivo"]:
				l = fantasmi[i]["luogo"]
			gruppi[l] = gruppi.get(l, []) + [key]
		_trasparenza(key, 1.0 if (mostra_s or not sp["vivo"]) else 0.55)
		var spr: Sprite3D = sagome[key].get_node("img")
		spr.rotation_degrees.z = 0.0 if sp["vivo"] else 90.0
		spr.modulate = Color(1, 1, 1, spr.modulate.a) if sp["vivo"] else Color(0.5, 0.2, 0.2, 1)
	sagome["k"].visible = k_vis
	for l in gruppi:
		var lst: Array = gruppi[l]
		var centro := pos_luogo(l)
		for n in lst.size():
			var off := Vector3.ZERO
			if lst.size() > 1:
				var ang := TAU * n / lst.size() - PI / 2
				off = Vector3(cos(ang), 0, sin(ang) * 0.8) * 0.62
			var dest := centro + off
			var nodo: Node3D = sagome[lst[n]]
			if subito or nodo.position.distance_to(dest) > 12.0:
				nodo.position = dest
			elif nodo.position.distance_to(dest) > 0.01:
				var tw := nodo.create_tween()
				tw.tween_property(nodo, "position", dest + Vector3(0, 0.6, 0), 0.18)
				tw.tween_property(nodo, "position", dest, 0.18)
	if k_vis:
		luce_k.visible = true
		luce_k.position = pos_luogo(kpos) + Vector3(0, 1.6, 0)
	else:
		luce_k.visible = false
	_segnalini()

func _trasparenza(key: String, a: float) -> void:
	var spr: Sprite3D = sagome[key].get_node("img")
	spr.modulate.a = a
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD if a >= 1.0 else SpriteBase3D.ALPHA_CUT_DISABLED

func _gettone(pos: Vector3, colore: Color, testo: String, r := 0.32) -> Node3D:
	var n := Node3D.new()
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.08
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colore
	mat.emission_enabled = true
	mat.emission = colore * 0.6
	m.material_override = mat
	n.add_child(m)
	if testo != "":
		var lb := Label3D.new()
		lb.text = testo
		lb.font = load("res://assets/font/Creepster-Regular.ttf")
		lb.font_size = 64
		lb.pixel_size = 0.006
		lb.outline_size = 12
		lb.modulate = Color(1, 0.95, 0.85)
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.position.y = 0.35
		lb.no_depth_test = true
		n.add_child(lb)
	n.position = pos
	segnalini.add_child(n)
	return n

func _segnalini() -> void:
	for c in segnalini.get_children():
		c.queue_free()
	# blocchi sulle porte
	for b in p.s["blocchi"]:
		var ab: PackedStringArray = b.split("|")
		var xy: Array = p.porta(ab[0], ab[1])["xy"]
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var pa := xy3d(p.mappa["luoghi"][ab[0]]["xy"])
		var pb := xy3d(p.mappa["luoghi"][ab[1]]["xy"])
		bm.size = Vector3(0.9, 0.35, 0.28)
		m.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.28, 0.16)
		mat.roughness = 0.9
		m.material_override = mat
		m.position = xy3d(xy, 0.18)
		var dir := pb - pa
		m.rotation.y = atan2(dir.x, dir.z)
		segnalini.add_child(m)
		var x := Label3D.new()
		x.text = "X"
		x.font_size = 48
		x.pixel_size = 0.008
		x.modulate = Color(1, 0.2, 0.15)
		x.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		x.position = xy3d(xy, 0.55)
		x.no_depth_test = true
		segnalini.add_child(x)
	# rumori (il Killer li vede a fine turno dei Sopravvissuti; i Sopravvissuti li vedono subito)
	var rum: Array = p.s["rumori"] if (lato == "S" or p.s["fase"] == "K") else p.s["rumori_prec"]
	if lato == "K" and p.s["fase"] == "S":
		rum = []
	for l in rum:
		_gettone(pos_luogo(l) + Vector3(0.75, 0.05, -0.45), Color(0.85, 0.1, 0.05), "!", 0.26)
	if p.s["petardo"] != "" and (lato == "S" or p.s["fase"] == "K"):
		_gettone(pos_luogo(p.s["petardo"]) + Vector3(-0.75, 0.05, -0.45), Color(1, 0.6, 0.1), "BUM", 0.32)
	# trappola (la vedono solo i Sopravvissuti)
	if p.s["trappola"] != "" and lato == "S":
		_gettone(pos_luogo(p.s["trappola"]) + Vector3(0.0, 0.05, 0.7), Color(0.5, 0.5, 0.55), "T", 0.26)
	# Killer furtivo: i Sopravvissuti vedono il segnalino dove è sparito
	if p.s["killer"]["furtivo"] and lato == "S":
		_gettone(pos_luogo(p.s["killer"]["vista"]) + Vector3(0, 0.05, 0), Color(0.35, 0.1, 0.45), "?", 0.45)
	# per il Killer: i luoghi rivelati di recente
	if lato == "K":
		for i in fantasmi:
			if p.s["sopr"][i]["vivo"]:
				var eta: int = p.s["turno"] - int(fantasmi[i]["turno"])
				var lb := Label3D.new()
				lb.text = "%s\n%s" % [p.nome_s(i), "ora" if eta <= 0 else ("%d turni fa" % eta if eta > 1 else "1 turno fa")]
				lb.font_size = 40
				lb.pixel_size = 0.006
				lb.outline_size = 10
				lb.modulate = Color(1, 0.9, 0.7)
				lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lb.no_depth_test = true
				lb.position = sagome["s%d" % i].position + Vector3(0, 2.0, 0)
				segnalini.add_child(lb)

## Il Killer annota dove ha visto un Sopravvissuto.
func annota(i: int, l: String) -> void:
	fantasmi[i] = {"luogo": l, "turno": p.s["turno"]}
