## Terrorscape — versione digitale (uso personale).
## Menu, preparazione, interfaccia di gioco dei due ruoli, IA e gioco online.
extends Node

const F_TITOLO := preload("res://assets/font/Creepster-Regular.ttf")
const F_SC := preload("res://assets/font/IMFeENsc28P.ttf")
const F_TESTO := preload("res://assets/font/IMFeENrm28P.ttf")
const F_MACCHINA := preload("res://assets/font/SpecialElite-Regular.ttf")
const OSSO := Color("#e9dcc3")
const SANGUE := Color("#a3121b")
const SANGUE_VIVO := Color("#e0262f")
const ORO := Color("#c9a24a")
const NOTTE := Color(0.06, 0.03, 0.035, 0.9)
const NOTTE_CHIARA := Color(0.13, 0.07, 0.08, 0.92)
const VERDE := Color("#4caf6a")
const PANNELLO_W := 440

var plancia: Plancia3D
var ui: CanvasLayer
var radice: Control
var partita: Partita
var ia_k: IA
var ia_s: IA
var modo := ""             # "giocatore_s", "giocatore_k", "osserva", "online"
var mio_lato := "S"
var config := {}
var velocita := 1.0

# elementi dell'interfaccia di gioco
var hud: Control
var barra: HBoxContainer
var lbl_turno: Label
var lbl_fase: Label
var lbl_stato: RichTextLabel
var pannello: VBoxContainer
var scroll_pannello: ScrollContainer
var registro: RichTextLabel
var box_registro: PanelContainer
var richiesta_box: PanelContainer
var richiesta_titolo: Label
var richiesta_corpo: HFlowContainer
var zoom: PanelContainer
var zoom_img: TextureRect
var zoom_testo: RichTextLabel
var avviso: Label
var fine_box: Control
var _aggiorna_in_coda := false

# stato delle scelte in corso
var req_attuale := {}
var lato_attuale := ""
var sel_s := -1            # Sopravvissuto selezionato
var sel_azione := ""       # azione che aspetta un clic sulla plancia
var sel_extra := {}
var sel_carte := []        # carte scelte per un costo
var primo_luogo := ""      # Deduzione logica
var _tex_cache := {}

# online
var rete: Rete
var codice := ""
var mio_posto := -1
var nome_giocatore := "Giocatore"
var _online_attesa := false

# ================================================================ avvio

func _ready() -> void:
	plancia = Plancia3D.new()
	add_child(plancia)
	plancia.luogo_cliccato.connect(_su_luogo)
	plancia.porta_cliccata.connect(_su_porta)
	ui = CanvasLayer.new()
	add_child(ui)
	radice = Control.new()
	radice.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(radice)
	var th := Theme.new()
	th.default_font = F_TESTO
	th.default_font_size = 19
	radice.theme = th
	rete = Rete.new()
	add_child(rete)
	_carica_preferenze()
	_menu()

func _tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]

func _pulisci_radice() -> void:
	for c in radice.get_children():
		c.queue_free()
	hud = null
	fine_box = null

# ================================================================ mattoncini dell'interfaccia

func _stile(bg: Color, raggio := 8, margine := 12, bordo := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(raggio)
	sb.set_content_margin_all(margine)
	if bordo.a > 0:
		sb.set_border_width_all(2)
		sb.border_color = bordo
	return sb

func _etichetta(t: String, size := 19, col := OSSO, font: Font = null) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

## Etichetta su una sola riga (per le file di bottoni).
func _riga(t: String, size := 19, col := OSSO, font: Font = null) -> Label:
	var l := _etichetta(t, size, col, font)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _bottone(t: String, col := SANGUE, size := 19, fcol := OSSO) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_override("font", F_SC)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", fcol)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(fcol, 0.35))
	b.add_theme_stylebox_override("normal", _stile(col, 6, 8, Color(0, 0, 0, 0.5)))
	b.add_theme_stylebox_override("hover", _stile(col.lightened(0.18), 6, 8, ORO))
	b.add_theme_stylebox_override("pressed", _stile(col.darkened(0.25), 6, 8, ORO))
	b.add_theme_stylebox_override("disabled", _stile(Color(col, 0.35), 6, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_mode = Control.FOCUS_NONE
	return b

func _bottone_piccolo(t: String, col := Color(1, 1, 1, 0.1)) -> Button:
	var b := _bottone(t, col, 16)
	b.add_theme_stylebox_override("normal", _stile(col, 5, 5, Color(1, 1, 1, 0.15)))
	b.add_theme_stylebox_override("hover", _stile(col.lightened(0.2), 5, 5, ORO))
	b.add_theme_stylebox_override("pressed", _stile(col.darkened(0.2), 5, 5, ORO))
	return b

func _titolo(t: String, size := 46, col := SANGUE_VIVO) -> Label:
	var l := _etichetta(t, size, col, F_TITOLO)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 8)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l

func _pannello(bg := NOTTE, margine := 12) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _stile(bg, 10, margine, Color(0.6, 0.12, 0.12, 0.6)))
	return pc

func _immagine(path: String, w: float, h: float) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = _tex(path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(w, h)
	return tr

## Una carta oggetto: l'immagine originale se c'è, altrimenti disegnata nello stile del gioco.
func _carta_oggetto(id: String, w := 70.0) -> Control:
	var h := w * 1.5
	var path := Dati.img_oggetto(id)
	if path != "":
		var tr := _immagine(path, w, h)
		_zoomabile(tr, path, _testo_oggetto(id))
		return tr
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(w, h)
	pc.add_theme_stylebox_override("panel", _stile(Color(0.09, 0.07, 0.08), 6, 4, Color(0.55, 0.5, 0.45, 0.8)))
	var v := VBoxContainer.new()
	pc.add_child(v)
	var n := _etichetta(Dati.OGGETTI[id]["nome"], maxi(10, int(w / 6.5)), OSSO, F_SC)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(n)
	if w >= 120:
		var t := _etichetta(Dati.OGGETTI[id]["testo"], int(w / 11), Color(0.85, 0.82, 0.75), F_MACCHINA)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
	_zoomabile(pc, "", _testo_oggetto(id), id)
	return pc

func _testo_oggetto(id: String) -> String:
	var o: Dictionary = Dati.OGGETTI[id]
	return "[font_size=24][color=#e0262f]%s[/color][/font_size]\n%s" % [o["nome"], o["testo"]]

func _testo_carta_k(c: String) -> String:
	var cd: Dictionary = Dati.CARTE_KILLER[c]
	var tipo: String = partita.tipo_carta(c) if partita else cd["tipo"]
	var tipi := {"veloce": "[color=#f0a030]Veloce[/color]", "speciale": "[color=#4f8ff0]Speciale[/color]", "lenta": "[color=#4caf6a]Lenta[/color]"}
	var costo: int = cd["costo"]
	var cs := "nessun costo" if costo == 0 else ("scarta tutta la mano" if costo < 0 else "scarta %d carte" % costo)
	var att := "  [color=#b070f0]· Attacco[/color]" if cd.get("attacco", false) else ""
	return "[font_size=24][color=#e0262f]%s[/color][/font_size]\n%s%s — costo: %s\n\n%s" % [cd["nome"], tipi.get(tipo, tipo), att, cs, cd["testo"]]

## Al passaggio del mouse (o tenendo premuto) la carta si ingrandisce con il testo in italiano.
func _zoomabile(c: Control, path: String, testo: String, ogg_id := "") -> void:
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.mouse_entered.connect(func(): _mostra_zoom(path, testo, ogg_id))
	c.mouse_exited.connect(func(): if zoom: zoom.visible = false)

func _mostra_zoom(path: String, testo: String, _ogg_id := "") -> void:
	if zoom == null:
		return
	zoom_img.texture = _tex(path)
	zoom_img.visible = path != ""
	zoom_testo.text = testo
	zoom.visible = true

# ================================================================ menu

func _menu() -> void:
	_pulisci_radice()
	if partita:
		partita.queue_free()
		partita = null
	plancia.p = null
	var sfondo := TextureRect.new()
	sfondo.texture = _tex("res://assets/varie/titolo.webp")
	sfondo.set_anchors_preset(Control.PRESET_FULL_RECT)
	sfondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sfondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sfondo.modulate = Color(0.75, 0.6, 0.6)
	radice.add_child(sfondo)
	var vela := ColorRect.new()
	vela.color = Color(0, 0, 0, 0.35)
	vela.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.add_child(vela)
	var box := _pannello(Color(0.04, 0.02, 0.025, 0.86), 26)
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.offset_left = -300
	box.offset_right = 300
	box.offset_top = -430
	box.offset_bottom = -40
	radice.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	var t := _titolo("TERRORSCAPE", 64)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var sot := _etichetta("Sopravvivi alla notte. Oppure dai la caccia.", 20, OSSO, F_SC)
	sot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sot)
	var b1 := _bottone("Gioca contro il computer", SANGUE, 24)
	b1.pressed.connect(_preparazione.bind(false))
	v.add_child(b1)
	var b2 := _bottone("Gioco online (2 giocatori)", Color("#5a1520"), 24)
	b2.pressed.connect(_preparazione.bind(true))
	v.add_child(b2)
	var b3 := _bottone("Regole in breve", Color(0.2, 0.12, 0.12), 20)
	b3.pressed.connect(_regole)
	v.add_child(b3)
	var salvata: Dictionary = rete.load_session()
	if str(salvata.get("room", "")) != "":
		var b4 := _bottone("Rientra nella partita online %s" % salvata["room"], Color("#2a3a5a"), 19)
		b4.pressed.connect(func(): _rientra(str(salvata["room"])))
		v.add_child(b4)
	var nota := _etichetta("Versione digitale per uso personale. Gioco originale © Ice Makes.", 14, Color(0.7, 0.6, 0.55))
	nota.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nota)

func _regole() -> void:
	_pulisci_radice()
	var sf := ColorRect.new()
	sf.color = Color(0.03, 0.015, 0.02)
	sf.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.add_child(sf)
	var box := _pannello(NOTTE, 20)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 60
	box.offset_right = -60
	box.offset_top = 30
	box.offset_bottom = -30
	radice.add_child(box)
	var v := VBoxContainer.new()
	box.add_child(v)
	var tt := _titolo("Regole in breve", 44)
	v.add_child(tt)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_override("normal_font", F_TESTO)
	rt.add_theme_font_override("bold_font", F_SC)
	rt.add_theme_font_size_override("normal_font_size", 19)
	rt.add_theme_font_size_override("bold_font_size", 20)
	rt.text = _testo_regole()
	v.add_child(rt)
	var b := _bottone("Indietro")
	b.pressed.connect(_menu)
	v.add_child(b)

func _testo_regole() -> String:
	var t := "[b]Lo scopo[/b]\nUn Killer contro 3 Sopravvissuti intrappolati nella Villa. Il Killer vince se elimina un Sopravvissuto (due ferite). I Sopravvissuti vincono se trovano [b]5 chiavi[/b] e si radunano tutti all'uscita principale (o all'uscita nascosta con la Mappa segreta), oppure se [b]riparano la radio[/b] (5 riparazioni) e resistono 5 turni finché arrivano i soccorsi. Se il mazzo scoperta finisce prima, vince il Killer.\n\n"
	t += "[b]Il turno dei Sopravvissuti[/b]\nOgni Sopravvissuto fa [b]una azione[/b]: [MUOVI] x1-2 · togli tutta la paura · azione speciale (oggetto o abilità) · togli un blocco nel tuo luogo · ripara la radio (fa rumore; non col Killer presente; una volta per turno) · [CERCA] in un luogo con la chiave (fa rumore se trovi oggetti rumorosi). In più: azioni extra degli oggetti e scambi tra chi è nello stesso luogo. Alla fine uno di loro [b]scopre[/b] 2 carte e ne tiene una, poi il Killer viene informato dei rumori.\n\n"
	t += "[b]Il turno del Killer[/b]\nSe era furtivo riappare e [CERCA] gratis. Poi gioca quante carte [color=#f0a030]veloci[/color] vuole, poi [b]una[/b] carta [color=#4f8ff0]speciale[/color] OPPURE 2 azioni ([MUOVI] x1 o [CERCA]); se non ha incontrato nessuno può giocare una carta [color=#4caf6a]lenta[/color]. Infine pesca 3 carte (mano massima 5). Quando il mazzo finisce sale di livello.\n\n"
	t += "[b]Incontro e attacco[/b]\nSe il Killer [CERCA] nel luogo di qualcuno, lo attacca. Chi si difende tira 4 dadi meno la sua paura (facce 0, 0, 1, 1, 1, 3) e può usare un oggetto: se la difesa è almeno pari alla Forza del Killer l'attacco è respinto (e il Killer scarta 2 carte dal mazzo), altrimenti è ferito e il Killer attacca il prossimo. Dopo l'incontro i presenti possono fuggire di un passo.\n\n"
	t += "[b]Paura[/b]: con la terza paura il Sopravvissuto urla: rumore immediato e posizione rivelata. [b]Blocchi[/b]: i Sopravvissuti non passano le porte bloccate; il Killer le sfonda passandoci (ma non quando è furtivo).\n\n"
	t += "[b]I Killer[/b]\n"
	for k in Dati.KILLER:
		var kd: Dictionary = Dati.KILLER[k]
		t += "• [b]%s[/b] (Forza %d): %s\n" % [kd["nome"], kd["forza"], kd["descrizione"]]
	t += "\n[b]I Sopravvissuti[/b]\n"
	for s in Dati.SOPRAVVISSUTI:
		var sd: Dictionary = Dati.SOPRAVVISSUTI[s]
		t += "• [b]%s[/b], %s — %s: %s %s: %s\n" % [sd["nome"], sd["ruolo"], sd["abilita"][0][0], sd["abilita"][0][1], sd["abilita"][1][0], sd["abilita"][1][1]]
	t += "\n[b]Comandi[/b]: clic sui luoghi della plancia per muovere; tasto destro (o due dita) per ruotare la vista, rotella per avvicinarsi. Passa sopra una carta per leggerla."
	return t

# ================================================================ preparazione

var _prep := {"ruolo": "S", "killer": "macellaio", "sopr": ["anna", "william", "marco"], "mappa": "villa"}

func _preparazione(online: bool) -> void:
	_pulisci_radice()
	var sf := TextureRect.new()
	sf.texture = _tex("res://assets/varie/tavolo.webp")
	sf.set_anchors_preset(Control.PRESET_FULL_RECT)
	sf.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sf.stretch_mode = TextureRect.STRETCH_TILE
	sf.modulate = Color(0.45, 0.3, 0.32)
	radice.add_child(sf)
	var sc := ScrollContainer.new()
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.offset_left = 30
	sc.offset_right = -30
	sc.offset_top = 20
	sc.offset_bottom = -20
	radice.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	sc.add_child(v)
	var testa := HBoxContainer.new()
	v.add_child(testa)
	testa.add_child(_titolo("Gioco online" if online else "Nuova partita", 48))
	var spazio := Control.new()
	spazio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	testa.add_child(spazio)
	var indietro := _bottone("Menu", Color(0.2, 0.12, 0.12))
	indietro.pressed.connect(_menu)
	testa.add_child(indietro)
	# ruolo
	v.add_child(_etichetta("Chi vuoi essere?", 26, ORO, F_SC))
	var ruoli := HBoxContainer.new()
	ruoli.add_theme_constant_override("separation", 10)
	v.add_child(ruoli)
	var opzioni := [["S", "I Sopravvissuti"], ["K", "Il Killer"]]
	if not online:
		opzioni.append(["O", "Guarda il computer giocare"])
	for o in opzioni:
		var b := _bottone(o[1], SANGUE if _prep["ruolo"] == o[0] else Color(0.18, 0.1, 0.1), 21)
		b.pressed.connect(func(): _prep["ruolo"] = o[0]; _preparazione(online))
		ruoli.add_child(b)
	# mappa
	v.add_child(_etichetta("Mappa", 26, ORO, F_SC))
	var mappe := HBoxContainer.new()
	v.add_child(mappe)
	for m in Dati.MAPPE:
		var b := _bottone(Dati.MAPPE[m]["nome"], SANGUE if _prep["mappa"] == m else Color(0.18, 0.1, 0.1), 19)
		b.pressed.connect(func(): _prep["mappa"] = m; _preparazione(online))
		mappe.add_child(b)
	# Killer
	v.add_child(_etichetta("Il Killer", 26, ORO, F_SC))
	var kh := HFlowContainer.new()
	kh.add_theme_constant_override("h_separation", 12)
	v.add_child(kh)
	for k in Dati.KILLER:
		kh.add_child(_scheda_killer(k, online))
	# Sopravvissuti
	v.add_child(_etichetta("I tre Sopravvissuti (scegline 3)", 26, ORO, F_SC))
	var sh := HFlowContainer.new()
	sh.add_theme_constant_override("h_separation", 10)
	sh.add_theme_constant_override("v_separation", 10)
	v.add_child(sh)
	for s in Dati.SOPRAVVISSUTI:
		sh.add_child(_scheda_sopr(s, online))
	var casuali := _bottone_piccolo("Tre a caso")
	casuali.pressed.connect(func():
		var pool: Array = Dati.SOPRAVVISSUTI.keys()
		pool.shuffle()
		_prep["sopr"] = pool.slice(0, 3)
		_preparazione(online))
	v.add_child(casuali)
	# avvio
	var giu := HBoxContainer.new()
	giu.add_theme_constant_override("separation", 12)
	v.add_child(giu)
	if online:
		v.add_child(_etichetta("Il tuo nome", 20, OSSO, F_SC))
		var nome := LineEdit.new()
		nome.text = nome_giocatore
		nome.max_length = 20
		nome.custom_minimum_size = Vector2(300, 40)
		nome.text_changed.connect(func(t): nome_giocatore = t; _salva_preferenze())
		v.add_child(nome)
		var crea := _bottone("Crea una stanza", SANGUE, 24)
		crea.disabled = _prep["sopr"].size() != 3
		crea.pressed.connect(_crea_stanza)
		v.add_child(crea)
		v.add_child(_etichetta("…oppure entra nella stanza di un amico (decide lui Killer, Sopravvissuti e mappa):", 19))
		var riga := HBoxContainer.new()
		v.add_child(riga)
		var cod := LineEdit.new()
		cod.placeholder_text = "CODICE"
		cod.max_length = 4
		cod.custom_minimum_size = Vector2(160, 44)
		cod.add_theme_font_size_override("font_size", 26)
		riga.add_child(cod)
		var entra := _bottone("Entra", Color("#2a3a5a"), 22)
		entra.pressed.connect(func(): _entra_stanza(cod.text.strip_edges().to_upper()))
		riga.add_child(entra)
	else:
		var via := _bottone("Inizia la notte", SANGUE, 28)
		via.disabled = _prep["sopr"].size() != 3
		via.pressed.connect(_avvia_locale)
		giu.add_child(via)
		var vel := _bottone_piccolo("Velocità del computer: %s" % ("normale" if velocita == 1.0 else ("rapida" if velocita < 1.0 else "lenta")))
		vel.pressed.connect(func():
			velocita = 0.4 if velocita == 1.0 else (2.0 if velocita < 1.0 else 1.0)
			_salva_preferenze()
			_preparazione(online))
		giu.add_child(vel)

func _scheda_killer(k: String, online: bool) -> Control:
	var kd: Dictionary = Dati.KILLER[k]
	var scelto: bool = _prep["killer"] == k
	var pc := _pannello(Color(0.25, 0.04, 0.05, 0.95) if scelto else Color(0.07, 0.04, 0.05, 0.9), 10)
	pc.custom_minimum_size = Vector2(420, 0)
	var h := HBoxContainer.new()
	pc.add_child(h)
	h.add_child(_immagine(kd["mini"], 110, 150))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(_etichetta(kd["nome"], 26, SANGUE_VIVO if scelto else OSSO, F_SC))
	v.add_child(_etichetta("Forza %d" % kd["forza"], 17, ORO))
	v.add_child(_etichetta(kd["descrizione"], 16))
	var b := _bottone_piccolo("Scelto" if scelto else "Scegli")
	b.disabled = scelto
	b.pressed.connect(func(): _prep["killer"] = k; _preparazione(online))
	v.add_child(b)
	return pc

func _scheda_sopr(s: String, online: bool) -> Control:
	var sd: Dictionary = Dati.SOPRAVVISSUTI[s]
	var scelto: bool = _prep["sopr"].has(s)
	var pc := _pannello(Color(0.06, 0.12, 0.2, 0.95) if scelto else Color(0.07, 0.04, 0.05, 0.9), 8)
	pc.custom_minimum_size = Vector2(300, 0)
	var h := HBoxContainer.new()
	pc.add_child(h)
	h.add_child(_immagine("res://assets/mini/%s.webp" % s, 70, 96))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(_etichetta(sd["nome"], 20, sd["colore"].lightened(0.3) if scelto else OSSO, F_SC))
	v.add_child(_etichetta(sd["ruolo"], 15, ORO))
	var abil := _etichetta("%s · %s" % [sd["abilita"][0][0], sd["abilita"][1][0]], 14)
	v.add_child(abil)
	pc.tooltip_text = "%s: %s\n%s: %s" % [sd["abilita"][0][0], sd["abilita"][0][1], sd["abilita"][1][0], sd["abilita"][1][1]]
	pc.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _prep["sopr"].has(s):
				_prep["sopr"].erase(s)
			elif _prep["sopr"].size() < 3:
				_prep["sopr"].append(s)
			_preparazione(online))
	return pc

func _avvia_locale() -> void:
	var ruolo: String = _prep["ruolo"]
	modo = {"S": "giocatore_s", "K": "giocatore_k", "O": "osserva"}[ruolo]
	mio_lato = {"S": "S", "K": "K", "O": "S"}[ruolo]
	config = {"mappa": _prep["mappa"], "killer": _prep["killer"], "sopravvissuti": _prep["sopr"].duplicate(),
		"seme": int(Time.get_unix_time_from_system()) % 1000000}
	_avvia_partita()

# ================================================================ partita

func _avvia_partita() -> void:
	_pulisci_radice()
	if partita:
		partita.queue_free()
	partita = Partita.new()
	add_child(partita)
	partita.prepara(config)
	partita.richiesta.connect(_su_richiesta)
	partita.evento.connect(_su_evento)
	partita.cambiato.connect(_aggiorna_dopo)
	partita.finita.connect(_su_fine)
	ia_k = null
	ia_s = null
	if modo in ["giocatore_s", "osserva"]:
		ia_k = IA.new(partita, "K", config["seme"] + 11)
	if modo in ["giocatore_k", "osserva"]:
		ia_s = IA.new(partita, "S", config["seme"] + 23)
	plancia.imposta(partita, mio_lato)
	plancia.vista_inclinata()
	_costruisci_hud()
	_aggiorna_hud()
	partita.gioca()

func _ia_per(lato: String) -> IA:
	if modo == "online":
		return null
	return ia_k if lato == "K" else ia_s

func _su_richiesta(lato: String, req: Dictionary) -> void:
	req_attuale = req
	lato_attuale = lato
	sel_azione = ""
	sel_carte.clear()
	primo_luogo = ""
	plancia.pulisci_scelta()
	if modo == "online":
		_online_richiesta(lato, req)
		return
	var ia := _ia_per(lato)
	if ia != null:
		_mostra_attesa(lato)
		var ritardo := (0.55 if lato == "K" else 0.4) * velocita
		if req["tipo"] in ["costo", "scarta_mano", "si_no", "troppi_oggetti", "nota_george", "cerca_tieni"]:
			ritardo *= 0.5
		var n := partita.decisioni
		await get_tree().create_timer(ritardo).timeout
		if partita == null or partita.decisioni != n or partita.attesa.is_empty():
			return
		partita.rispondi(ia.decidi(req))
		return
	_mostra_richiesta()

func _decidi(d: Dictionary) -> void:
	plancia.pulisci_scelta()
	sel_azione = ""
	if partita == null or partita.attesa.is_empty():
		return
	if modo == "online":
		var n := partita.decisioni
		_avviso("Invio della mossa…")
		var ok := false
		for tentativo in 6:
			ok = await rete.post_decision(codice, n, d)
			if ok:
				break
			await get_tree().create_timer(1.5).timeout
		if not ok:
			_avviso("Rete non raggiungibile: riprova. (%s)" % rete.last_error)
			_mostra_richiesta()
			return
		_avviso("")
	partita.rispondi(d)

func _su_evento(e: Dictionary) -> void:
	var vis: String = e.get("vis", "tutti")
	var vede := vis == "tutti" or vis == mio_lato or modo == "osserva"
	# il Killer annota dove ha visto i Sopravvissuti
	match e.get("tipo", ""):
		"incontro":
			for i in e["trovati"]:
				plancia.annota(int(i), e["luogo"])
		"rivelato", "trabocca", "morte":
			plancia.annota(int(e["i"]), e["luogo"])
		"percepisci":
			if e["luoghi"].size() <= 2:
				for i in e["trovati"]:
					var l: String = e["luoghi"][0]
					if e["luoghi"].size() == 2 and partita.s["sopr"][int(i)]["pos"] == e["luoghi"][1]:
						l = e["luoghi"][1]
					plancia.annota(int(i), l)
	if not vede or registro == null:
		return
	var col := "#e9dcc3"
	match e.get("tipo", ""):
		"turno":
			col = "#c9a24a"
		"incontro", "morte", "ferita", "difesa_ko", "fine":
			col = "#ff4a4a"
		"difesa_ok", "cura", "radio", "chiave":
			col = "#7fdc8a"
		"paura", "trabocca", "paura_raggio":
			col = "#d08cff"
		"rumori", "rumore_s", "petardo":
			col = "#ffb070"
		"carta", "livello":
			col = "#f08070"
	var testo: String = e["t"]
	if e.get("tipo", "") == "turno":
		registro.append_text("\n[font_size=21][color=%s]%s[/color][/font_size]\n" % [col, testo])
	else:
		registro.append_text("[color=%s]• %s[/color]\n" % [col, testo])
	match e.get("tipo", ""):
		"tiro":
			_toast_dadi(e)
		"incontro", "livello", "radio", "trabocca", "riappare", "morte":
			_toast(testo, Color("#ff5050") if e["tipo"] != "radio" else VERDE)
		"chiave":
			_toast(testo, VERDE)
		"carta":
			if mio_lato == "S" or modo == "osserva":
				_toast_carta(e)

func _su_fine(vincitore: String, motivo: String) -> void:
	_aggiorna_hud()
	plancia.lato = "tutti"
	plancia.aggiorna()
	if modo == "online":
		rete.remember_room("")
	await get_tree().create_timer(1.2).timeout
	_schermata_fine(vincitore, motivo)

func _aggiorna_dopo() -> void:
	if _aggiorna_in_coda:
		return
	_aggiorna_in_coda = true
	await get_tree().process_frame
	_aggiorna_in_coda = false
	if partita == null:
		return
	plancia.aggiorna()
	_aggiorna_hud()

# ================================================================ HUD

func _costruisci_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radice.add_child(hud)
	# barra in alto
	var top := _pannello(Color(0.04, 0.02, 0.025, 0.9), 6)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 58
	hud.add_child(top)
	barra = HBoxContainer.new()
	barra.add_theme_constant_override("separation", 16)
	top.add_child(barra)
	var logo := _etichetta("TERRORSCAPE", 30, SANGUE_VIVO, F_TITOLO)
	logo.autowrap_mode = TextServer.AUTOWRAP_OFF
	barra.add_child(logo)
	lbl_turno = _etichetta("", 22, ORO, F_SC)
	lbl_turno.autowrap_mode = TextServer.AUTOWRAP_OFF
	barra.add_child(lbl_turno)
	lbl_fase = _etichetta("", 20, OSSO, F_SC)
	lbl_fase.autowrap_mode = TextServer.AUTOWRAP_OFF
	barra.add_child(lbl_fase)
	lbl_stato = RichTextLabel.new()
	lbl_stato.bbcode_enabled = true
	lbl_stato.fit_content = true
	lbl_stato.scroll_active = false
	lbl_stato.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl_stato.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_stato.add_theme_font_override("normal_font", F_SC)
	lbl_stato.add_theme_font_size_override("normal_font_size", 19)
	barra.add_child(lbl_stato)
	var bv := _bottone_piccolo("Vista")
	bv.tooltip_text = "Passa dalla vista inclinata a quella dall'alto"
	bv.pressed.connect(func():
		if plancia._pitch < -80: plancia.vista_inclinata()
		else: plancia.vista_dall_alto())
	barra.add_child(bv)
	var br := _bottone_piccolo("Registro")
	br.pressed.connect(func(): box_registro.visible = not box_registro.visible)
	barra.add_child(br)
	var bm := _bottone_piccolo("Menu", Color(0.4, 0.08, 0.08))
	bm.pressed.connect(_chiedi_menu)
	barra.add_child(bm)
	# pannello a destra
	var dx := _pannello(Color(0.05, 0.025, 0.03, 0.9), 8)
	dx.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	dx.offset_left = -PANNELLO_W
	dx.offset_top = 62
	hud.add_child(dx)
	scroll_pannello = ScrollContainer.new()
	scroll_pannello.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dx.add_child(scroll_pannello)
	pannello = VBoxContainer.new()
	pannello.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pannello.add_theme_constant_override("separation", 8)
	scroll_pannello.add_child(pannello)
	# registro a sinistra
	box_registro = _pannello(Color(0.03, 0.015, 0.02, 0.78), 8)
	box_registro.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	box_registro.offset_right = 300
	box_registro.offset_top = 62
	box_registro.offset_bottom = -170
	hud.add_child(box_registro)
	registro = RichTextLabel.new()
	registro.bbcode_enabled = true
	registro.scroll_following = true
	registro.add_theme_font_override("normal_font", F_TESTO)
	registro.add_theme_font_size_override("normal_font_size", 16)
	box_registro.add_child(registro)
	for e in partita.s["log"]:
		_su_evento(e)
	# richiesta in basso
	richiesta_box = _pannello(Color(0.08, 0.03, 0.035, 0.94), 12)
	richiesta_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	richiesta_box.offset_right = -PANNELLO_W - 8
	richiesta_box.offset_top = -164
	richiesta_box.offset_bottom = -4
	hud.add_child(richiesta_box)
	var rv := VBoxContainer.new()
	richiesta_box.add_child(rv)
	richiesta_titolo = _etichetta("", 21, ORO, F_SC)
	rv.add_child(richiesta_titolo)
	var rs := ScrollContainer.new()
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(rs)
	richiesta_corpo = HFlowContainer.new()
	richiesta_corpo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	richiesta_corpo.add_theme_constant_override("h_separation", 8)
	richiesta_corpo.add_theme_constant_override("v_separation", 6)
	rs.add_child(richiesta_corpo)
	# ingrandimento carte
	zoom = _pannello(Color(0.03, 0.015, 0.02, 0.96), 10)
	zoom.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	zoom.offset_left = 350
	zoom.offset_right = 690
	zoom.offset_top = -330
	zoom.offset_bottom = 230
	zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom.visible = false
	hud.add_child(zoom)
	var zv := VBoxContainer.new()
	zv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom.add_child(zv)
	zoom_img = TextureRect.new()
	zoom_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	zoom_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	zoom_img.custom_minimum_size = Vector2(320, 330)
	zoom_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zv.add_child(zoom_img)
	zoom_testo = RichTextLabel.new()
	zoom_testo.bbcode_enabled = true
	zoom_testo.fit_content = true
	zoom_testo.custom_minimum_size = Vector2(320, 0)
	zoom_testo.add_theme_font_override("normal_font", F_MACCHINA)
	zoom_testo.add_theme_font_size_override("normal_font_size", 17)
	zoom_testo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zv.add_child(zoom_testo)
	# avvisi
	avviso = _etichetta("", 24, OSSO, F_SC)
	avviso.set_anchors_preset(Control.PRESET_CENTER_TOP)
	avviso.offset_top = 70
	avviso.offset_left = -400
	avviso.offset_right = 400 - PANNELLO_W
	avviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	avviso.add_theme_color_override("font_outline_color", Color.BLACK)
	avviso.add_theme_constant_override("outline_size", 6)
	avviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(avviso)

func _avviso(t: String) -> void:
	if avviso:
		avviso.text = t

var _toasts := 0

func _toast(t: String, col := SANGUE_VIVO, durata := 2.6) -> void:
	if hud == null:
		return
	var pc := _pannello(Color(0.05, 0.02, 0.025, 0.93), 14)
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.offset_left = -330 - PANNELLO_W / 2.0
	pc.offset_right = 330 - PANNELLO_W / 2.0
	pc.offset_top = -170 + _toasts * 70
	pc.offset_bottom = -110 + _toasts * 70
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _etichetta(t, 24, col, F_SC)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	hud.add_child(pc)
	_toasts += 1
	var tw := pc.create_tween()
	pc.modulate.a = 0
	tw.tween_property(pc, "modulate:a", 1.0, 0.2)
	tw.tween_interval(durata * velocita)
	tw.tween_property(pc, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): pc.queue_free(); _toasts = maxi(0, _toasts - 1))

func _toast_dadi(e: Dictionary) -> void:
	if hud == null:
		return
	var pc := _pannello(Color(0.05, 0.02, 0.025, 0.95), 14)
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.offset_left = -260 - PANNELLO_W / 2.0
	pc.offset_right = 260 - PANNELLO_W / 2.0
	pc.offset_top = -40
	pc.offset_bottom = 70
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	pc.add_child(v)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	for f in e["dadi"]:
		var d := PanelContainer.new()
		d.custom_minimum_size = Vector2(56, 56)
		d.add_theme_stylebox_override("panel", _stile(Color("#c4161c"), 8, 2, Color("#2a0505")))
		var l := _etichetta("" if int(f) == 0 else str(f), 34, Color("#1a0000"), F_SC)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		d.add_child(l)
		h.add_child(d)
	var tot := _etichetta("%s: difesa %d" % [partita.nome_s(int(e["i"])), int(e["totale"])], 22, OSSO, F_SC)
	tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tot)
	hud.add_child(pc)
	var tw := pc.create_tween()
	pc.scale = Vector2(0.7, 0.7)
	tw.tween_property(pc, "scale", Vector2(1, 1), 0.2)
	tw.tween_interval(2.2 * velocita)
	tw.tween_property(pc, "modulate:a", 0.0, 0.4)
	tw.tween_callback(pc.queue_free)

func _toast_carta(e: Dictionary) -> void:
	if hud == null:
		return
	var path := Dati.img_carta(e["killer"], e["carta"])
	var tr := _immagine(path, 200, 277)
	tr.set_anchors_preset(Control.PRESET_CENTER)
	tr.offset_left = -100 - PANNELLO_W / 2.0
	tr.offset_right = 100 - PANNELLO_W / 2.0
	tr.offset_top = -200
	tr.offset_bottom = 77
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(tr)
	var tw := tr.create_tween()
	tr.modulate.a = 0
	tw.tween_property(tr, "modulate:a", 1.0, 0.2)
	tw.tween_interval(1.6 * velocita)
	tw.tween_property(tr, "modulate:a", 0.0, 0.4)
	tw.tween_callback(tr.queue_free)

func _chiedi_menu() -> void:
	if fine_box != null:
		_menu()
		return
	var pc := _pannello(Color(0.05, 0.02, 0.025, 0.97), 20)
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.offset_left = -220
	pc.offset_right = 220
	pc.offset_top = -90
	pc.offset_bottom = 90
	radice.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(_etichetta("Abbandonare la partita?", 24, OSSO, F_SC))
	var h := HBoxContainer.new()
	v.add_child(h)
	var si := _bottone("Sì, al menu")
	si.pressed.connect(func():
		if modo == "online":
			rete.remember_room("")
		_menu())
	h.add_child(si)
	var no := _bottone("Continua", Color(0.2, 0.12, 0.12))
	no.pressed.connect(pc.queue_free)
	h.add_child(no)

func _aggiorna_hud() -> void:
	if hud == null or partita == null:
		return
	var s: Dictionary = partita.s
	lbl_turno.text = "Turno %d" % s["turno"]
	if s["vincitore"] != "":
		lbl_fase.text = "Fine della partita"
	elif s["fase"] == "S":
		lbl_fase.text = "Tocca ai Sopravvissuti" + (" (tu)" if mio_lato == "S" and modo != "osserva" else "")
	else:
		lbl_fase.text = "Tocca al Killer" + (" (tu)" if mio_lato == "K" else "")
	var st := "[color=#c9a24a]Chiavi[/color] %d/5   [color=#c9a24a]Radio[/color] %d/5" % [s["chiavi"], s["riparazione"]]
	if mio_lato == "K" and modo != "osserva":
		st = "[color=#c9a24a]Chiavi[/color] %d/5   [color=#c9a24a]Radio[/color] ?/5" % s["chiavi"]
	if s["soccorso"] > 0:
		st += "   [color=#7fdc8a]Soccorsi tra %d turni[/color]" % s["soccorso"]
	st += "   [color=#c9a24a]Scoperta[/color] %d   [color=#c9a24a]Blocchi[/color] %d/%d" % [s["scoperta"].size(), s["blocchi"].size(), Dati.BLOCCHI_MAX]
	lbl_stato.text = st
	for c in pannello.get_children():
		c.queue_free()
	if mio_lato == "K" and modo != "osserva":
		_pannello_killer()
		_pannello_sopr_pubblico()
	else:
		_pannello_sopr()
		_pannello_killer_pubblico()

func _cuori(ferite: int, vivo: bool) -> String:
	if not vivo:
		return "[color=#ff3030]MORTO[/color]"
	return "[color=#e0262f]♥[/color]".repeat(2 - ferite) + "[color=#555]♥[/color]".repeat(ferite)

func _paure(n: int) -> String:
	return "[color=#d08cff]☠[/color]".repeat(n) + "[color=#444]☠[/color]".repeat(2 - n)

func _pannello_sopr() -> void:
	var s: Dictionary = partita.s
	var turno_mio: bool = lato_attuale == "S" and req_attuale.get("tipo", "") == "azione_s" and mio_lato == "S" and modo != "osserva"
	for i in s["sopr"].size():
		var sp: Dictionary = s["sopr"][i]
		var sd: Dictionary = Dati.SOPRAVVISSUTI[sp["id"]]
		var sel: bool = sel_s == i and turno_mio
		var pc := _pannello(Color(0.1, 0.06, 0.07, 0.95) if not sel else Color(0.16, 0.1, 0.06, 0.98), 8)
		pannello.add_child(pc)
		var v := VBoxContainer.new()
		pc.add_child(v)
		var h := HBoxContainer.new()
		v.add_child(h)
		var ritratto := _immagine("res://assets/sopravvissuti/%s_%s.webp" % [sp["id"], "ferito" if sp["ferite"] > 0 else "sano"], 120, 80)
		if ritratto.texture == null:
			ritratto = _immagine("res://assets/mini/%s.webp" % sp["id"], 80, 80)
		h.add_child(ritratto)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var nome := _etichetta(sd["nome"], 21, sd["colore"].lightened(0.35), F_SC)
		info.add_child(nome)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.add_theme_font_size_override("normal_font_size", 18)
		var extra := ""
		if sp["tempra"]:
			extra += "  [color=#c9a24a]Tempra[/color]"
		if sp["incoraggiamento"]:
			extra += "  [color=#7fdc8a]Incoraggiato[/color]"
		rt.text = "%s   %s   [color=#aaa]%s[/color]%s%s" % [_cuori(sp["ferite"], sp["vivo"]), _paure(sp["paura"]), partita.nome_luogo(sp["pos"]),
			"  [color=#7fdc8a]✓ ha agito[/color]" if sp["agito"] and s["fase"] == "S" else "", extra]
		info.add_child(rt)
		var abil := _etichetta("%s · %s" % [sd["abilita"][0][0], sd["abilita"][1][0]], 14, Color(0.8, 0.7, 0.6))
		abil.tooltip_text = "%s: %s\n%s: %s" % [sd["abilita"][0][0], sd["abilita"][0][1], sd["abilita"][1][0], sd["abilita"][1][1]]
		abil.mouse_filter = Control.MOUSE_FILTER_PASS
		info.add_child(abil)
		# oggetti
		if not sp["oggetti"].is_empty():
			var ho := HFlowContainer.new()
			ho.add_theme_constant_override("h_separation", 4)
			v.add_child(ho)
			for o in sp["oggetti"]:
				ho.add_child(_carta_oggetto(o, 52))
		# azioni
		if turno_mio and sp["vivo"]:
			var az := HFlowContainer.new()
			az.add_theme_constant_override("h_separation", 5)
			az.add_theme_constant_override("v_separation", 5)
			v.add_child(az)
			_bottoni_azioni(i, az)
	if modo != "osserva":
		var st := "[color=#c9a24a]Portachiavi:[/color] %d/5   [color=#c9a24a]Radio:[/color] %d/5" % [s["chiavi"], s["riparazione"]]
		var rr := RichTextLabel.new()
		rr.bbcode_enabled = true
		rr.fit_content = true
		rr.text = st
		pannello.add_child(rr)

func _pannello_killer_pubblico() -> void:
	var s: Dictionary = partita.s
	var k: Dictionary = s["killer"]
	var kd: Dictionary = Dati.KILLER[k["id"]]
	var pc := _pannello(Color(0.18, 0.03, 0.04, 0.95), 8)
	pannello.add_child(pc)
	var h := HBoxContainer.new()
	pc.add_child(h)
	h.add_child(_immagine(kd["mini"], 70, 90))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	v.add_child(_etichetta(kd["nome"], 22, SANGUE_VIVO, F_SC))
	var dove := "furtivo (sparito nel %s)" % partita.nome_luogo(k["vista"]) if k["furtivo"] else partita.nome_luogo(k["pos"])
	if modo == "osserva":
		dove = partita.nome_luogo(k["pos"]) + (" (furtivo)" if k["furtivo"] else "")
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.text = "Livello [color=#c9a24a]%d[/color] · Forza [color=#e0262f]%d[/color] · Carte in mano: %s\n%s" % [k["livello"], partita.forza(),
		str(k["mano"].size()) if modo == "osserva" else "?", dove]
	v.add_child(rt)
	var lv := _etichetta("Prossimo livello: " + (kd["livelli"][k["livello"]] if k["livello"] < 5 else "massimo raggiunto"), 14, Color(0.8, 0.7, 0.6))
	v.add_child(lv)
	if modo == "osserva":
		var hm := HFlowContainer.new()
		pannello.add_child(hm)
		for c in k["mano"]:
			var tr := _immagine(Dati.img_carta(k["id"], c), 62, 86)
			_zoomabile(tr, Dati.img_carta(k["id"], c), _testo_carta_k(c))
			hm.add_child(tr)

func _pannello_killer() -> void:
	var s: Dictionary = partita.s
	var k: Dictionary = s["killer"]
	var kd: Dictionary = Dati.KILLER[k["id"]]
	var pc := _pannello(Color(0.18, 0.03, 0.04, 0.95), 8)
	pannello.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	var pl := _immagine(kd["plancia"], 400, 227)
	_zoomabile(pl, kd["plancia"], "[font_size=24][color=#e0262f]%s[/color][/font_size]\n%s" % [kd["nome"], _livelli_testo(k)])
	v.add_child(pl)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.add_theme_font_size_override("normal_font_size", 18)
	rt.text = "Livello [color=#c9a24a]%d[/color] · Forza [color=#e0262f]%d[/color] · Mazzo %d · Scarti %d%s\nSei nel %s%s" % [k["livello"], partita.forza(),
		k["mazzo"].size(), k["scarti"].size(), "" if k["bloccata"] == "" else " · bloccata: «%s»" % Dati.CARTE_KILLER[k["bloccata"]]["nome"],
		partita.nome_luogo(k["pos"]), " [color=#b070f0](furtivo)[/color]" if k["furtivo"] else ""]
	v.add_child(rt)
	v.add_child(_etichetta("La tua mano", 19, ORO, F_SC))
	var hm := HFlowContainer.new()
	hm.add_theme_constant_override("h_separation", 6)
	hm.add_theme_constant_override("v_separation", 6)
	v.add_child(hm)
	var giocabili: Array = req_attuale.get("carte", []) if lato_attuale == "K" else []
	var tipo_req: String = req_attuale.get("tipo", "")
	for idx in k["mano"].size():
		var c: String = k["mano"][idx]
		var path := Dati.img_carta(k["id"], c)
		var b := TextureButton.new()
		b.texture_normal = _tex(path)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(122, 169)
		var attiva := false
		if lato_attuale == "K" and mio_lato == "K":
			if tipo_req in ["veloce", "principale", "lenta", "attacco"] and giocabili.has(idx):
				attiva = true
			elif tipo_req in ["costo", "scarta_mano"]:
				attiva = true
		if sel_carte.has(idx):
			b.modulate = Color(1, 0.5, 0.5)
		elif not attiva and tipo_req != "":
			b.modulate = Color(0.55, 0.5, 0.5)
		if attiva:
			var cornice := PanelContainer.new()
			cornice.add_theme_stylebox_override("panel", _stile(Color(0, 0, 0, 0), 6, 2, ORO))
			cornice.add_child(b)
			hm.add_child(cornice)
			b.pressed.connect(_su_carta.bind(idx))
		else:
			hm.add_child(b)
		_zoomabile(b, path, _testo_carta_k(c))
	if k["mano"].is_empty():
		v.add_child(_etichetta("(nessuna carta)", 16))

func _livelli_testo(k: Dictionary) -> String:
	var kd: Dictionary = Dati.KILLER[k["id"]]
	var t := ""
	for n in 5:
		var col := "#c9a24a" if n + 1 == k["livello"] else ("#e9dcc3" if n + 1 < k["livello"] else "#888")
		t += "[color=%s]Lv %d: %s[/color]\n" % [col, n + 1, kd["livelli"][n]]
	return t

func _pannello_sopr_pubblico() -> void:
	var s: Dictionary = partita.s
	pannello.add_child(_etichetta("Le prede", 20, ORO, F_SC))
	for i in s["sopr"].size():
		var sp: Dictionary = s["sopr"][i]
		var sd: Dictionary = Dati.SOPRAVVISSUTI[sp["id"]]
		var pc := _pannello(Color(0.08, 0.05, 0.06, 0.95), 6)
		pannello.add_child(pc)
		var h := HBoxContainer.new()
		pc.add_child(h)
		h.add_child(_immagine("res://assets/mini/%s.webp" % sp["id"], 46, 56))
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		var dove := ""
		if plancia.fantasmi.has(i):
			var f: Dictionary = plancia.fantasmi[i]
			var eta: int = s["turno"] - int(f["turno"])
			dove = "visto nel %s (%s)" % [partita.nome_luogo(f["luogo"]), "in questo turno" if eta <= 0 else "%d turni fa" % eta]
		else:
			dove = "posizione sconosciuta"
		rt.text = "[color=%s]%s[/color]  %s  %s\n[color=#aaa]%s[/color]" % ["#" + sd["colore"].lightened(0.35).to_html(false), sd["nome"],
			_cuori(sp["ferite"], sp["vivo"]), _paure(sp["paura"]), dove]
		v.add_child(rt)
		var abil := _etichetta("%s · %s" % [sd["abilita"][0][0], sd["abilita"][1][0]], 13, Color(0.8, 0.7, 0.6))
		abil.tooltip_text = "%s: %s\n%s: %s" % [sd["abilita"][0][0], sd["abilita"][0][1], sd["abilita"][1][0], sd["abilita"][1][1]]
		abil.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(abil)
	var rum: Array = s["rumori"] if s["fase"] == "K" else s["rumori_prec"]
	var t := "Rumori dell'ultimo turno: " + ("nessuno" if rum.is_empty() else ", ".join(rum.map(func(x): return partita.nome_luogo(x))))
	if s["petardo"] != "" and s["fase"] == "K":
		t = "Un petardo ha coperto tutti i rumori!"
	pannello.add_child(_etichetta(t, 16, Color("#ffb070")))

# ================================================================ azioni dei Sopravvissuti

func _bottoni_azioni(i: int, box: Control) -> void:
	var poss := partita.azioni_possibili(i)
	var sp: Dictionary = partita.s["sopr"][i]
	var aggiungi := func(t: String, cb: Callable, col := Color(0.35, 0.08, 0.1), tip := ""):
		var b := _bottone_piccolo(t, col)
		b.pressed.connect(cb)
		if tip != "":
			b.tooltip_text = tip
		box.add_child(b)
	if poss.has("muovi"):
		aggiungi.call("Muovi", func(): _scegli_movimento(i, "muovi", 2), Color(0.35, 0.08, 0.1), "[MUOVI] x1-2: clicca la destinazione")
	if poss.has("scatto"):
		aggiungi.call("Scatto", func(): _scegli_movimento(i, "scatto", 3), Color(0.35, 0.08, 0.1), "Muovi fino a 3, rumore all'arrivo")
	if poss.has("cerca"):
		aggiungi.call("Cerca", func(): _decidi({"a": "cerca", "i": i}), Color(0.15, 0.25, 0.12), "Pesca dal mazzo ricerca")
	if poss.has("ripara"):
		aggiungi.call("Ripara la radio", func(): _decidi({"a": "ripara", "i": i}), Color(0.15, 0.25, 0.12), "+1 riparazione, fa rumore")
	if poss.has("paura"):
		aggiungi.call("Calmati", func(): _decidi({"a": "paura", "i": i}), Color(0.25, 0.12, 0.3), "Togli tutta la paura")
	if poss.has("blocco"):
		for b in poss["blocco"]:
			var ab: PackedStringArray = b.split("|")
			var altro: String = ab[1] if ab[0] == sp["pos"] else ab[0]
			aggiungi.call("Sblocca verso %s" % altro, func(): _decidi({"a": "blocco", "i": i, "porta": b}), Color(0.3, 0.2, 0.1))
	if poss.has("passaggio"):
		aggiungi.call("Passaggio segreto", func(): _decidi({"a": "passaggio", "i": i}), Color(0.2, 0.15, 0.3), "Osservatrice: attraversa il passaggio segreto")
	if poss.has("passaggio_extra"):
		aggiungi.call("Passaggio (extra)", func(): _decidi({"a": "passaggio_extra", "i": i}), Color(0.2, 0.15, 0.3))
	if poss.has("risorse"):
		for o in poss["risorse"]:
			aggiungi.call("Prendi %s" % Dati.OGGETTI[o]["nome"], func(): _decidi({"a": "risorse", "i": i, "ogg": o}), Color(0.15, 0.2, 0.3))
	if poss.has("mente"):
		for sc in poss["mente"]:
			aggiungi.call("Studio: " + ("cassetta → +1 radio" if sc == "cassetta" else "pesca dalla ricerca"), func(): _decidi({"a": "mente", "i": i, "scelta": sc}), Color(0.15, 0.2, 0.3))
	if poss.has("incoraggia"):
		for j in poss["incoraggia"]:
			aggiungi.call("Incoraggia %s" % partita.nome_s(j), func(): _decidi({"a": "incoraggia", "i": i, "bersaglio": j}), Color(0.15, 0.25, 0.12))
	if poss.has("meccanica"):
		aggiungi.call("Prendi una cassetta", func(): _decidi({"a": "meccanica", "i": i}), Color(0.15, 0.2, 0.3))
	if poss.has("usa"):
		for k in poss["usa"]:
			var o: String = sp["oggetti"][k]
			aggiungi.call("Usa " + Dati.OGGETTI[o]["nome"], func(): _usa_oggetto(i, k), Color(0.2, 0.18, 0.08), Dati.OGGETTI[o]["testo"])
	if poss.has("scambia"):
		aggiungi.call("Dai un oggetto…", func(): _scegli_scambio(i, poss["scambia"]), Color(0.12, 0.12, 0.16), "Scambia oggetti con chi è nel tuo luogo")

func _scegli_scambio(i: int, compagni: Array) -> void:
	var sp: Dictionary = partita.s["sopr"][i]
	for c in richiesta_corpo.get_children():
		c.queue_free()
	richiesta_titolo.text = "%s: cosa dai, e a chi?" % partita.nome_s(i)
	for k in sp["oggetti"].size():
		var o: String = sp["oggetti"][k]
		for j in compagni:
			var b := _bottone_piccolo("%s → %s" % [Dati.OGGETTI[o]["nome"], partita.nome_s(j)], Color(0.12, 0.12, 0.16))
			b.pressed.connect(func(): _decidi({"a": "scambia", "i": i, "verso": j, "ogg": k}))
			richiesta_corpo.add_child(b)
	var ann := _bottone_piccolo("Annulla")
	ann.pressed.connect(_mostra_richiesta)
	richiesta_corpo.add_child(ann)

func _scegli_movimento(i: int, azione: String, n: int) -> void:
	sel_s = i
	sel_azione = azione
	sel_extra = partita.raggiungibili_sopr(i, n)
	plancia.mostra_scelta(sel_extra.keys())
	richiesta_titolo.text = "%s: clicca dove andare (fino a %d passi)" % [partita.nome_s(i), n]
	_bottoni_annulla()

func _bottoni_annulla() -> void:
	for c in richiesta_corpo.get_children():
		c.queue_free()
	var b := _bottone_piccolo("Annulla")
	b.pressed.connect(func(): plancia.pulisci_scelta(); sel_azione = ""; _mostra_richiesta())
	richiesta_corpo.add_child(b)

func _usa_oggetto(i: int, k: int) -> void:
	var sp: Dictionary = partita.s["sopr"][i]
	var o: String = sp["oggetti"][k]
	match o:
		"adrenalina":
			sel_s = i
			sel_azione = "adrenalina"
			sel_extra = partita.raggiungibili_sopr(i, 1)
			sel_extra["_k"] = k
			var dest: Array = sel_extra.keys()
			dest.erase("_k")
			plancia.mostra_scelta(dest)
			richiesta_titolo.text = "Adrenalina: clicca dove andare"
			_bottoni_annulla()
		"moneta":
			sel_s = i
			sel_azione = "moneta"
			sel_extra = partita.raggiungibili_sopr(i, 2)
			sel_extra["_k"] = k
			var dest: Array = sel_extra.keys()
			dest.erase("_k")
			plancia.mostra_scelta(dest)
			richiesta_titolo.text = "Moneta: se non esce una chiave ti muovi fin qui (clicca), oppure resta"
			_bottoni_annulla()
			var resta := _bottone_piccolo("Lancia e resta qui")
			resta.pressed.connect(func(): _decidi({"a": "usa", "i": i, "ogg": k, "percorso": []}))
			richiesta_corpo.add_child(resta)
		"whisky":
			sel_s = i
			sel_azione = "whisky"
			sel_extra = {"_k": k}
			plancia.mostra_scelta(partita.entro(sp["pos"], 1))
			richiesta_titolo.text = "Bottiglia di whisky: dove la lanci?"
			_bottoni_annulla()
		"nota_rumore":
			sel_s = i
			sel_azione = "nota_rumore"
			sel_extra = {"_k": k}
			plancia.mostra_scelta(partita.mappa["luoghi"].keys())
			richiesta_titolo.text = "Nota di George: dove fai rumore?"
			_bottoni_annulla()
		"erbe", "kit_medico", "tranquillante":
			var cand := []
			for j in partita.in_luogo(sp["pos"]):
				var q: Dictionary = partita.s["sopr"][j]
				if (o == "erbe" and q["ferite"] > 0) or (o == "tranquillante" and q["paura"] > 0) or (o == "kit_medico" and (q["ferite"] > 0 or q["paura"] > 0)):
					cand.append(j)
			if cand.size() <= 1:
				_decidi({"a": "usa", "i": i, "ogg": k, "bersaglio": cand[0] if not cand.is_empty() else i})
			else:
				for c in richiesta_corpo.get_children():
					c.queue_free()
				richiesta_titolo.text = "%s: su chi?" % Dati.OGGETTI[o]["nome"]
				for j in cand:
					var b := _bottone_piccolo(partita.nome_s(j))
					b.pressed.connect(func(): _decidi({"a": "usa", "i": i, "ogg": k, "bersaglio": j}))
					richiesta_corpo.add_child(b)
		"accetta", "nota_blocchi":
			var bl := []
			for b in partita.s["blocchi"]:
				if sp["pos"] in b.split("|"):
					bl.append(b)
			if bl.size() == 1 or o == "nota_blocchi":
				_decidi({"a": "usa", "i": i, "ogg": k, "porta": bl[0]})
			else:
				sel_s = i
				sel_azione = "accetta"
				sel_extra = {"_k": k}
				plancia.mostra_scelta([], bl)
				richiesta_titolo.text = "Accetta: clicca il blocco da abbattere"
				_bottoni_annulla()
		_:
			_decidi({"a": "usa", "i": i, "ogg": k})

# ================================================================ richieste: interfaccia

func _mostra_attesa(lato: String) -> void:
	if richiesta_titolo == null:
		return
	for c in richiesta_corpo.get_children():
		c.queue_free()
	if modo == "osserva":
		richiesta_titolo.text = ("Il Killer pensa…" if lato == "K" else "I Sopravvissuti pensano…")
	elif lato == "K":
		richiesta_titolo.text = "Il Killer si muove nell'ombra…"
	else:
		richiesta_titolo.text = "I Sopravvissuti stanno decidendo…"

func _mostra_richiesta() -> void:
	if richiesta_titolo == null or partita == null:
		return
	var req := req_attuale
	for c in richiesta_corpo.get_children():
		c.queue_free()
	plancia.pulisci_scelta()
	richiesta_titolo.text = req.get("titolo", "")
	var s: Dictionary = partita.s
	var k: Dictionary = s["killer"]
	match req.get("tipo", ""):
		"azione_s":
			richiesta_titolo.text = "Il vostro turno: scegliete un'azione per ogni Sopravvissuto (pannello a destra), poi chiudete il turno."
			var fine := _bottone("Fine delle azioni", SANGUE, 20)
			fine.pressed.connect(func(): _decidi({"a": "fine"}))
			richiesta_corpo.add_child(fine)
			var manca := []
			for i in partita.vivi():
				if not s["sopr"][i]["agito"]:
					manca.append(partita.nome_s(i))
			if not manca.is_empty():
				richiesta_corpo.add_child(_riga("Non hanno ancora agito: " + ", ".join(manca), 17, Color(0.85, 0.75, 0.6)))
		"scoperta_chi", "difensore", "bersaglio_paura":
			var cand: Array = req.get("candidati", partita.vivi())
			for i in cand:
				var sp: Dictionary = s["sopr"][i]
				var t := partita.nome_s(i)
				if req["tipo"] == "difensore":
					var mig := 0
					for o in partita.oggetti_difesa(i):
						mig = maxi(mig, int(o["bonus"]))
					t += " (%d dadi%s%s)" % [maxi(0, 4 - sp["paura"]), (", oggetto +%d" % mig) if mig > 0 else "", ", ferito" if sp["ferite"] > 0 else ""]
				elif req["tipo"] == "scoperta_chi":
					t += " (%s)" % partita.nome_luogo(sp["pos"])
				elif req["tipo"] == "bersaglio_paura":
					t += " (paura %d)" % sp["paura"]
				var b := _bottone(t, SANGUE, 18)
				b.pressed.connect(func(): _decidi({"i": i}))
				richiesta_corpo.add_child(b)
		"scoperta_tieni", "cerca_ophelia":
			var carte: Array = req["carte"]
			for n in carte.size():
				var v := VBoxContainer.new()
				v.add_child(_carta_oggetto(carte[n], 76))
				var b := _bottone_piccolo("Tieni")
				b.pressed.connect(func(): _decidi({"tieni": n}))
				v.add_child(b)
				richiesta_corpo.add_child(v)
			if req["tipo"] == "scoperta_tieni":
				var no := _bottone_piccolo("Nessuna")
				no.pressed.connect(func(): _decidi({"tieni": -1}))
				richiesta_corpo.add_child(no)
		"cerca_tieni":
			richiesta_corpo.add_child(_carta_oggetto(req["carta"], 76))
			var si := _bottone("Tienila", Color(0.15, 0.3, 0.15))
			si.pressed.connect(func(): _decidi({"tieni": true}))
			richiesta_corpo.add_child(si)
			var no := _bottone("Lasciala", Color(0.3, 0.1, 0.1))
			no.pressed.connect(func(): _decidi({"tieni": false}))
			richiesta_corpo.add_child(no)
		"troppi_oggetti":
			var ogg: Array = s["sopr"][int(req["i"])]["oggetti"]
			for n in ogg.size():
				var v := VBoxContainer.new()
				v.add_child(_carta_oggetto(ogg[n], 60))
				var b := _bottone_piccolo("Scarta")
				b.pressed.connect(func(): _decidi({"ogg": n}))
				v.add_child(b)
				richiesta_corpo.add_child(v)
		"oggetto_difesa":
			var i := int(req["i"])
			var sp: Dictionary = s["sopr"][i]
			richiesta_titolo.text += "  (tiri %d dadi)" % maxi(0, 4 - sp["paura"])
			for o in req["opzioni"]:
				var b := _bottone("%s (+%d)" % [o["nome"], o["bonus"]], Color(0.2, 0.18, 0.08), 18)
				b.pressed.connect(func(): _decidi({"ogg": o["ogg"], "munizioni": o.get("munizioni", false)}))
				richiesta_corpo.add_child(b)
			var no := _bottone("Nessun oggetto: tira i dadi", SANGUE, 18)
			no.pressed.connect(func(): _decidi({"ogg": -1}))
			richiesta_corpo.add_child(no)
		"fuga":
			plancia.mostra_scelta(req["luoghi"])
			sel_azione = "fuga"
			var resta := _bottone_piccolo("Resta qui")
			resta.pressed.connect(func(): _decidi({"dest": ""}))
			richiesta_corpo.add_child(resta)
		"nota_george":
			for n in req["note"]:
				var v := VBoxContainer.new()
				v.add_child(_carta_oggetto(n, 60))
				var b := _bottone_piccolo("Prendi")
				b.pressed.connect(func(): _decidi({"nota": n}))
				v.add_child(b)
				richiesta_corpo.add_child(v)
			var no := _bottone_piccolo("Nessuna")
			no.pressed.connect(func(): _decidi({"nota": ""}))
			richiesta_corpo.add_child(no)
		# ---------------- Killer
		"veloce":
			richiesta_titolo.text = "Carte veloci: clicca una carta evidenziata nella tua mano, oppure prosegui."
			var b := _bottone("Prosegui", SANGUE, 19)
			b.pressed.connect(func(): _decidi({"carta": -1}))
			richiesta_corpo.add_child(b)
		"principale":
			richiesta_titolo.text = "Gioca una carta speciale (clic sulla carta) oppure fai 2 azioni."
			var b := _bottone("Fai 2 azioni ([MUOVI] x1 / [CERCA])", SANGUE, 19)
			b.pressed.connect(func(): _decidi({"carta": -1}))
			richiesta_corpo.add_child(b)
		"lenta":
			richiesta_titolo.text = "Puoi giocare una carta lenta (clic sulla carta) prima di pescare."
			var b := _bottone("Pesca 3 carte e chiudi il turno", SANGUE, 19)
			b.pressed.connect(func(): _decidi({"carta": -1}))
			richiesta_corpo.add_child(b)
		"attacco":
			var b := _bottone("Attacca senza carte", SANGUE, 19)
			b.pressed.connect(func(): _decidi({"carta": -1}))
			richiesta_corpo.add_child(b)
		"azione_k":
			plancia.mostra_scelta(req["vicini"])
			sel_azione = "azione_k"
			var b := _bottone("[CERCA] nel %s" % partita.nome_luogo(k["pos"]), SANGUE, 19)
			b.pressed.connect(func(): _decidi({"a": "cerca"}))
			richiesta_corpo.add_child(b)
			richiesta_corpo.add_child(_riga("…oppure clicca un luogo vicino per [MUOVERTI].", 17))
		"muovi_k":
			plancia.mostra_scelta(req["vicini"], [], Color(1, 0.3, 0.25) if not req.get("furtivo", false) else Color(0.7, 0.4, 1))
			sel_azione = "muovi_k"
			if not req.get("obbligo", false):
				var b := _bottone("Fermati qui", SANGUE, 19)
				b.pressed.connect(func(): _decidi({"dest": ""}))
				richiesta_corpo.add_child(b)
		"costo":
			richiesta_titolo.text = "%s (%d/%d)" % [req["titolo"], sel_carte.size(), int(req["n"])]
			var b := _bottone("Conferma", SANGUE, 19)
			b.disabled = sel_carte.size() != int(req["n"])
			b.pressed.connect(func(): _decidi({"carte": sel_carte.duplicate()}))
			richiesta_corpo.add_child(b)
		"scarta_mano":
			richiesta_corpo.add_child(_riga("Clicca la carta da scartare nella tua mano.", 17))
		"zona":
			for z in Dati.ZONE:
				var b := _bottone("Zona " + Dati.ZONE[z], Dati.ZONA_COLORE[z].darkened(0.3), 19)
				b.pressed.connect(func(): _decidi({"zona": z}))
				richiesta_corpo.add_child(b)
		"luoghi2":
			plancia.mostra_scelta(partita.mappa["luoghi"].keys())
			sel_azione = "luoghi2"
			richiesta_corpo.add_child(_riga("Clicca il primo luogo, poi uno vicino.", 17))
		"porta":
			plancia.mostra_scelta([], req["porte"])
			sel_azione = "porta"
			for pt in req["porte"]:
				var ab: PackedStringArray = pt.split("|")
				var b := _bottone_piccolo("%s ↔ %s" % [ab[0], ab[1]])
				b.pressed.connect(func(): _decidi({"porta": pt}))
				richiesta_corpo.add_child(b)
		"si_no":
			var si := _bottone("Sì", SANGUE, 19)
			si.pressed.connect(func(): _decidi({"si": true}))
			richiesta_corpo.add_child(si)
			var no := _bottone("No", Color(0.2, 0.12, 0.12), 19)
			no.pressed.connect(func(): _decidi({"si": false}))
			richiesta_corpo.add_child(no)
	_aggiorna_hud()

func _su_carta(idx: int) -> void:
	if lato_attuale != "K" or mio_lato != "K":
		return
	var tipo: String = req_attuale.get("tipo", "")
	match tipo:
		"veloce", "principale", "lenta", "attacco":
			_decidi({"carta": idx})
		"scarta_mano":
			_decidi({"carta": idx})
		"costo":
			if idx == -1:
				return
			if sel_carte.has(idx):
				sel_carte.erase(idx)
			elif sel_carte.size() < int(req_attuale["n"]):
				sel_carte.append(idx)
			_mostra_richiesta()

func _su_luogo(l: String) -> void:
	if partita == null or partita.attesa.is_empty():
		return
	if not plancia._scelta_luoghi.has(l):
		return
	match sel_azione:
		"muovi", "scatto":
			if sel_extra.has(l):
				_decidi({"a": sel_azione, "i": sel_s, "percorso": sel_extra[l]})
		"adrenalina", "moneta":
			if sel_extra.has(l):
				_decidi({"a": "usa", "i": sel_s, "ogg": sel_extra["_k"], "percorso": sel_extra[l]})
		"whisky", "nota_rumore":
			_decidi({"a": "usa", "i": sel_s, "ogg": sel_extra["_k"], "luogo": l})
		"fuga":
			_decidi({"dest": l})
		"azione_k":
			_decidi({"a": "muovi", "dest": l})
		"muovi_k":
			_decidi({"dest": l})
		"luoghi2":
			if primo_luogo == "":
				primo_luogo = l
				plancia.mostra_scelta(partita.vicini(l))
				richiesta_titolo.text = "Ora un luogo collegato a %s" % partita.nome_luogo(l)
			else:
				_decidi({"luoghi": [primo_luogo, l]})

func _su_porta(pt: String) -> void:
	if partita == null or partita.attesa.is_empty():
		return
	match sel_azione:
		"porta":
			_decidi({"porta": pt})
		"accetta":
			_decidi({"a": "usa", "i": sel_s, "ogg": sel_extra["_k"], "porta": pt})

# ================================================================ fine partita

func _schermata_fine(vincitore: String, motivo: String) -> void:
	if fine_box != null:
		fine_box.queue_free()
	fine_box = Control.new()
	fine_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.add_child(fine_box)
	var vela := ColorRect.new()
	vela.color = Color(0.2, 0, 0, 0.55) if vincitore == "K" else Color(0, 0.08, 0.04, 0.55)
	vela.set_anchors_preset(Control.PRESET_FULL_RECT)
	fine_box.add_child(vela)
	var pc := _pannello(Color(0.04, 0.02, 0.025, 0.95), 26)
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.offset_left = -360
	pc.offset_right = 360
	pc.offset_top = -170
	pc.offset_bottom = 170
	fine_box.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pc.add_child(v)
	var hai_vinto := (vincitore == mio_lato) and modo != "osserva"
	var t := ""
	if modo == "osserva":
		t = "VINCE IL KILLER" if vincitore == "K" else "I SOPRAVVISSUTI SONO SALVI"
	else:
		t = ("HAI VINTO" if hai_vinto else "HAI PERSO")
	var tt := _titolo(t, 60, SANGUE_VIVO if vincitore == "K" else VERDE)
	tt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tt)
	var m := _etichetta(("Il Killer vince: " if vincitore == "K" else "I Sopravvissuti vincono: ") + motivo, 22, OSSO, F_SC)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(m)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	if modo != "online":
		var b := _bottone("Rivincita", SANGUE, 22)
		b.pressed.connect(func():
			config["seme"] = int(Time.get_unix_time_from_system()) % 1000000
			_avvia_partita())
		h.add_child(b)
	var b2 := _bottone("Guarda la plancia", Color(0.2, 0.12, 0.12), 20)
	b2.pressed.connect(func(): fine_box.visible = false; _toast("Premi Menu per uscire", OSSO))
	h.add_child(b2)
	var b3 := _bottone("Menu", Color(0.2, 0.12, 0.12), 20)
	b3.pressed.connect(_menu)
	h.add_child(b3)

# ================================================================ gioco online

func _crea_stanza() -> void:
	if _prep["ruolo"] == "O":
		_prep["ruolo"] = "S"
	_schermata_attesa("Creo la stanza…")
	var c: String = await rete.create_room(nome_giocatore, _prep["ruolo"])
	if c == "":
		_schermata_attesa("Non riesco a creare la stanza: %s" % rete.last_error, true)
		return
	codice = c
	mio_posto = 0
	mio_lato = _prep["ruolo"]
	rete.remember_room(codice, 0)
	_schermata_attesa("Stanza [b]%s[/b] creata. Comunica il codice al tuo avversario: tu sei %s.\nIn attesa che entri…" % [codice,
		"il Killer" if mio_lato == "K" else "i Sopravvissuti"], true)
	while codice != "" and hud == null:
		await get_tree().create_timer(2.0).timeout
		if codice == "" or hud != null:
			return
		var room: Dictionary = await rete.room(codice)
		var seats: Dictionary = Rete._as_dict(room.get("seats", {}))
		if seats.has("1"):
			config = {"mappa": _prep["mappa"], "killer": _prep["killer"], "sopravvissuti": _prep["sopr"].duplicate(),
				"seme": int(Time.get_unix_time_from_system()) % 1000000, "lato_host": mio_lato}
			await rete.start_room(codice, config)
			modo = "online"
			_avvia_partita()
			_toast("%s è entrato. Che la notte abbia inizio!" % str(seats["1"].get("name", "L'avversario")), OSSO)
			return

func _entra_stanza(c: String) -> void:
	if c.length() != 4:
		return
	_schermata_attesa("Entro nella stanza %s…" % c)
	var posto: int = await rete.join_room(c, nome_giocatore)
	if posto < 0:
		_schermata_attesa("Non posso entrare nella stanza %s (%s)." % [c, "piena" if posto == -1 else "inesistente o già iniziata"], true)
		return
	codice = c
	mio_posto = posto
	rete.remember_room(codice, posto)
	_schermata_attesa("Sei nella stanza %s. Aspetto che inizi la partita…" % codice, true)
	while codice != "" and hud == null:
		var room: Dictionary = await rete.room(codice)
		if room.get("status", "") == "playing" and room.get("game") is Dictionary:
			_avvia_online(room["game"])
			return
		await get_tree().create_timer(2.0).timeout

func _rientra(c: String) -> void:
	_schermata_attesa("Rientro nella stanza %s…" % c)
	var posto: int = await rete.join_room(c, nome_giocatore)
	if posto < 0:
		rete.remember_room("")
		_schermata_attesa("La partita %s non è più disponibile." % c, true)
		return
	codice = c
	mio_posto = posto
	var room: Dictionary = await rete.room(codice)
	if room.get("status", "") == "playing" and room.get("game") is Dictionary:
		_avvia_online(room["game"])
	else:
		_entra_stanza(c)

func _avvia_online(game: Dictionary) -> void:
	config = game.duplicate()
	config["seme"] = int(config["seme"])
	var lh: String = str(game.get("lato_host", "S"))
	mio_lato = lh if mio_posto == 0 else ("K" if lh == "S" else "S")
	modo = "online"
	_avvia_partita()

func _schermata_attesa(t: String, con_menu := false) -> void:
	_pulisci_radice()
	var sf := ColorRect.new()
	sf.color = Color(0.03, 0.015, 0.02)
	sf.set_anchors_preset(Control.PRESET_FULL_RECT)
	radice.add_child(sf)
	var pc := _pannello(NOTTE, 24)
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.offset_left = -360
	pc.offset_right = 360
	pc.offset_top = -140
	pc.offset_bottom = 140
	radice.add_child(pc)
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(_titolo("Gioco online", 40))
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.add_theme_font_size_override("normal_font_size", 21)
	rt.add_theme_font_size_override("bold_font_size", 30)
	rt.text = t
	v.add_child(rt)
	if con_menu:
		var b := _bottone("Menu", Color(0.2, 0.12, 0.12))
		b.pressed.connect(func(): codice = ""; _menu())
		v.add_child(b)

## Online: ogni decisione ha un numero. Se è già nel registro della stanza la si usa (così chi rientra
## rigioca la partita fino al punto giusto); altrimenti decide chi ne ha il diritto, l'altro aspetta.
func _online_richiesta(lato: String, req: Dictionary) -> void:
	var n := partita.decisioni
	var primo := true
	while partita != null and partita.decisioni == n and not partita.attesa.is_empty():
		var d = await rete.get_decision(codice, n)
		if partita == null or partita.decisioni != n:
			return
		if d is Dictionary and not d.is_empty():
			_avviso("")
			partita.rispondi(d)
			return
		if d == null and lato == mio_lato:
			if primo:
				_mostra_richiesta()
			return
		if d == null:
			if primo:
				_mostra_attesa(lato)
				primo = false
			await get_tree().create_timer(1.2).timeout
		else:
			_avviso("Connessione instabile… (%s)" % rete.last_error)
			await get_tree().create_timer(2.5).timeout

# ================================================================ preferenze

func _carica_preferenze() -> void:
	var c := ConfigFile.new()
	if c.load("user://preferenze_terrorscape.cfg") == OK:
		nome_giocatore = str(c.get_value("p", "nome", nome_giocatore))
		velocita = float(c.get_value("p", "velocita", 1.0))

func _salva_preferenze() -> void:
	var c := ConfigFile.new()
	c.set_value("p", "nome", nome_giocatore)
	c.set_value("p", "velocita", velocita)
	c.save("user://preferenze_terrorscape.cfg")
