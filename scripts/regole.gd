## Il motore delle regole di Terrorscape, senza grafica.
## La partita è una coroutine: quando serve una decisione chiama chiedi(lato, richiesta) e aspetta
## la risposta (dal giocatore, dall'IA o dalla rete). Con lo stesso seme e le stesse risposte
## due dispositivi giocano esattamente la stessa partita: così funziona il gioco online.
class_name Partita
extends Node

signal richiesta(lato: String, req: Dictionary)
signal risposta_arrivata
signal evento(ev: Dictionary)
signal cambiato
signal finita(vincitore: String, motivo: String)

var s: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _risposta = null
var attesa := {}          # richiesta in corso: {lato, req}
var mappa: Dictionary = {}
var _adj := {}            # luogo -> [vicini]
var _porte := {}          # "A|B" -> {tipo, xy}
var decisioni := 0        # quante risposte sono state date (per il gioco online)
var veloce := false       # niente pause (simulazioni)

# ================================================================ avvio

## config: {mappa, killer, sopravvissuti: [3 id], seme}
func prepara(config: Dictionary) -> void:
	rng.seed = int(config.get("seme", 1))
	mappa = Dati.MAPPE[config.get("mappa", "villa")]
	_adj.clear()
	_porte.clear()
	for l in mappa["luoghi"]:
		_adj[l] = []
	for c in mappa["collegamenti"]:
		_adj[c[0]].append(c[1])
		_adj[c[1]].append(c[0])
		_porte[chiave_porta(c[0], c[1])] = {"tipo": c[2], "xy": c[3]}
	var kd: Dictionary = Dati.KILLER[config["killer"]]
	var mazzo := []
	for c in kd["mazzo"]:
		for i in int(kd["mazzo"][c]):
			mazzo.append(c)
	_mescola(mazzo)
	s = {
		"mappa": config.get("mappa", "villa"),
		"turno": 0, "fase": "", "vincitore": "", "motivo": "",
		"killer": {"id": config["killer"], "pos": mappa["partenza_k"], "vista": mappa["partenza_k"], "furtivo": false,
			"livello": 1, "forza_base": int(kd["forza"]), "bonus_livello": 0, "bonus_turno": 0, "bonus_attacco": 0,
			"mazzo": mazzo, "mano": [], "scarti": [], "bloccata": kd["bloccata"], "riappari": [], "incontro": false,
			"motosega_veloce": false, "furtivo_turni": 0,
			"forza_perm": 0, "bonus_esteso": 0, "bonus_esteso_fino": -1, "evoluzioni": [], "passaggio_turno": false,
			"rimosse": [], "fase_carta": "", "principale": 0, "molt": 1, "riappare_ora": false},
		"sopr": [],
		# espansioni
		"zombi": [], "statue": [], "nuclei": [], "trappole_k": {}, "trappole_scattate": [],
		"forzieri": [], "argento": [], "reliquie": [], "reliquie_aperte": false, "crollo_k": "", "crollo_s": "",
		"blocchi": [],               # elenco di "A|B" (in ordine di posa)
		"rumori": [], "rumori_prec": [], "petardo": "",
		"trappola": "",
		"chiavi": 0, "riparazione": 0, "riparato_turno": false, "soccorso": -1,
		"cancello": "", "statua_corridoio": false, "valigia_su": false,
		"ricerca": [], "scoperta": [], "scarti_ogg": [],
		"log": [],
	}
	for l in mappa["luoghi"]:
		if mappa["luoghi"][l].get("statua", false):
			s["statua_corridoio"] = true
		if mappa["luoghi"][l].get("valigia", false):
			s["valigia_su"] = true
	for id in config["sopravvissuti"]:
		var sd: Dictionary = Dati.SOPRAVVISSUTI[id]
		var p := {"id": id, "pos": mappa["partenza_s"], "ferite": 0, "paura": 0, "oggetti": [], "vivo": true,
			"agito": false, "moneta": false, "incoraggiamento": false, "tempra": id == "dylan",
			"veleno": false, "intrappolato": false, "no_extra": false}
		for o in sd.get("inizio", []):
			p["oggetti"].append(o)
		s["sopr"].append(p)
	# mazzi oggetto
	var ric := []
	for o in Dati.MAZZO_RICERCA:
		for i in int(Dati.MAZZO_RICERCA[o]):
			ric.append(o)
	_mescola(ric)
	# una chiave in fondo (la carta col dorso colorato)
	ric.erase("chiave")
	ric.push_front("chiave")
	s["ricerca"] = ric
	var sco := []
	for o in Dati.MAZZO_SCOPERTA:
		for i in int(Dati.MAZZO_SCOPERTA[o]):
			sco.append(o)
	_mescola(sco)
	s["scoperta"] = sco
	# mano iniziale del Killer: 2 carte
	for i in 2:
		s["killer"]["mano"].append(s["killer"]["mazzo"].pop_back())
	# Tomba: il mazzo delle reliquie
	for l in mappa["luoghi"]:
		if mappa["luoghi"][l].get("reliquie", false):
			var rel := []
			for o in Dati.MAZZO_RELIQUIE:
				for i in int(Dati.MAZZO_RELIQUIE[o]):
					rel.append(o)
			_mescola(rel)
			s["reliquie"] = rel
	# Killer delle espansioni: preparativi senza decisioni
	match config["killer"]:
		"lupo":
			var arg := []
			for o in Dati.MAZZO_ARGENTO:
				for i in int(Dati.MAZZO_ARGENTO[o]):
					arg.append(o)
			_mescola(arg)
			s["argento"] = arg
			var cand := []
			for l in mappa["luoghi"]:
				if l != mappa["partenza_s"] and l != mappa["partenza_k"]:
					cand.append(l)
			_mescola(cand)
			s["forzieri"] = cand.slice(0, 4)
		"strangolatore":
			s["nuclei"] = [mappa["partenza_k"]]
		"statue":
			s["statue"] = [{"pos": mappa["partenza_k"], "gelo": 0, "nome": "Rossa"}, {"pos": mappa["partenza_k"], "gelo": 0, "nome": "Blu"},
				{"pos": mappa["partenza_k"], "gelo": 0, "nome": "Verde"}, {"pos": mappa["partenza_k"], "gelo": 0, "nome": "Gialla"}]

func _mescola(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

func gioca() -> void:
	var dove_k := "" if s["killer"]["id"] == "statue" else ", il Killer attende nel %s" % nome_luogo(mappa["partenza_k"])
	_ev("Cala la notte: %s. I Sopravvissuti entrano da %s%s." % [mappa["nome"], nome_luogo(mappa["partenza_s"]), dove_k], "S")
	_ev("Cala la notte: %s. Tu attendi nel %s; i Sopravvissuti sono entrati da %s." % [
		mappa["nome"], nome_luogo(mappa["partenza_k"]), nome_luogo(mappa["partenza_s"])], "K")
	await _preparativi()
	while s["vincitore"] == "":
		await _turno_sopravvissuti()
		if s["vincitore"] != "":
			break
		await _turno_killer()
	cambiato.emit()
	finita.emit(s["vincitore"], s["motivo"])

## Preparativi dei Killer delle espansioni che richiedono decisioni.
func _preparativi() -> void:
	var k: Dictionary = s["killer"]
	match k["id"]:
		"cacciatrice":
			var tipi := ["tagliola", "teschi", "rete", "rete"]
			for t in tipi:
				var cand := []
				for l in mappa["luoghi"]:
					if distanza(l, mappa["partenza_s"]) >= 1 and not s["trappole_k"].has(l):
						cand.append(l)
				var d := await chiedi("K", {"tipo": "luogo", "luoghi": cand, "scopo": "trappola", "trappola": t,
					"titolo": "Preparativi: dove piazzi la trappola «%s»?" % Dati.TRAPPOLE[t]["nome"]})
				var l: String = d.get("dest", "")
				if not cand.has(l):
					l = cand[0]
				s["trappole_k"][l] = t
				_ev("La Cacciatrice piazza una trappola coperta nel %s." % nome_luogo(l), "tutti", {"tipo": "trappola_piazzata", "luogo": l})
		"statue":
			for j in range(1, 4):
				var cand := []
				for l in mappa["luoghi"]:
					if distanza(l, mappa["partenza_s"]) >= 2:
						var occupato := false
						for st in s["statue"].slice(0, j):
							if st["pos"] == l:
								occupato = true
						if not occupato:
							cand.append(l)
				var d := await chiedi("K", {"tipo": "luogo", "luoghi": cand, "scopo": "statua",
					"titolo": "Preparativi: dove metti la Statua %s?" % s["statue"][j]["nome"]})
				var l: String = d.get("dest", "")
				if not cand.has(l):
					l = cand[0]
				s["statue"][j]["pos"] = l
			var opz := []
			for st in s["statue"]:
				opz.append("Statua %s (%s)" % [st["nome"], nome_luogo(st["pos"])])
			var d2 := await chiedi("K", {"tipo": "scelta", "opzioni": opz, "scopo": "principale",
				"titolo": "Quale Statua è la principale? (i Sopravvissuti non lo sanno)"})
			var n := int(d2.get("n", 0))
			k["principale"] = clampi(n, 0, 3)
			_sync_statue()
			_ev("Quattro Statue si ergono nella %s." % mappa["nome"], "tutti", {"tipo": "statue"})
		"regina":
			var vv := vivi()
			var d := await chiedi("S", {"tipo": "sopravvissuto", "candidati": vv, "titolo": "Preparativi: chi riceve la Balestra?"})
			var i := int(d.get("i", vv[0]))
			if not vv.has(i):
				i = vv[0]
			s["sopr"][i]["oggetti"].append("balestra")
			_ev("%s parte con la Balestra." % nome_s(i), "tutti")
	cambiato.emit()

# ================================================================ richieste e risposte

func chiedi(lato: String, req: Dictionary) -> Dictionary:
	req["lato"] = lato
	attesa = {"lato": lato, "req": req}
	_risposta = null
	cambiato.emit()
	richiesta.emit(lato, req)
	while _risposta == null:
		await risposta_arrivata
	var r: Dictionary = _risposta
	_risposta = null
	attesa = {}
	decisioni += 1
	return r

func rispondi(d: Dictionary) -> void:
	if attesa.is_empty():
		push_warning("Risposta senza richiesta: %s" % str(d))
		return
	_risposta = d
	risposta_arrivata.emit()

# ================================================================ eventi

## vis: "tutti", "K" (solo il Killer lo sa), "S" (solo i Sopravvissuti)
func _ev(testo: String, vis := "tutti", extra := {}) -> void:
	if testo.find("Le Statue ") >= 0:
		# le Statue sono plurali: si accorda il verbo
		for c in [[" gioca ", " giocano "], [" pesca ", " pescano "], [" sale al ", " salgono al "], [" sblocca ", " sbloccano "],
				[" trova ", " trovano "], [" cerca ", " cercano "], [" blocca ", " bloccano "], [" scarta ", " scartano "]]:
			testo = testo.replace("Le Statue" + c[0], "Le Statue" + c[1])
	var e := {"t": testo, "vis": vis, "turno": s.get("turno", 0)}
	e.merge(extra)
	s["log"].append(e)
	evento.emit(e)

func _fine(chi: String, motivo: String) -> void:
	if s["vincitore"] != "":
		return
	s["vincitore"] = chi
	s["motivo"] = motivo
	_ev(("VITTORIA DEL KILLER: " if chi == "K" else "VITTORIA DEI SOPRAVVISSUTI: ") + motivo, "tutti", {"tipo": "fine"})

# ================================================================ mappa

static func chiave_porta(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func nome_luogo(l: String) -> String:
	if l == "":
		return "?"
	return "%s %s" % [l, mappa["luoghi"][l]["nome"]]

func vicini(l: String) -> Array:
	return _adj.get(l, [])

func porta(a: String, b: String) -> Dictionary:
	return _porte.get(chiave_porta(a, b), {})

func bloccata(a: String, b: String) -> bool:
	return chiave_porta(a, b) in s["blocchi"]

## Porte (bloccabili) che toccano un luogo.
func porte_di(l: String) -> Array:
	var out := []
	for v in vicini(l):
		if porta(l, v).get("tipo", "") == "porta":
			out.append(chiave_porta(l, v))
	return out

## Gruppi di passaggio segreto di un luogo (un luogo può averne più d'uno).
func _gruppi_passaggio(l: String) -> Array:
	var g = mappa["luoghi"][l].get("passaggio", "")
	if g is Array:
		return g
	return [] if g == "" else [g]

## Dove porta il passaggio segreto (o i passaggi) di un luogo.
func passaggi_di(l: String) -> Array:
	var out := []
	for g in _gruppi_passaggio(l):
		for o in mappa["luoghi"]:
			if o != l and _gruppi_passaggio(o).has(g) and not out.has(o):
				out.append(o)
	return out

## Il Killer può muoversi anche lungo i suoi passaggi riservati (Baita). Il cancello lo ferma
## se non ha almeno 3 carte da scartare.
func vicini_k(l: String) -> Array:
	var out: Array = vicini(l).duplicate()
	for c in mappa.get("passaggi_killer", []):
		if c[0] == l and not out.has(c[1]):
			out.append(c[1])
		elif c[1] == l and not out.has(c[0]):
			out.append(c[0])
	if s.get("cancello", "") != "" and s["killer"]["mano"].size() < 3:
		for v in out.duplicate():
			if chiave_porta(l, v) == s["cancello"]:
				out.erase(v)
	# il Non Identificato usa i passaggi segreti
	if s["killer"]["id"] == "ignoto":
		for v in passaggi_di(l):
			if not out.has(v):
				out.append(v)
	# il crollo dei Sopravvissuti ferma il Killer
	if s.get("crollo_s", "") != "":
		out.erase(s["crollo_s"])
	return out

## Il Killer impedisce di cercare e riparare nel suo luogo (le Statue no).
func killer_blocca(l: String) -> bool:
	if s["killer"]["id"] == "statue":
		return false
	return (not s["killer"]["furtivo"]) and killer_visto() == l

## I luoghi in cui i Sopravvissuti vedono una figura del Killer (le Statue sono quattro).
func figure_killer() -> Array:
	if s["killer"]["id"] == "statue":
		var out := []
		for st in s["statue"]:
			out.append(st["pos"])
		return out
	return [killer_visto()]

## Distanza dalla figura del Killer più vicina (per i Sopravvissuti).
func distanza_killer(l: String) -> int:
	var m := 99
	for f in figure_killer():
		m = mini(m, distanza(l, f))
	return m

func _sync_statue() -> void:
	if s["killer"]["id"] != "statue" or s["statue"].is_empty():
		return
	var pos: String = s["statue"][s["killer"]["principale"]]["pos"]
	s["killer"]["pos"] = pos
	s["killer"]["vista"] = pos

func statue_in(l: String) -> Array:
	var out := []
	for j in s["statue"].size():
		if s["statue"][j]["pos"] == l:
			out.append(j)
	return out

func zombi_in(l: String) -> int:
	return s["zombi"].count(l)

## Porta chiusa per i Sopravvissuti: bloccata oppure con il cancello.
func chiusa_sopr(a: String, b: String) -> bool:
	return bloccata(a, b) or s.get("cancello", "") == chiave_porta(a, b)

## Distanza (in passi, i blocchi non contano; i passaggi segreti nemmeno).
func distanza(a: String, b: String) -> int:
	if a == b:
		return 0
	var vis := {a: 0}
	var coda := [a]
	while not coda.is_empty():
		var x = coda.pop_front()
		for v in vicini(x):
			if not vis.has(v):
				vis[v] = vis[x] + 1
				if v == b:
					return vis[v]
				coda.append(v)
	return 99

func entro(centro: String, r: int) -> Array:
	var out := []
	for l in mappa["luoghi"]:
		if distanza(centro, l) <= r:
			out.append(l)
	return out

func zona(l: String) -> String:
	return l.substr(0, 1)

## Dove un Sopravvissuto può fare un passo: porte non bloccate, aperti, passaggi segreti se ha la torcia.
func passi_sopr(i: int, da: String, con_passaggi := false) -> Array:
	var out := []
	if s["sopr"][i].get("intrappolato", false):
		return out
	for v in vicini(da):
		if not chiusa_sopr(da, v):
			out.append(v)
	if con_passaggi or ha_oggetto(i, "torcia"):
		for p in passaggi_di(da):
			if not out.has(p):
				out.append(p)
	if s.get("crollo_k", "") != "":
		out.erase(s["crollo_k"])
	return out

## Tutti i luoghi raggiungibili in 1..n passi (per l'interfaccia), con il percorso.
func raggiungibili_sopr(i: int, n: int) -> Dictionary:
	var da: String = s["sopr"][i]["pos"]
	var out := {}
	var front := {da: []}
	for passo in n:
		var nuovo := {}
		for l in front:
			for v in passi_sopr(i, l):
				var perc: Array = front[l].duplicate()
				perc.append(v)
				if v != da and not out.has(v):
					out[v] = perc
					nuovo[v] = perc
		front = nuovo
	return out

# ================================================================ Sopravvissuti: utilità

func sopr(i: int) -> Dictionary:
	return s["sopr"][i]

func nome_s(i: int) -> String:
	return Dati.SOPRAVVISSUTI[s["sopr"][i]["id"]]["nome"].split(" ")[0]

func indice_di(id: String) -> int:
	for i in s["sopr"].size():
		if s["sopr"][i]["id"] == id:
			return i
	return -1

func ha_oggetto(i: int, o: String) -> bool:
	return s["sopr"][i]["oggetti"].has(o)

func vivi() -> Array:
	var out := []
	for i in s["sopr"].size():
		if s["sopr"][i]["vivo"]:
			out.append(i)
	return out

func in_luogo(l: String) -> Array:
	var out := []
	for i in vivi():
		if s["sopr"][i]["pos"] == l:
			out.append(i)
	return out

func limite_oggetti(i: int) -> int:
	return 99 if s["sopr"][i]["id"] == "johnson" else 3

## Dove i Sopravvissuti credono che sia il Killer (se è furtivo, l'ultimo luogo noto).
func killer_visto() -> String:
	return s["killer"]["vista"]

func _rumore(l: String, perche := "") -> void:
	if l == "" or s["rumori"].has(l):
		return
	s["rumori"].append(l)
	_ev("Rumore nel %s%s." % [nome_luogo(l), (" (" + perche + ")") if perche != "" else ""], "S", {"tipo": "rumore_s", "luogo": l})

func _paura(i: int, fonte := "") -> void:
	var p: Dictionary = s["sopr"][i]
	if not p["vivo"]:
		return
	if p["incoraggiamento"]:
		p["incoraggiamento"] = false
		_ev("%s riceve paura ma l'Incoraggiamento la annulla." % nome_s(i), "tutti", {"tipo": "paura", "i": i, "annullata": true})
		return
	if p["paura"] >= 2:
		# la paura trabocca: rumore e posizione rivelata subito
		_ev("La paura di %s trabocca! Un urlo dal %s." % [nome_s(i), nome_luogo(p["pos"])], "tutti",
			{"tipo": "trabocca", "i": i, "luogo": p["pos"]})
		if not s["rumori"].has(p["pos"]):
			s["rumori"].append(p["pos"])
		if s["killer"]["id"] == "spettro" and s["killer"]["livello"] >= 3 and s["killer"]["mano"].size() >= 3 and s["vincitore"] == "":
			var d := await chiedi("K", {"tipo": "si_no", "titolo": "Livello 3: scartare 3 carte per ferire %s?" % nome_s(i)})
			if d.get("si", false):
				for k in 3:
					s["killer"]["scarti"].append(s["killer"]["mano"].pop_back())
				await _danno(i, "Spettro")
		return
	p["paura"] += 1
	_ev("%s riceve paura (%d)%s." % [nome_s(i), p["paura"], (" da " + fonte) if fonte != "" else ""], "tutti", {"tipo": "paura", "i": i})

## Paura immediata senza effetti di livello (usata dal Corridoio delle statue).
func _paura_subito(i: int) -> void:
	var p: Dictionary = s["sopr"][i]
	if p["incoraggiamento"]:
		p["incoraggiamento"] = false
		return
	if p["paura"] >= 2:
		_ev("La paura di %s trabocca! Un urlo dal %s." % [nome_s(i), nome_luogo(p["pos"])], "tutti",
			{"tipo": "trabocca", "i": i, "luogo": p["pos"]})
		if not s["rumori"].has(p["pos"]):
			s["rumori"].append(p["pos"])
		return
	p["paura"] += 1
	_ev("%s riceve paura (%d)." % [nome_s(i), p["paura"]], "tutti", {"tipo": "paura", "i": i})

func _danno(i: int, fonte := "") -> void:
	var p: Dictionary = s["sopr"][i]
	if not p["vivo"] or s["vincitore"] != "":
		return
	if p["tempra"]:
		p["tempra"] = false
		_ev("%s evita la ferita grazie alla Tempra." % nome_s(i), "tutti", {"tipo": "tempra", "i": i})
		return
	if p["oggetti"].has("pietra"):
		_scarta_oggetto(i, "pietra")
		_ev("%s mostra la Pietra della protezione: la ferita è evitata." % nome_s(i), "tutti", {"tipo": "tempra", "i": i})
		return
	p["ferite"] += 1
	if p["ferite"] >= 2:
		p["vivo"] = false
		_ev("%s è stato ucciso%s nel %s." % [nome_s(i), (" da " + fonte) if fonte != "" else "", nome_luogo(p["pos"])], "tutti",
			{"tipo": "morte", "i": i, "luogo": p["pos"]})
		_fine("K", "%s è stato eliminato." % Dati.SOPRAVVISSUTI[p["id"]]["nome"])
	else:
		_ev("%s è ferito%s." % [nome_s(i), (" da " + fonte) if fonte != "" else ""], "tutti", {"tipo": "ferita", "i": i})

func _cura(i: int) -> void:
	var p: Dictionary = s["sopr"][i]
	if p.get("veleno", false):
		p["veleno"] = false
		_ev("%s non è più avvelenato." % nome_s(i), "tutti", {"tipo": "cura", "i": i})
	if p["ferite"] > 0:
		p["ferite"] = 0
		_ev("%s è curato." % nome_s(i), "tutti", {"tipo": "cura", "i": i})

## [AVVELENA]: la prima volta un segnalino veleno, la seconda una ferita (il segnalino resta).
func _avvelena(i: int) -> void:
	var p: Dictionary = s["sopr"][i]
	if not p["vivo"] or s["vincitore"] != "":
		return
	if not p["veleno"]:
		p["veleno"] = true
		_ev("%s è avvelenato!" % nome_s(i), "tutti", {"tipo": "veleno", "i": i})
	else:
		_ev("Il veleno fa effetto su %s." % nome_s(i), "tutti", {"tipo": "veleno", "i": i})
		_danno(i, "il veleno")

func ha_bisogno_cura(j: int) -> bool:
	return s["sopr"][j]["ferite"] > 0 or s["sopr"][j].get("veleno", false)

func _scarta_oggetto(i: int, o: String) -> void:
	var p: Dictionary = s["sopr"][i]
	if p["oggetti"].has(o):
		p["oggetti"].erase(o)
		s["scarti_ogg"].append(o)

## Aggiunge un oggetto (le chiavi vanno sul portachiavi); se si supera il limite si sceglie cosa scartare.
func _prendi_oggetto(i: int, o: String) -> void:
	if o == "chiave":
		s["chiavi"] += 1
		_ev("%s trova una Chiave! (%d/5)" % [nome_s(i), s["chiavi"]], "S", {"tipo": "chiave"})
		_ev("I Sopravvissuti hanno trovato una chiave (%d)." % s["chiavi"], "K", {"tipo": "chiave_k"})
		return
	s["sopr"][i]["oggetti"].append(o)
	_ev("%s prende: %s." % [nome_s(i), Dati.OGGETTI[o]["nome"]], "S")
	while s["sopr"][i]["oggetti"].size() > limite_oggetti(i):
		var d := await chiedi("S", {"tipo": "troppi_oggetti", "i": i, "titolo": "%s ha troppi oggetti: scegline uno da scartare" % nome_s(i)})
		var idx := int(d.get("ogg", 0))
		var lst: Array = s["sopr"][i]["oggetti"]
		if idx < 0 or idx >= lst.size():
			idx = lst.size() - 1
		var via = lst[idx]
		lst.remove_at(idx)
		s["scarti_ogg"].append(via)
		_ev("%s scarta %s." % [nome_s(i), Dati.OGGETTI[via]["nome"]], "S")

# ================================================================ turno dei Sopravvissuti

func _turno_sopravvissuti() -> void:
	s["turno"] += 1
	s["fase"] = "S"
	_ev("— Turno %d: i Sopravvissuti —" % s["turno"], "tutti", {"tipo": "turno"})
	s["rumori_prec"] = s["rumori"]
	s["rumori"] = []
	s["petardo"] = ""
	s["riparato_turno"] = false
	# soccorso in arrivo
	if s["soccorso"] > 0:
		s["soccorso"] -= 1
		if s["soccorso"] <= 0:
			_fine("S", "i soccorsi sono arrivati!")
			return
		_ev("I soccorsi arriveranno tra %d turni." % s["soccorso"], "tutti", {"tipo": "soccorso"})
	# fuga con 5 chiavi
	if s["chiavi"] >= 5:
		var tutti_uscita := true
		var tutti_nascosta := true
		var mappa_s := false
		for i in vivi():
			var l: String = s["sopr"][i]["pos"]
			if not mappa["luoghi"][l].get("uscita", false):
				tutti_uscita = false
			if not mappa["luoghi"][l].get("uscita_nascosta", false):
				tutti_nascosta = false
			if ha_oggetto(i, "mappa_segreta"):
				mappa_s = true
		if tutti_uscita:
			_fine("S", "fuga dall'uscita principale con le 5 chiavi!")
			return
		if tutti_nascosta and mappa_s:
			_fine("S", "fuga dall'uscita nascosta con la Mappa segreta!")
			return
	for i in vivi():
		s["sopr"][i]["agito"] = false
		s["sopr"][i]["moneta"] = false
		s["sopr"][i]["intrappolato"] = false
		s["sopr"][i]["no_extra"] = false
	for l in mappa["luoghi"]:
		if mappa["luoghi"][l].get("valigia", false):
			s["valigia_su"] = true
	cambiato.emit()
	# azioni
	var giri := 0
	while s["vincitore"] == "":
		giri += 1
		if giri > 200:
			break
		var d := await chiedi("S", {"tipo": "azione_s", "titolo": "Turno dei Sopravvissuti"})
		if d.get("a", "fine") == "fine":
			break
		var ok := await esegui_s(d)
		if not ok:
			_ev("Azione non valida: %s" % str(d), "S", {"tipo": "errore"})
		cambiato.emit()
	if s["vincitore"] != "":
		return
	# scoperta
	await _scoperta()
	if s["vincitore"] != "":
		return
	# George percettivo
	for i in vivi():
		var p: Dictionary = s["sopr"][i]
		var dk := distanza(p["pos"], s["killer"]["pos"])
		if s["killer"]["id"] == "statue":
			dk = distanza_killer(p["pos"])
		if p["id"] == "george" and dk <= 1:
			var d := await chiedi("S", {"tipo": "nota_george", "i": i, "titolo": "George è vicino al Killer: prendi una Nota?",
				"note": ["nota_blocchi", "nota_rumore", "nota_difesa"]})
			var n: String = d.get("nota", "")
			if n in ["nota_blocchi", "nota_rumore", "nota_difesa"]:
				await _prendi_oggetto(i, n)
	# i rumori vengono comunicati al Killer
	if s["petardo"] != "":
		_ev("Un PETARDO esplode: rumore ovunque! (segnalino nel %s)" % nome_luogo(s["petardo"]), "tutti", {"tipo": "petardo", "luogo": s["petardo"]})
	elif s["rumori"].is_empty():
		_ev("Nessun rumore in questo turno.", "K", {"tipo": "rumori", "luoghi": []})
	else:
		var nomi := []
		for l in s["rumori"]:
			nomi.append(nome_luogo(l))
		_ev("Rumori da: %s." % ", ".join(nomi), "K", {"tipo": "rumori", "luoghi": s["rumori"].duplicate()})
	cambiato.emit()

func _scoperta() -> void:
	if s["scoperta"].is_empty():
		if s["soccorso"] > 0:
			return
		_fine("K", "il mazzo scoperta è esaurito: la notte non finisce mai.")
		return
	var vv := vivi()
	var d := await chiedi("S", {"tipo": "scoperta_chi", "titolo": "Scoperta: chi pesca 2 carte?"})
	var i := int(d.get("i", vv[0]))
	if not vv.has(i):
		i = vv[0]
	var pescate := []
	for k in mini(2, s["scoperta"].size()):
		pescate.append(s["scoperta"].pop_back())
	var d2 := await chiedi("S", {"tipo": "scoperta_tieni", "i": i, "carte": pescate,
		"titolo": "%s scopre: quale carta tieni?" % nome_s(i)})
	var t := int(d2.get("tieni", 0))
	for k in pescate.size():
		var o: String = pescate[k]
		if Dati.OGGETTI[o].get("rumore", false):
			_rumore(s["sopr"][i]["pos"], Dati.OGGETTI[o]["nome"])
	for k in pescate.size():
		if k == t:
			await _prendi_oggetto(i, pescate[k])
		else:
			s["scarti_ogg"].append(pescate[k])
	_ev("Scoperta: restano %d carte." % s["scoperta"].size(), "tutti", {"tipo": "scoperta"})

## Le possibili azioni dei Sopravvissuti (per l'interfaccia e per l'IA).
func azioni_possibili(i: int) -> Dictionary:
	var p: Dictionary = s["sopr"][i]
	var out := {}
	if not p["vivo"] or s["fase"] != "S":
		return out
	var l: String = p["pos"]
	var killer_qui: bool = killer_blocca(l)
	if p.get("no_extra", false):
		# dopo aver congelato una Statua: niente azioni extra in questo turno (gli scambi sì)
		var compagni0 := []
		for j in in_luogo(l):
			if j != i:
				compagni0.append(j)
		if not compagni0.is_empty() and not p["oggetti"].is_empty():
			out["scambia"] = compagni0
		return out
	var ld: Dictionary = mappa["luoghi"][l]
	if not p["agito"]:
		# espansioni: azioni speciali
		if s["killer"]["id"] == "statue":
			var qui := statue_in(l)
			if qui.size() == 1 and s["statue"][qui[0]]["gelo"] <= 0:
				out["congela"] = true
		if s["nuclei"].has(l):
			out["nucleo"] = true
		if ld.get("reliquie", false) and not s["reliquie_aperte"]:
			out["apri_reliquie"] = true
		if ld.get("macerie", false) and s["crollo_s"] == "" and s["crollo_k"] != l:
			out["crollo"] = true
		if ld.get("reliquie", false) and s["reliquie_aperte"] and not s["reliquie"].is_empty() and not killer_qui:
			out["cerca_reliquie"] = true
		out["muovi"] = true
		if p["paura"] > 0:
			out["paura"] = true
		var bl := []
		for b in s["blocchi"]:
			if l in b.split("|"):
				bl.append(b)
		if not bl.is_empty():
			out["blocco"] = bl
		if mappa["luoghi"][l].get("radio", false) and s["riparazione"] < Dati.RIPARAZIONE_MAX and not s["riparato_turno"] and not killer_qui:
			out["ripara"] = true
		var luogo_cerca: bool = mappa["luoghi"][l].get("chiave", false) or (p["id"] == "caleb" and mappa["luoghi"][l].get("spirale", false))
		if luogo_cerca and not killer_qui and not s["ricerca"].is_empty():
			out["cerca"] = true
		if p["id"] == "william":
			out["scatto"] = true
		if p["id"] == "sophia" and not passaggi_di(l).is_empty() and not ha_oggetto(i, "torcia"):
			out["passaggio"] = passaggi_di(l)
		if p["id"] == "marco":
			var ris := []
			for o in ["adrenalina", "tranquillante"]:
				if s["scarti_ogg"].has(o):
					ris.append(o)
			if not ris.is_empty():
				out["risorse"] = ris
		if p["id"] == "george" and mappa["luoghi"][l].get("libro", false):
			var sc := []
			if ha_oggetto(i, "cassetta") and s["riparazione"] < Dati.RIPARAZIONE_MAX:
				sc.append("cassetta")
			if not s["ricerca"].is_empty():
				sc.append("ricerca")
			if not sc.is_empty():
				out["mente"] = sc
		if p["id"] == "ophelia":
			var bers := []
			for j in in_luogo(l):
				if s["sopr"][j]["paura"] > 0 or not s["sopr"][j]["incoraggiamento"]:
					bers.append(j)
			if not bers.is_empty():
				out["incoraggia"] = bers
	# extra sempre disponibili
	if p["id"] == "sophia" and not passaggi_di(l).is_empty() and ha_oggetto(i, "torcia"):
		out["passaggio_extra"] = passaggi_di(l)
	if mappa["luoghi"][l].get("valigia", false) and s["valigia_su"] and not s["scoperta"].is_empty():
		out["valigia"] = true
	if mappa["luoghi"][l].get("leva", false):
		out["leva"] = true
	if p["id"] == "dylan" and mappa["luoghi"][l].get("martello", false) and s["scarti_ogg"].has("cassetta"):
		out["meccanica"] = true
	if s["forzieri"].has(l) and not s["argento"].is_empty():
		out["forziere"] = true
	# oggetti utilizzabili
	var usi := []
	for k in p["oggetti"].size():
		if puo_usare(i, k):
			usi.append(k)
	if not usi.is_empty():
		out["usa"] = usi
	# scambi
	var compagni := []
	for j in in_luogo(l):
		if j != i:
			compagni.append(j)
	if not compagni.is_empty() and not p["oggetti"].is_empty():
		out["scambia"] = compagni
	return out

## Un oggetto si può usare adesso? (azioni speciali solo se non si è ancora agito)
func puo_usare(i: int, k: int) -> bool:
	var p: Dictionary = s["sopr"][i]
	var o: String = p["oggetti"][k]
	var od: Dictionary = Dati.OGGETTI[o]
	if od.has("solo") and od["solo"] != p["id"]:
		return false
	var l: String = p["pos"]
	match o:
		"cassetta":
			return not p["agito"] and mappa["luoghi"][l].get("radio", false) and s["riparazione"] < Dati.RIPARAZIONE_MAX \
				and not s["riparato_turno"] and not killer_blocca(l)
		"erbe":
			if p["agito"]:
				return false
			for j in in_luogo(l):
				if ha_bisogno_cura(j):
					return true
			return false
		"kit_medico":
			if p["agito"]:
				return false
			for j in in_luogo(l):
				if ha_bisogno_cura(j) or s["sopr"][j]["paura"] > 0:
					return true
			return false
		"balestra":
			if p["agito"]:
				return false
			for z in s["zombi"]:
				if distanza(l, z) <= 1:
					return true
			return false
		"specchio":
			for x in mappa["luoghi"]:
				if mappa["luoghi"][x].get("spirale", false) and x != l and not (s["crollo_k"] == x):
					return true
			return false
		"sfera":
			return not p["agito"] and mappa["luoghi"][l].get("chiave", false) and not s["ricerca"].is_empty() and not killer_blocca(l)
		"trappola":
			return not p["agito"]
		"accetta":
			for b in s["blocchi"]:
				if l in b.split("|"):
					return true
			return false
		"adrenalina":
			return not passi_sopr(i, l).is_empty()
		"tranquillante":
			for j in in_luogo(l):
				if s["sopr"][j]["paura"] > 0:
					return true
			return false
		"whisky", "petardo", "macchina_foto", "nota_rumore":
			return true
		"moneta":
			return not p["moneta"] and not s["ricerca"].is_empty()
		"nota_blocchi":
			for b in s["blocchi"]:
				if l in b.split("|"):
					return true
			return false
	return false

func _percorso_valido(i: int, perc: Array, nmax: int, con_passaggi := false) -> bool:
	if perc.is_empty() or perc.size() > nmax:
		return false
	var da: String = s["sopr"][i]["pos"]
	for l in perc:
		if not passi_sopr(i, da, con_passaggi).has(l):
			return false
		da = l
	return true

func _muovi_sopr(i: int, perc: Array, come := "") -> void:
	var p: Dictionary = s["sopr"][i]
	var da: String = p["pos"]
	# trappole della Cacciatrice: la prima che si incontra scatta e ferma il movimento
	var scatta := ""
	for n in perc.size():
		if s["trappole_k"].has(perc[n]):
			scatta = perc[n]
			perc = perc.slice(0, n + 1)
			break
	p["pos"] = perc[-1]
	if s.get("statua_corridoio", false):
		for l in perc:
			if mappa["luoghi"][l].get("statua", false):
				s["statua_corridoio"] = false
				_ev("Nel %s una statua si volta verso %s!" % [nome_luogo(l), nome_s(i)], "tutti", {"tipo": "statua", "luogo": l})
				_paura_subito(i)
				break
	var nomi := []
	for l in perc:
		nomi.append(nome_luogo(l))
	_ev("%s%s: %s → %s." % [nome_s(i), (" " + come) if come != "" else "", nome_luogo(da), " → ".join(nomi)], "S",
		{"tipo": "movimento_s", "i": i, "percorso": [da] + perc})
	if scatta != "":
		var t: String = s["trappole_k"][scatta]
		s["trappole_k"].erase(scatta)
		s["trappole_scattate"].append(t)
		_ev("SCATTA UNA TRAPPOLA! %s finisce in una %s nel %s." % [nome_s(i), Dati.TRAPPOLE[t]["nome"], nome_luogo(scatta)], "tutti",
			{"tipo": "trappola_scattata", "i": i, "luogo": scatta, "trappola": t})
		match t:
			"tagliola":
				_danno(i, "la Tagliola")
			"teschi":
				_paura_subito(i)
				_paura_subito(i)
			"rete":
				p["intrappolato"] = true
				_ev("%s è avvolto nella rete: non può lasciare il luogo in questo turno." % nome_s(i), "tutti")

## Esegue un'azione dei Sopravvissuti. Restituisce false se non è valida.
func esegui_s(d: Dictionary) -> bool:
	var a: String = d.get("a", "")
	var i := int(d.get("i", -1))
	if a == "scambia":
		return await _scambia(d)
	if i < 0 or i >= s["sopr"].size():
		return false
	var p: Dictionary = s["sopr"][i]
	var poss := azioni_possibili(i)
	var l: String = p["pos"]
	match a:
		"muovi":
			var perc: Array = d.get("percorso", [])
			if not poss.has("muovi") or not _percorso_valido(i, perc, 2):
				return false
			p["agito"] = true
			_muovi_sopr(i, perc)
		"scatto":
			var perc: Array = d.get("percorso", [])
			if not poss.has("scatto") or not _percorso_valido(i, perc, 3):
				return false
			p["agito"] = true
			_muovi_sopr(i, perc, "scatta")
			_rumore(p["pos"], "Scatto")
		"paura":
			if not poss.has("paura"):
				return false
			p["agito"] = true
			p["paura"] = 0
			_ev("%s si calma: paura azzerata." % nome_s(i), "tutti", {"tipo": "calma", "i": i})
		"blocco":
			var b: String = d.get("porta", "")
			if not poss.has("blocco") or not poss["blocco"].has(b):
				return false
			p["agito"] = true
			s["blocchi"].erase(b)
			_ev("%s rimuove il blocco tra %s e %s." % [nome_s(i), nome_luogo(b.split("|")[0]), nome_luogo(b.split("|")[1])], "tutti",
				{"tipo": "sblocco", "porta": b})
		"ripara":
			if not poss.has("ripara"):
				return false
			p["agito"] = true
			_ripara(i, 1)
		"cerca":
			if not poss.has("cerca"):
				return false
			p["agito"] = true
			await _cerca(i)
		"passaggio", "passaggio_extra":
			if not poss.has(a):
				return false
			var dest: String = d.get("dest", poss[a][0])
			if not poss[a].has(dest):
				dest = poss[a][0]
			if a == "passaggio":
				p["agito"] = true
			_muovi_sopr(i, [dest], "usa il passaggio segreto")
		"valigia":
			if not poss.has("valigia"):
				return false
			s["valigia_su"] = false
			var o: String = s["scoperta"].pop_back()
			_ev("%s fruga nella valigia." % nome_s(i), "S", {"tipo": "valigia"})
			if Dati.OGGETTI[o].get("rumore", false):
				_rumore(l, Dati.OGGETTI[o]["nome"])
			var dv := await chiedi("S", {"tipo": "cerca_tieni", "i": i, "carta": o, "titolo": "%s trova nella valigia: %s. La tieni?" % [nome_s(i), Dati.OGGETTI[o]["nome"]]})
			if dv.get("tieni", true):
				await _prendi_oggetto(i, o)
			else:
				s["scarti_ogg"].append(o)
		"leva":
			var pt: String = d.get("porta", "")
			if not poss.has("leva") or not _porte.has(pt) or _porte[pt]["tipo"] != "porta":
				return false
			s["cancello"] = pt
			_ev("%s aziona le leve: il cancello cala tra %s e %s." % [nome_s(i), nome_luogo(pt.split("|")[0]), nome_luogo(pt.split("|")[1])], "tutti",
				{"tipo": "cancello", "porta": pt})
		"risorse":
			var o: String = d.get("ogg", "")
			if not poss.has("risorse") or not poss["risorse"].has(o):
				return false
			p["agito"] = true
			s["scarti_ogg"].erase(o)
			await _prendi_oggetto(i, o)
		"mente":
			var sc: String = d.get("scelta", "")
			if not poss.has("mente") or not poss["mente"].has(sc):
				return false
			p["agito"] = true
			if sc == "cassetta":
				_scarta_oggetto(i, "cassetta")
				s["riparazione"] = mini(Dati.RIPARAZIONE_MAX, s["riparazione"] + 1)
				_ev("George studia gli schemi: riparazione %d/5." % s["riparazione"], "S", {"tipo": "riparazione"})
				_controlla_radio()
			else:
				var o: String = s["ricerca"].pop_back()
				_ev("George consulta i libri e pesca dal mazzo ricerca.", "S")
				await _proponi_carta(i, o, false)
		"incoraggia":
			var j := int(d.get("bersaglio", -1))
			if not poss.has("incoraggia") or not poss["incoraggia"].has(j):
				return false
			p["agito"] = true
			s["sopr"][j]["paura"] = 0
			s["sopr"][j]["incoraggiamento"] = true
			_ev("Ophelia incoraggia %s: paura azzerata." % nome_s(j), "tutti", {"tipo": "calma", "i": j})
		"meccanica":
			if not poss.has("meccanica"):
				return false
			s["scarti_ogg"].erase("cassetta")
			await _prendi_oggetto(i, "cassetta")
		"congela":
			if not poss.has("congela"):
				return false
			var j: int = statue_in(l)[0]
			p["agito"] = true
			p["no_extra"] = true
			s["statue"][j]["gelo"] = 1
			_ev("%s congela la Statua %s nel %s: non potrà muoversi né cercare." % [nome_s(i), s["statue"][j]["nome"], nome_luogo(l)], "tutti",
				{"tipo": "gelo", "statua": j, "luogo": l})
		"nucleo":
			if not poss.has("nucleo"):
				return false
			p["agito"] = true
			s["nuclei"].erase(l)
			_ev("%s strappa un nucleo nel %s." % [nome_s(i), nome_luogo(l)], "tutti", {"tipo": "nucleo_tolto", "luogo": l})
		"apri_reliquie":
			if not poss.has("apri_reliquie"):
				return false
			p["agito"] = true
			s["reliquie_aperte"] = true
			_ev("%s forza il sigillo: la Camera delle reliquie è aperta!" % nome_s(i), "tutti", {"tipo": "reliquie"})
			_rumore(l, "il sigillo infranto")
		"cerca_reliquie":
			if not poss.has("cerca_reliquie"):
				return false
			p["agito"] = true
			var o: String = s["reliquie"].pop_back()
			_ev("%s cerca tra le reliquie." % nome_s(i), "S")
			await _proponi_carta(i, o, true)
		"crollo":
			if not poss.has("crollo"):
				return false
			p["agito"] = true
			s["crollo_s"] = l
			_ev("%s fa crollare il %s: il Killer non potrà più entrarci!" % [nome_s(i), nome_luogo(l)], "tutti", {"tipo": "crollo", "luogo": l})
			_rumore(l, "il crollo")
		"forziere":
			if not poss.has("forziere"):
				return false
			s["forzieri"].erase(l)
			var o: String = s["argento"].pop_back()
			_ev("%s apre un forziere nel %s." % [nome_s(i), nome_luogo(l)], "tutti", {"tipo": "forziere", "luogo": l})
			await _prendi_oggetto(i, o)
		"usa":
			return await _usa(i, d)
		_:
			return false
	return true

func _ripara(i: int, quanto: int) -> void:
	s["riparato_turno"] = true
	s["riparazione"] = mini(Dati.RIPARAZIONE_MAX, s["riparazione"] + quanto)
	_ev("%s ripara la radio: %d/5." % [nome_s(i), s["riparazione"]], "S", {"tipo": "riparazione"})
	_rumore(s["sopr"][i]["pos"], "riparazione")
	_controlla_radio()

func _controlla_radio() -> void:
	if s["riparazione"] >= Dati.RIPARAZIONE_MAX and s["soccorso"] < 0:
		s["soccorso"] = Dati.SOCCORSO_TURNI
		_ev("LA RADIO FUNZIONA! Chiamata di soccorso: arriveranno tra %d turni." % Dati.SOCCORSO_TURNI, "tutti", {"tipo": "radio"})

func _cerca(i: int) -> void:
	var p: Dictionary = s["sopr"][i]
	if p["id"] == "ophelia" and s["ricerca"].size() >= 2:
		var c1: String = s["ricerca"].pop_back()
		var c2: String = s["ricerca"].pop_back()
		var d := await chiedi("S", {"tipo": "cerca_ophelia", "i": i, "carte": [c1, c2],
			"titolo": "Sesto senso: quale carta tieni? L'altra torna in cima al mazzo."})
		var t := int(d.get("tieni", 0))
		var tenuta: String = c1 if t == 0 else c2
		var resa: String = c2 if t == 0 else c1
		s["ricerca"].append(resa)
		await _proponi_carta(i, tenuta, true)
		return
	var o: String = s["ricerca"].pop_back()
	await _proponi_carta(i, o, true)

## Una carta pescata dal mazzo ricerca: fa rumore (se è rumorosa e non è Anna) e si può tenere o scartare.
func _proponi_carta(i: int, o: String, ricerca: bool) -> void:
	var p: Dictionary = s["sopr"][i]
	if Dati.OGGETTI[o].get("rumore", false) and not (ricerca and p["id"] == "anna"):
		_rumore(p["pos"], Dati.OGGETTI[o]["nome"])
	var d := await chiedi("S", {"tipo": "cerca_tieni", "i": i, "carta": o, "titolo": "%s trova: %s. La tieni?" % [nome_s(i), Dati.OGGETTI[o]["nome"]]})
	if d.get("tieni", true):
		await _prendi_oggetto(i, o)
	else:
		s["scarti_ogg"].append(o)
		_ev("%s lascia %s." % [nome_s(i), Dati.OGGETTI[o]["nome"]], "S")

func _scambia(d: Dictionary) -> bool:
	var i := int(d.get("i", -1))
	var j := int(d.get("verso", -1))
	var k := int(d.get("ogg", -1))
	if i < 0 or j < 0 or i == j or i >= s["sopr"].size() or j >= s["sopr"].size():
		return false
	var p: Dictionary = s["sopr"][i]
	var q: Dictionary = s["sopr"][j]
	if not p["vivo"] or not q["vivo"] or p["pos"] != q["pos"] or k < 0 or k >= p["oggetti"].size():
		return false
	var o: String = p["oggetti"][k]
	p["oggetti"].remove_at(k)
	_ev("%s dà %s a %s." % [nome_s(i), Dati.OGGETTI[o]["nome"], nome_s(j)], "S")
	q["oggetti"].append(o)
	while q["oggetti"].size() > limite_oggetti(j):
		var dd := await chiedi("S", {"tipo": "troppi_oggetti", "i": j, "titolo": "%s ha troppi oggetti: scegline uno da scartare" % nome_s(j)})
		var idx := int(dd.get("ogg", 0))
		if idx < 0 or idx >= q["oggetti"].size():
			idx = q["oggetti"].size() - 1
		s["scarti_ogg"].append(q["oggetti"][idx])
		q["oggetti"].remove_at(idx)
	return true

func _usa(i: int, d: Dictionary) -> bool:
	var p: Dictionary = s["sopr"][i]
	var k := int(d.get("ogg", -1))
	if k < 0 or k >= p["oggetti"].size() or not puo_usare(i, k):
		return false
	var o: String = p["oggetti"][k]
	var l: String = p["pos"]
	var od: Dictionary = Dati.OGGETTI[o]
	match o:
		"cassetta":
			p["agito"] = true
			_scarta_oggetto(i, o)
			_ripara(i, 3 if p["id"] == "johnson" else 2)
		"erbe":
			var j := int(d.get("bersaglio", i))
			if not in_luogo(l).has(j) or not ha_bisogno_cura(j):
				j = -1
				for x in in_luogo(l):
					if ha_bisogno_cura(x):
						j = x
			if j < 0:
				return false
			p["agito"] = true
			_scarta_oggetto(i, o)
			_cura(j)
			_rumore(l, "Erbe medicinali")
		"kit_medico":
			var j := int(d.get("bersaglio", i))
			if not in_luogo(l).has(j):
				j = i
			p["agito"] = true
			_cura(j)
			s["sopr"][j]["paura"] = 0
			_ev("Marco medica %s: niente più paura." % nome_s(j), "tutti", {"tipo": "calma", "i": j})
		"trappola":
			p["agito"] = true
			_scarta_oggetto(i, o)
			s["trappola"] = l
			_ev("%s piazza una trappola nel %s." % [nome_s(i), nome_luogo(l)], "S", {"tipo": "trappola"})
		"accetta":
			var b: String = d.get("porta", "")
			var possibili := []
			for x in s["blocchi"]:
				if l in x.split("|"):
					possibili.append(x)
			if not possibili.has(b):
				b = possibili[0]
			_scarta_oggetto(i, o)
			s["blocchi"].erase(b)
			_ev("%s abbatte il blocco tra %s e %s con l'Accetta." % [nome_s(i), nome_luogo(b.split("|")[0]), nome_luogo(b.split("|")[1])], "tutti",
				{"tipo": "sblocco", "porta": b})
		"nota_blocchi":
			_scarta_oggetto(i, o)
			var tolti := 0
			for x in s["blocchi"].duplicate():
				if l in x.split("|") and tolti < 2:
					s["blocchi"].erase(x)
					tolti += 1
					_ev("George rimuove il blocco tra %s e %s." % [nome_luogo(x.split("|")[0]), nome_luogo(x.split("|")[1])], "tutti",
						{"tipo": "sblocco", "porta": x})
		"adrenalina":
			var perc: Array = d.get("percorso", [])
			if not _percorso_valido(i, perc, 1):
				return false
			_scarta_oggetto(i, o)
			_muovi_sopr(i, perc, "(Adrenalina)")
		"tranquillante":
			var j := int(d.get("bersaglio", i))
			if not in_luogo(l).has(j) or s["sopr"][j]["paura"] == 0:
				j = -1
				for x in in_luogo(l):
					if s["sopr"][x]["paura"] > 0:
						j = x
			if j < 0:
				return false
			_scarta_oggetto(i, o)
			s["sopr"][j]["paura"] = 0
			_ev("%s prende il Tranquillante: paura azzerata." % nome_s(j), "tutti", {"tipo": "calma", "i": j})
		"whisky":
			var dove: String = d.get("luogo", "")
			if not entro(l, 1).has(dove):
				return false
			_scarta_oggetto(i, o)
			_rumore(dove, "una bottiglia in frantumi")
		"petardo":
			_scarta_oggetto(i, o)
			s["petardo"] = killer_visto()
			_ev("%s accende un Petardo!" % nome_s(i), "S", {"tipo": "petardo_s"})
		"macchina_foto":
			_scarta_oggetto(i, o)
			_rumore(l, "un flash")
		"nota_rumore":
			var dove: String = d.get("luogo", "")
			if not mappa["luoghi"].has(dove):
				return false
			_scarta_oggetto(i, o)
			_rumore(dove, "Nota di George")
		"moneta":
			p["moneta"] = true
			var c: String = s["ricerca"].pop_back()
			s["scarti_ogg"].append(c)
			if c == "chiave":
				_ev("La moneta di Caleb: era una Chiave (scartata). Caleb si cura.", "S")
				_cura(i)
			else:
				_ev("La moneta di Caleb scarta %s." % Dati.OGGETTI[c]["nome"], "S")
				var perc: Array = d.get("percorso", [])
				if not perc.is_empty() and _percorso_valido(i, perc, 2):
					_muovi_sopr(i, perc, "(Moneta)")
		"balestra":
			p["agito"] = true
			# elimina fino a 2 zombi: prima nel proprio luogo, poi negli adiacenti più affollati
			var cand := []
			for z in s["zombi"]:
				if distanza(l, z) <= 1:
					cand.append(z)
			cand.sort_custom(func(a, b): return distanza(l, a) < distanza(l, b) or (distanza(l, a) == distanza(l, b) and a < b))
			var scelti: Array = d.get("luoghi", [])
			var tolti := 0
			for z in scelti:
				if tolti < 2 and cand.has(z):
					cand.erase(z)
					s["zombi"].erase(z)
					tolti += 1
					_ev("%s abbatte uno zombi nel %s con la Balestra." % [nome_s(i), nome_luogo(z)], "tutti", {"tipo": "zombi_tolto", "luogo": z})
			while tolti < 2 and not cand.is_empty():
				var z: String = cand.pop_front()
				s["zombi"].erase(z)
				tolti += 1
				_ev("%s abbatte uno zombi nel %s con la Balestra." % [nome_s(i), nome_luogo(z)], "tutti", {"tipo": "zombi_tolto", "luogo": z})
		"specchio":
			var dest := ""
			for x in mappa["luoghi"]:
				if mappa["luoghi"][x].get("spirale", false) and x != l:
					dest = x
			_scarta_oggetto(i, o)
			_muovi_sopr(i, [dest], "attraversa lo Specchio")
		"sfera":
			p["agito"] = true
			await _cerca(i)
			if not s["ricerca"].is_empty() and s["vincitore"] == "":
				await _cerca(i)
		_:
			return false
	return true

# ================================================================ turno del Killer

func forza() -> int:
	var k: Dictionary = s["killer"]
	var est: int = k["bonus_esteso"] if s["turno"] <= int(k["bonus_esteso_fino"]) else 0
	return mini(Dati.FORZA_MAX, k["forza_base"] + k["bonus_livello"] + k["bonus_turno"] + k["bonus_attacco"] + k["forza_perm"] + est)

## La Forza di un attacco: per la Regina si sommano Regina e zombi presenti.
func forza_attacco() -> int:
	var k: Dictionary = s["killer"]
	var f := forza()
	if int(k["molt"]) != 1:
		f = (f - int(k["bonus_attacco"])) * int(k["molt"]) + int(k["bonus_attacco"])
	return f

func costo_carta(id: String) -> int:
	var c: int = carta(id)["costo"]
	if c > 0 and s["killer"]["id"] == "cacciatrice" and s["killer"]["livello"] >= 3:
		c -= 1
	return c

## Condizioni particolari per giocare una carta.
func condizione(id: String) -> bool:
	var k: Dictionary = s["killer"]
	match carta(id).get("cond", ""):
		"ferito":
			for i in vivi():
				if s["sopr"][i]["ferite"] > 0:
					return true
			return false
		"zombi":
			return not s["zombi"].is_empty()
		"regina_presente":
			return int(k.get("regina_qui", 0)) == 1
		"agguato":
			return k["riappare_ora"] or k["passaggio_turno"]
	match id:
		"orda", "prendeteli", "esplosione":
			return not s["zombi"].is_empty()
		"rampicante":
			return not s["nuclei"].is_empty()
	return true

func nome_k() -> String:
	return Dati.KILLER[s["killer"]["id"]]["nome"]

func carta(id: String) -> Dictionary:
	return Dati.CARTE_KILLER[id]

func tipo_carta(id: String) -> String:
	if id == "motosega" and s["killer"]["motosega_veloce"]:
		return "veloce"
	return carta(id)["tipo"]

## Si può pagare il costo di questa carta (indice nella mano)?
func pagabile(idx: int) -> bool:
	var mano: Array = s["killer"]["mano"]
	var c: int = costo_carta(mano[idx])
	if c < 0:
		return true
	return mano.size() - 1 >= c and condizione(mano[idx])

func giocabili(tipo: String) -> Array:
	var out := []
	var mano: Array = s["killer"]["mano"]
	for k in mano.size():
		var id: String = mano[k]
		var ok: bool = tipo_carta(id) == tipo or carta(id).get("tipi", []).has(tipo)
		if ok and pagabile(k):
			out.append(k)
	return out

func _turno_killer() -> void:
	var k: Dictionary = s["killer"]
	s["fase"] = "K"
	k["incontro"] = false
	k["bonus_turno"] = 0
	k["bonus_attacco"] = 0
	k["passaggio_turno"] = false
	k["riappare_ora"] = false
	_ev("— Turno %d: %s —" % [s["turno"], nome_k()], "tutti", {"tipo": "turno"})
	cambiato.emit()
	# Propriocezione sonora (evoluzione del Non Identificato)
	if k["evoluzioni"].has("sonar"):
		var riv := []
		if s["rumori"].is_empty():
			for i in vivi():
				if distanza(s["sopr"][i]["pos"], k["pos"]) <= 1:
					riv.append(i)
		else:
			for i in vivi():
				if s["rumori"].has(s["sopr"][i]["pos"]):
					riv.append(i)
		for i in riv:
			_ev("Propriocezione sonora: %s è nel %s." % [nome_s(i), nome_luogo(s["sopr"][i]["pos"])], "tutti",
				{"tipo": "rivelato", "i": i, "luogo": s["sopr"][i]["pos"]})
	if k["furtivo"]:
		await _riappari()
	# carte veloci
	k["fase_carta"] = "veloce"
	if not k["incontro"] and s["vincitore"] == "":
		var giri := 0
		while giri < 20:
			giri += 1
			var g := giocabili("veloce")
			if g.is_empty():
				break
			var d := await chiedi("K", {"tipo": "veloce", "carte": g, "titolo": "Carte veloci: giocane una o prosegui"})
			var idx := int(d.get("carta", -1))
			if idx < 0 or not g.has(idx):
				break
			await _gioca_carta(idx)
			cambiato.emit()
			if k["incontro"] or s["vincitore"] != "":
				break
	# carta speciale oppure 2 azioni
	k["fase_carta"] = "speciale"
	if not k["incontro"] and s["vincitore"] == "":
		var g := giocabili("speciale")
		var d := await chiedi("K", {"tipo": "principale", "carte": g, "titolo": "Gioca una carta speciale oppure fai 2 azioni"})
		var idx := int(d.get("carta", -1))
		if idx >= 0 and g.has(idx):
			await _gioca_carta(idx)
		else:
			for n in 2:
				if k["incontro"] or s["vincitore"] != "":
					break
				await _azione_base(n)
				cambiato.emit()
	# carte lente (solo se non c'è stato un incontro; lo Strangolatore ne può giocare più d'una)
	k["fase_carta"] = "lenta"
	var lente := 0
	while not k["incontro"] and s["vincitore"] == "" and lente < 6:
		var g := giocabili("lenta")
		if g.is_empty():
			break
		var d := await chiedi("K", {"tipo": "lenta", "carte": g, "titolo": "Puoi giocare una carta lenta"})
		var idx := int(d.get("carta", -1))
		if idx < 0 or not g.has(idx):
			break
		await _gioca_carta(idx)
		lente += 1
		cambiato.emit()
		if k["id"] != "strangolatore":
			break
	k["fase_carta"] = ""
	if s["vincitore"] != "":
		return
	await _fine_turno_k()
	if s["vincitore"] != "":
		return
	# pesca 3
	await _pesca_fine_turno()
	# il gelo delle Statue finisce
	for st in s["statue"]:
		if st["gelo"] > 0:
			st["gelo"] -= 1
	cambiato.emit()

## Le 2 azioni base: [MUOVI] x1 oppure [CERCA]. Le Statue scelgono quale Statua agisce.
func _azione_base(n: int) -> void:
	var k: Dictionary = s["killer"]
	if k["id"] == "statue":
		var libere := []
		var opz := []
		for j in s["statue"].size():
			if s["statue"][j]["gelo"] <= 0:
				libere.append(j)
				opz.append("Statua %s%s (%s)" % [s["statue"][j]["nome"], " ★" if j == k["principale"] else "", nome_luogo(s["statue"][j]["pos"])])
		if libere.is_empty():
			return
		var ds := await chiedi("K", {"tipo": "scelta", "opzioni": opz, "scopo": "statua_azione",
			"titolo": "Azione %d di 2: quale Statua agisce?" % (n + 1)})
		var j: int = libere[clampi(int(ds.get("n", 0)), 0, libere.size() - 1)]
		var pos: String = s["statue"][j]["pos"]
		var d2 := await chiedi("K", {"tipo": "azione_k", "n": n + 1, "vicini": vicini_k(pos), "da": pos,
			"titolo": "Statua %s: [MUOVI] x1 o [CERCA]" % s["statue"][j]["nome"]})
		if d2.get("a", "") == "muovi" and vicini_k(pos).has(d2.get("dest", "")):
			_passo_statua(j, d2["dest"])
		elif d2.get("a", "") == "cerca":
			await _cerca_luogo(pos, "la Statua %s" % s["statue"][j]["nome"])
		return
	var d2 := await chiedi("K", {"tipo": "azione_k", "n": n + 1, "vicini": vicini_k(k["pos"]), "da": k["pos"],
		"titolo": "Azione %d di 2: [MUOVI] x1 o [CERCA]" % (n + 1)})
	if d2.get("a", "") == "muovi" and vicini_k(k["pos"]).has(d2.get("dest", "")):
		await _passo_killer(d2["dest"])
	elif d2.get("a", "") == "cerca":
		await _cerca_k()
	elif d2.get("a", "") == "crollo" and _puo_crollare():
		_crollo_k()

func _puo_crollare() -> bool:
	var k: Dictionary = s["killer"]
	return s["crollo_k"] == "" and mappa["luoghi"][k["pos"]].get("macerie", false) and s["crollo_s"] != k["pos"] and not k["furtivo"]

func _crollo_k() -> void:
	var l: String = s["killer"]["pos"]
	s["crollo_k"] = l
	_ev("%s fa crollare il %s: i Sopravvissuti non potranno più entrarci!" % [nome_k(), nome_luogo(l)], "tutti", {"tipo": "crollo", "luogo": l})
	for i in in_luogo(l):
		_paura_subito(i)

## Fine del turno del Killer: effetti dei livelli e delle evoluzioni.
func _fine_turno_k() -> void:
	var k: Dictionary = s["killer"]
	if k["incontro"] or k["furtivo"]:
		return
	match k["id"]:
		"lupo":
			if k["livello"] >= 4:
				await _paura_raggio(2)
		"regina":
			_zombi_sorge(k["pos"])
	if k["evoluzioni"].has("ghiandole"):
		await _blocca_qui(1)

func _zombi_sorge(l: String) -> void:
	if s["zombi"].size() >= 6:
		_ev("Non ci sono altri zombi.", "K")
		return
	s["zombi"].append(l)
	_ev("Uno zombi sorge nel %s." % nome_luogo(l), "tutti", {"tipo": "zombi", "luogo": l})

func _pesca_killer_una() -> String:
	var k: Dictionary = s["killer"]
	if k["mazzo"].is_empty():
		await _sali_livello()
		if k["mazzo"].is_empty():
			return ""
	return k["mazzo"].pop_back()

func _pesca_fine_turno() -> void:
	var k: Dictionary = s["killer"]
	var pescate := 0
	for n in 3:
		var c: String = await _pesca_killer_una()
		if c == "":
			break
		if k["mano"].size() >= Dati.MANO_MAX:
			k["scarti"].append(c)
		else:
			k["mano"].append(c)
			pescate += 1
	_ev("%s pesca %d carte (mano: %d)." % [nome_k(), pescate, k["mano"].size()], "K", {"tipo": "pesca"})

## Scarta 2 carte dal mazzo (difesa riuscita dei Sopravvissuti).
func _scarta_dal_mazzo(n: int) -> void:
	var k: Dictionary = s["killer"]
	for i in n:
		var c: String = await _pesca_killer_una()
		if c != "":
			k["scarti"].append(c)

func _sali_livello() -> void:
	var k: Dictionary = s["killer"]
	# rimescola gli scarti
	k["mazzo"] = k["scarti"]
	k["scarti"] = []
	_mescola(k["mazzo"])
	if k["livello"] >= 5:
		return
	k["livello"] += 1
	var lv: int = k["livello"]
	_ev("%s sale al LIVELLO %d: %s" % [nome_k(), lv, Dati.KILLER[k["id"]]["livelli"][lv - 1]], "tutti", {"tipo": "livello"})
	match k["id"]:
		"macellaio":
			if lv == 2:
				k["bonus_livello"] += 1
			elif lv == 3:
				await _sblocca()
			elif lv == 4:
				k["motosega_veloce"] = true
		"spettro":
			if lv == 4:
				await _sblocca()
		"assassino":
			if lv == 3:
				await _sblocca()
			elif lv == 4:
				k["bonus_livello"] += 2
				for n in 4:
					if s["blocchi"].size() >= Dati.BLOCCHI_MAX and n > 0:
						break
					var tutte := []
					for p in _porte:
						if _porte[p]["tipo"] == "porta" and not s["blocchi"].has(p):
							tutte.append(p)
					if tutte.is_empty():
						break
					var d := await chiedi("K", {"tipo": "porta", "porte": tutte, "titolo": "Livello 4: [BLOCCA] una porta qualsiasi (%d/4)" % (n + 1)})
					var p: String = d.get("porta", "")
					if not tutte.has(p):
						p = tutte[0]
					_metti_blocco(p)
		"lupo":
			if lv == 2:
				await _sblocca()
			elif lv == 3:
				k["bonus_livello"] += 1
		"cacciatrice":
			if lv == 2:
				await _sblocca()
		"regina":
			if lv == 3:
				await _sblocca()
			elif lv == 4:
				var primo := ""
				for n in 2:
					var cand := []
					for l in mappa["luoghi"]:
						if l != primo:
							cand.append(l)
					var d := await chiedi("K", {"tipo": "luogo", "luoghi": cand, "scopo": "zombi",
						"titolo": "Livello 4: dove sorge uno zombi? (%d/2)" % (n + 1)})
					var l: String = d.get("dest", "")
					if not cand.has(l):
						l = cand[0]
					primo = l
					_zombi_sorge(l)
		"statue":
			if lv == 2:
				k["bonus_livello"] += 1
			elif lv == 3:
				await _sblocca()
			elif lv == 4:
				k["bonus_livello"] += 2
				if k["scarti"].has("accerchiamento"):
					k["scarti"].erase("accerchiamento")
					k["mano"].append("accerchiamento")
					_ev("Le Statue riprendono «Accerchiamento».", "K")
			# livello 1: a ogni salita si può cambiare la Statua principale
			await _scegli_principale("Sali di livello: vuoi cambiare la Statua principale?")
		"strangolatore":
			if lv == 2:
				_metti_nucleo(k["pos"])
			elif lv == 3:
				await _sblocca()
			elif lv == 4:
				var primo := ""
				for n in 2:
					var cand := []
					for l in mappa["luoghi"]:
						if l != primo:
							cand.append(l)
					var d := await chiedi("K", {"tipo": "luogo", "luoghi": cand, "scopo": "nucleo",
						"titolo": "Livello 4: dove metti un nucleo? (%d/2)" % (n + 1)})
					var l: String = d.get("dest", "")
					if not cand.has(l):
						l = cand[0]
					primo = l
					_metti_nucleo(l)
		"ignoto":
			if lv == 2 or lv == 4:
				var dispo := []
				var opz := []
				for e in Dati.EVOLUZIONI:
					if not k["evoluzioni"].has(e):
						dispo.append(e)
						opz.append("%s: %s" % [Dati.EVOLUZIONI[e]["nome"], Dati.EVOLUZIONI[e]["testo"]])
				var d := await chiedi("K", {"tipo": "scelta", "opzioni": opz, "scopo": "evoluzione", "chiavi": dispo,
					"titolo": "Livello %d: scegli una carta Evoluzione" % lv})
				var e: String = dispo[clampi(int(d.get("n", 0)), 0, dispo.size() - 1)]
				k["evoluzioni"].append(e)
				_ev("Il Non Identificato evolve: %s." % Dati.EVOLUZIONI[e]["nome"], "tutti", {"tipo": "evoluzione", "evo": e})
			elif lv == 3:
				var d := await chiedi("K", {"tipo": "scelta", "opzioni": ["Rumore stridente: " + carta("stridio")["testo"], "Sputo acido: " + carta("acido")["testo"]],
					"scopo": "ultima", "titolo": "Livello 3: quale carta sblocchi?"})
				k["bloccata"] = "acido" if int(d.get("n", 0)) == 1 else "stridio"
				await _sblocca()
	cambiato.emit()

func _scegli_principale(titolo: String) -> void:
	var k: Dictionary = s["killer"]
	var opz := []
	for j in s["statue"].size():
		opz.append("Statua %s%s (%s)" % [s["statue"][j]["nome"], " ★ (attuale)" if j == k["principale"] else "", nome_luogo(s["statue"][j]["pos"])])
	var d := await chiedi("K", {"tipo": "scelta", "opzioni": opz, "scopo": "principale", "titolo": titolo})
	var n := clampi(int(d.get("n", k["principale"])), 0, 3)
	if n != k["principale"]:
		k["principale"] = n
		_ev("La Statua principale ora è la %s." % s["statue"][n]["nome"], "K")
	_sync_statue()

func _metti_nucleo(l: String) -> void:
	if s["nuclei"].size() >= 5:
		_ev("Non ci sono altri nuclei.", "K")
		return
	s["nuclei"].append(l)
	_ev("Un nucleo germoglia nel %s." % nome_luogo(l), "tutti", {"tipo": "nucleo", "luogo": l})

func _sblocca() -> void:
	var k: Dictionary = s["killer"]
	var c: String = k["bloccata"]
	if c == "":
		return
	k["bloccata"] = ""
	_ev("%s sblocca «%s»." % [nome_k(), carta(c)["nome"]], "tutti", {"tipo": "sblocco_carta"})
	if k["mano"].size() >= Dati.MANO_MAX:
		var d := await chiedi("K", {"tipo": "scarta_mano", "titolo": "Mano piena: scarta una carta per far posto a «%s»" % carta(c)["nome"]})
		var idx := int(d.get("carta", 0))
		if idx < 0 or idx >= k["mano"].size():
			idx = 0
		k["scarti"].append(k["mano"][idx])
		k["mano"].remove_at(idx)
	k["mano"].append(c)

## Gioca la carta all'indice idx della mano: paga il costo, risolve l'effetto, la scarta.
func _gioca_carta(idx: int) -> void:
	var k: Dictionary = s["killer"]
	var id: String = k["mano"][idx]
	k["mano"].remove_at(idx)
	var costo: int = costo_carta(id)
	if costo < 0:
		costo = k["mano"].size()
	if costo > 0:
		var scelte: Array = []
		if k["mano"].size() > costo:
			var d := await chiedi("K", {"tipo": "costo", "n": costo, "carta": id,
				"titolo": "Costo di «%s»: scegli %d carte da scartare" % [carta(id)["nome"], costo]})
			scelte = d.get("carte", [])
		var valide := []
		for x in scelte:
			var xi := int(x)
			if xi >= 0 and xi < k["mano"].size() and not valide.has(xi):
				valide.append(xi)
		while valide.size() < costo:
			for x in k["mano"].size():
				if not valide.has(x):
					valide.append(x)
					break
		valide.sort()
		valide.reverse()
		for x in valide.slice(0, costo):
			k["scarti"].append(k["mano"][x])
			k["mano"].remove_at(x)
	_ev("%s gioca «%s»." % [nome_k(), carta(id)["nome"]], "tutti", {"tipo": "carta", "carta": id, "killer": k["id"]})
	k["cima"] = false
	await _effetto(id)
	if k.get("cima", false):
		k["mazzo"].append(id)
		k["cima"] = false
	else:
		k["scarti"].append(id)
	cambiato.emit()

## Paga il costo di una carta giocata durante l'attacco (la carta è già tolta dalla mano).
func _paga(costo: int, id: String) -> void:
	var k: Dictionary = s["killer"]
	if costo <= 0:
		return
	var scelte: Array = []
	if k["mano"].size() > costo:
		var d := await chiedi("K", {"tipo": "costo", "n": costo, "carta": id,
			"titolo": "Costo di «%s»: scegli %d carte da scartare" % [carta(id)["nome"], costo]})
		scelte = d.get("carte", [])
	var valide := []
	for x in scelte:
		var xi := int(x)
		if xi >= 0 and xi < k["mano"].size() and not valide.has(xi):
			valide.append(xi)
	var x2 := 0
	while valide.size() < mini(costo, k["mano"].size()) and x2 < k["mano"].size():
		if not valide.has(x2):
			valide.append(x2)
		x2 += 1
	valide.sort()
	valide.reverse()
	for x in valide:
		k["scarti"].append(k["mano"][x])
		k["mano"].remove_at(x)

## Toglie dal gioco n carte dalla pila degli scarti (scelte dal Killer).
func _rimuovi_scarti(n: int) -> void:
	var k: Dictionary = s["killer"]
	for x in n:
		if k["scarti"].is_empty():
			return
		var opz := []
		for c in k["scarti"]:
			opz.append(carta(c)["nome"])
		var d := await chiedi("K", {"tipo": "scelta", "opzioni": opz, "scopo": "rimuovi", "carte_id": k["scarti"].duplicate(),
			"titolo": "Togli dal gioco una carta dagli scarti (%d/%d)" % [x + 1, n]})
		var i := clampi(int(d.get("n", 0)), 0, k["scarti"].size() - 1)
		var c: String = k["scarti"][i]
		k["scarti"].remove_at(i)
		k["rimosse"].append(c)
		_ev("«%s» è tolta dal gioco." % carta(c)["nome"], "K")

func _passo_killer(dest: String, furtivo := false) -> bool:
	var k: Dictionary = s["killer"]
	var da: String = k["pos"]
	var tolto := false
	if s.get("cancello", "") != "" and s["cancello"] == chiave_porta(da, dest):
		# il cancello: il Killer lo sfonda scartando 3 carte
		var scelte: Array = []
		if k["mano"].size() > 3:
			var dc := await chiedi("K", {"tipo": "costo", "n": 3, "carta": "",
				"titolo": "Il cancello: scegli 3 carte da scartare per sfondarlo"})
			scelte = dc.get("carte", [])
		var valide := []
		for x in scelte:
			var xi := int(x)
			if xi >= 0 and xi < k["mano"].size() and not valide.has(xi):
				valide.append(xi)
		var x2 := 0
		while valide.size() < mini(3, k["mano"].size()) and x2 < k["mano"].size():
			if not valide.has(x2):
				valide.append(x2)
			x2 += 1
		valide.sort()
		valide.reverse()
		for x in valide:
			k["scarti"].append(k["mano"][x])
			k["mano"].remove_at(x)
		s["cancello"] = ""
		_ev("%s scarta 3 carte e sfonda il cancello!" % nome_k(), "tutti", {"tipo": "cancello_rotto"})
	if bloccata(da, dest) and not furtivo:
		s["blocchi"].erase(chiave_porta(da, dest))
		tolto = true
	if not vicini(da).has(dest) and passaggi_di(da).has(dest):
		if not k["passaggio_turno"] and k["evoluzioni"].has("mimetismo"):
			k["bonus_turno"] += 3
			_ev("Mimetismo: +3 Forza fino a fine turno.", "K")
		k["passaggio_turno"] = true
	k["pos"] = dest
	if furtivo:
		_ev("[furtivo] %s → %s" % [nome_luogo(da), nome_luogo(dest)], "K", {"tipo": "movimento_k", "da": da, "a": dest, "furtivo": true})
	else:
		k["vista"] = dest
		_ev("%s si sposta: %s → %s%s." % [nome_k(), nome_luogo(da), nome_luogo(dest), " sfondando il blocco" if tolto else ""],
			"tutti", {"tipo": "movimento_k", "da": da, "a": dest, "sblocco": tolto})
	return tolto

## [MUOVI] da nmin a nmax passi, uno alla volta. Restituisce {percorso, sblocchi}.
func _muovi_k(nmin: int, nmax: int, titolo := "[MUOVI]", furtivo := false) -> Dictionary:
	var k: Dictionary = s["killer"]
	var perc := [k["pos"]]
	var sblocchi := 0
	for n in nmax:
		var vk := vicini_k(k["pos"])
		var d := await chiedi("K", {"tipo": "muovi_k", "vicini": vk, "obbligo": n < nmin, "passo": n + 1, "max": nmax,
			"furtivo": furtivo, "titolo": "%s: passo %d di %d%s" % [titolo, n + 1, nmax, "" if n < nmin else " (puoi fermarti)"]})
		var dest: String = d.get("dest", "")
		if dest == "" or not vk.has(dest):
			if n < nmin and not vk.is_empty():
				dest = vk[0]
			else:
				break
		if await _passo_killer(dest, furtivo):
			sblocchi += 1
		perc.append(dest)
		cambiato.emit()
	return {"percorso": perc, "sblocchi": sblocchi}

func _cerca_k(automatica := false) -> bool:
	return await _cerca_luogo(s["killer"]["pos"], "", automatica)

## [CERCA] in un luogo (del Killer, di una Statua o di uno zombi).
func _cerca_luogo(l: String, chi := "", automatica := false) -> bool:
	var qui := in_luogo(l)
	var nome := nome_k() if chi == "" else chi
	if qui.is_empty():
		_ev("%s cerca nel %s: nessuno." % [nome, nome_luogo(l)], "tutti", {"tipo": "cerca_k", "luogo": l, "trovati": []})
		return false
	await _incontro(automatica, l)
	return true

## Un passo di una Statua (come il Killer: sfonda i blocchi).
func _passo_statua(j: int, dest: String) -> void:
	var st: Dictionary = s["statue"][j]
	var da: String = st["pos"]
	var tolto := false
	if bloccata(da, dest):
		s["blocchi"].erase(chiave_porta(da, dest))
		tolto = true
	st["pos"] = dest
	_sync_statue()
	_ev("La Statua %s si sposta: %s → %s%s." % [st["nome"], nome_luogo(da), nome_luogo(dest), " sfondando il blocco" if tolto else ""],
		"tutti", {"tipo": "movimento_statua", "statua": j, "da": da, "a": dest, "sblocco": tolto})

## Muove una Statua di nmin..nmax passi, chiedendo ogni passo.
func _muovi_statua(j: int, nmin: int, nmax: int, titolo: String) -> void:
	for n in nmax:
		if s["statue"][j]["gelo"] > 0:
			return
		var vk := vicini_k(s["statue"][j]["pos"])
		var d := await chiedi("K", {"tipo": "muovi_k", "vicini": vk, "obbligo": n < nmin, "passo": n + 1, "max": nmax, "da": s["statue"][j]["pos"],
			"titolo": "%s (Statua %s): passo %d di %d%s" % [titolo, s["statue"][j]["nome"], n + 1, nmax, "" if n < nmin else " (puoi fermarti)"]})
		var dest: String = d.get("dest", "")
		if dest == "" or not vk.has(dest):
			if n < nmin and not vk.is_empty():
				dest = vk[0]
			else:
				return
		_passo_statua(j, dest)
		cambiato.emit()

## Il Killer si sposta direttamente in un luogo (teletrasporto, anche furtivo).
func _teletrasporto(dest: String, furtivo := false) -> void:
	var k: Dictionary = s["killer"]
	var da: String = k["pos"]
	if furtivo:
		if not k["furtivo"]:
			k["vista"] = k["pos"]
		k["furtivo"] = true
		_ev("%s svanisce nell'ombra [FURTIVO]." % nome_k(), "tutti", {"tipo": "furtivo", "luogo": k["vista"]})
		k["pos"] = dest
		_ev("[furtivo] %s → %s" % [nome_luogo(da), nome_luogo(dest)], "K", {"tipo": "movimento_k", "da": da, "a": dest, "furtivo": true})
	else:
		k["pos"] = dest
		k["vista"] = dest
		_ev("%s si teletrasporta: %s → %s." % [nome_k(), nome_luogo(da), nome_luogo(dest)], "tutti", {"tipo": "movimento_k", "da": da, "a": dest})

## Chiede al Killer un luogo tra quelli dati.
func _chiedi_luogo(cand: Array, titolo: String, scopo: String, facoltativo := false) -> String:
	if cand.is_empty():
		return ""
	var d := await chiedi("K", {"tipo": "luogo", "luoghi": cand, "scopo": scopo, "facoltativo": facoltativo, "titolo": titolo})
	var l: String = d.get("dest", "")
	if not cand.has(l):
		return "" if facoltativo else cand[0]
	return l

func _metti_blocco(p: String) -> void:
	if s["blocchi"].has(p):
		return
	if s["blocchi"].size() >= Dati.BLOCCHI_MAX:
		var via: String = s["blocchi"].pop_front()
		_ev("Blocchi finiti: il Killer sposta il blocco tra %s e %s." % [nome_luogo(via.split("|")[0]), nome_luogo(via.split("|")[1])], "tutti",
			{"tipo": "sblocco", "porta": via})
	s["blocchi"].append(p)
	_ev("%s blocca la porta tra %s e %s." % [nome_k(), nome_luogo(p.split("|")[0]), nome_luogo(p.split("|")[1])], "tutti", {"tipo": "blocco", "porta": p})

func _blocca_qui(n: int) -> void:
	for x in n:
		var lib := []
		for p in porte_di(s["killer"]["pos"]):
			if not s["blocchi"].has(p):
				lib.append(p)
		if lib.is_empty():
			return
		var d := await chiedi("K", {"tipo": "porta", "porte": lib, "titolo": "[BLOCCA] una porta del tuo luogo"})
		var p: String = d.get("porta", "")
		if not lib.has(p):
			p = lib[0]
		_metti_blocco(p)
		cambiato.emit()

func _paura_raggio(r: int) -> void:
	var centro: String = s["killer"]["pos"]
	var zona_l := entro(centro, r)
	var colpiti := []
	for i in vivi():
		if zona_l.has(s["sopr"][i]["pos"]):
			colpiti.append(i)
	_ev("[PAURA] entro %d dal %s: %s." % [r, nome_luogo(centro), "nessuno" if colpiti.is_empty() else ", ".join(colpiti.map(func(x): return nome_s(x)))],
		"tutti", {"tipo": "paura_raggio", "centro": centro, "raggio": r, "colpiti": colpiti})
	for i in colpiti:
		await _paura(i, nome_k())

func _percepisci(luoghi: Array, descr: String) -> void:
	var trovati := []
	var tutti := []
	for i in vivi():
		if luoghi.has(s["sopr"][i]["pos"]):
			tutti.append(i)
			if s["sopr"][i]["id"] != "anna":
				trovati.append(i)
	var testo := "nessuno"
	if not trovati.is_empty():
		testo = ", ".join(trovati.map(func(x): return nome_s(x)))
	_ev("[PERCEPISCI] %s: %s." % [descr, testo], "tutti", {"tipo": "percepisci", "luoghi": luoghi, "trovati": trovati})
	if s["killer"]["id"] == "regina" and s["killer"]["livello"] >= 2:
		for i in trovati:
			_ev("La Regina impone il terrore a %s." % nome_s(i), "tutti")
			_paura_subito(i)

func _furtivo(nmin: int, nmax: int, effetto_riappari: String) -> void:
	var k: Dictionary = s["killer"]
	if not k["furtivo"]:
		k["vista"] = k["pos"]
	k["furtivo"] = true
	if effetto_riappari != "":
		k["riappari"].append(effetto_riappari)
	_ev("%s svanisce nell'ombra [FURTIVO]." % nome_k(), "tutti", {"tipo": "furtivo", "luogo": k["vista"]})
	await _muovi_k(nmin, nmax, "[FURTIVO]", true)

func _riappari() -> void:
	var k: Dictionary = s["killer"]
	k["furtivo"] = false
	k["vista"] = k["pos"]
	_ev("%s RIAPPARE nel %s!" % [nome_k(), nome_luogo(k["pos"])], "tutti", {"tipo": "riappare", "luogo": k["pos"]})
	cambiato.emit()
	var eff: Array = k["riappari"]
	k["riappari"] = []
	for e in eff:
		match e:
			"svanire":
				await _paura_raggio(1)
			"minaccia":
				var vv := vivi()
				var d := await chiedi("K", {"tipo": "bersaglio_paura", "titolo": "Minaccia in agguato: [PAURA] a un Sopravvissuto a scelta"})
				var i := int(d.get("i", vv[0]))
				if not vv.has(i):
					i = vv[0]
				await _paura(i, nome_k())
			"fioritura":
				var zona_l := entro(k["pos"], 1)
				var uccisi := []
				for i in vivi():
					if zona_l.has(s["sopr"][i]["pos"]):
						uccisi.append(i)
				_ev("Fioritura di morte: %s." % ("nessuno nel raggio" if uccisi.is_empty() else ", ".join(uccisi.map(func(x): return nome_s(x)))), "tutti",
					{"tipo": "paura_raggio", "centro": k["pos"], "raggio": 1, "colpiti": uccisi})
				for i in uccisi:
					s["sopr"][i]["ferite"] = 1
					s["sopr"][i]["tempra"] = false
					await _danno(i, "Fioritura di morte")
		if s["vincitore"] != "":
			return
	# [CERCA] obbligatoria
	var qui := in_luogo(k["pos"])
	if not qui.is_empty() and k["id"] == "assassino" and k["livello"] >= 2:
		k["bonus_attacco"] += 3
		_ev("Livello 2: +3 Forza per l'incontro alla ricomparsa.", "tutti")
	if not qui.is_empty() and k["evoluzioni"].has("mimetismo"):
		k["bonus_attacco"] += 3
		_ev("Mimetismo: +3 Forza alla ricomparsa.", "tutti")
	k["riappare_ora"] = true
	await _cerca_k(true)
	k["riappare_ora"] = false
	k["bonus_attacco"] = 0

# ================================================================ incontro e attacco

func _incontro(_automatica := false, luogo := "") -> void:
	var k: Dictionary = s["killer"]
	k["incontro"] = true
	if luogo == "":
		luogo = k["pos"]
	var bersagli := in_luogo(luogo)
	_ev("INCONTRO! %s trova %s nel %s." % [nome_k(), ", ".join(bersagli.map(func(x): return nome_s(x))), nome_luogo(luogo)],
		"tutti", {"tipo": "incontro", "luogo": luogo, "trovati": bersagli})
	cambiato.emit()
	# Regina: Forza = Regina + zombi presenti
	k["molt"] = 1
	k["regina_qui"] = 0
	if k["id"] == "regina":
		var rq: bool = k["pos"] == luogo
		k["regina_qui"] = 1 if rq else 0
		k["molt"] = maxi(1, zombi_in(luogo) + (1 if rq else 0))
		if k["molt"] > 1:
			_ev("La Forza dell'attacco somma Regina e zombi: x%d." % k["molt"], "tutti")
	# effetti dei livelli
	if k["id"] == "spettro":
		for i in bersagli:
			await _paura(i, nome_k())
	if k["livello"] >= 5:
		for i in bersagli:
			await _danno(i, nome_k())
			if s["vincitore"] != "":
				return
	var attaccati := []
	var trappola_usata := false
	var bonus_incontro: int = k["bonus_attacco"]
	while s["vincitore"] == "":
		var restanti := []
		for i in in_luogo(luogo):
			if not attaccati.has(i):
				restanti.append(i)
		if restanti.is_empty():
			break
		# carta d'attacco
		var att := []
		for x in k["mano"].size():
			if carta(k["mano"][x]).get("attacco", false) and pagabile(x):
				att.append(x)
		k["bonus_attacco"] = bonus_incontro
		var effetto_att := ""
		if not att.is_empty():
			var d := await chiedi("K", {"tipo": "attacco", "carte": att, "titolo": "Vuoi giocare una carta d'attacco?"})
			var idx := int(d.get("carta", -1))
			if att.has(idx):
				var id: String = k["mano"][idx]
				k["mano"].remove_at(idx)
				await _paga(costo_carta(id), id)
				k["scarti"].append(id)
				effetto_att = id
				var b: int = int(carta(id).get("bonus", 1))
				if id == "strangolare":
					b = s["nuclei"].size()
				k["bonus_attacco"] += b
				_ev("%s gioca «%s»%s." % [nome_k(), carta(id)["nome"], (": +%d Forza in questo attacco" % b) if b > 0 else ""], "tutti",
					{"tipo": "carta", "carta": id, "killer": k["id"]})
				if id == "adattamento":
					await _rimuovi_scarti(1)
					k["forza_perm"] += 1
					_ev("Adattamento: +1 Forza per sempre.", "tutti")
		var d := await chiedi("S", {"tipo": "difensore", "candidati": restanti, "forza": forza_attacco(),
			"titolo": "Attacco! Forza del Killer: %d. Chi si difende?" % forza_attacco()})
		var i := int(d.get("i", restanti[0]))
		if not restanti.has(i):
			i = restanti[0]
		attaccati.append(i)
		if effetto_att == "tocco":
			_avvelena(i)
			if s["vincitore"] != "":
				return
		var opz := oggetti_difesa(i)
		if effetto_att == "avvinghiare":
			opz = []
			_ev("%s è avvinghiato: non può usare oggetti." % nome_s(i), "tutti")
		var d2 := await chiedi("S", {"tipo": "oggetto_difesa", "i": i, "forza": forza_attacco(), "opzioni": opz,
			"titolo": "%s si difende (Forza %d): usi un oggetto?" % [nome_s(i), forza_attacco()]})
		if effetto_att == "avvinghiare":
			d2 = {"ogg": -1}
		var res := _difesa(i, d2, (not trappola_usata) and s["trappola"] == luogo)
		if res["trappola"]:
			trappola_usata = true
			s["trappola"] = ""
		cambiato.emit()
		var fa := forza_attacco()
		if res["totale"] >= fa:
			_ev("%s respinge l'attacco! (difesa %d contro Forza %d) Il Killer scarta 2 carte dal mazzo." % [nome_s(i), res["totale"], fa],
				"tutti", {"tipo": "difesa_ok", "i": i, "dadi": res["dadi"], "totale": res["totale"], "forza": fa})
			await _scarta_dal_mazzo(2)
			break
		else:
			_ev("%s non riesce a difendersi (difesa %d contro Forza %d)." % [nome_s(i), res["totale"], fa],
				"tutti", {"tipo": "difesa_ko", "i": i, "dadi": res["dadi"], "totale": res["totale"], "forza": fa})
			if effetto_att == "esecuzione" and fa - int(res["totale"]) >= 3:
				_ev("ESECUZIONE!", "tutti")
				s["sopr"][i]["ferite"] = 1
				s["sopr"][i]["tempra"] = false
			await _danno(i, nome_k())
	k["bonus_attacco"] = 0
	k["molt"] = 1
	k["regina_qui"] = 0
	if s["vincitore"] != "":
		return
	# fuga dopo l'incontro: [MUOVI] x1 per chi è nel luogo
	for i in in_luogo(luogo):
		var dest := passi_sopr(i, luogo)
		if dest.is_empty():
			continue
		var d := await chiedi("S", {"tipo": "fuga", "i": i, "luoghi": dest, "titolo": "%s può fuggire di un passo" % nome_s(i)})
		var l: String = d.get("dest", "")
		if dest.has(l):
			_muovi_sopr(i, [l], "fugge")
	cambiato.emit()

## Oggetti con cui un Sopravvissuto può difendersi: [{ogg: indice, nome, bonus, munizioni, ogg2}]
func oggetti_difesa(i: int) -> Array:
	var p: Dictionary = s["sopr"][i]
	var out := []
	var ha_mun: bool = p["oggetti"].has("munizioni")
	var arg: bool = p["oggetti"].has("proiettile_argento")
	var scudo: int = p["oggetti"].find("scudo")
	for k in p["oggetti"].size():
		var o: String = p["oggetti"][k]
		var b: int = Dati.OGGETTI[o].get("difesa", 0)
		if b > 0:
			var nome: String = Dati.OGGETTI[o]["nome"]
			if o == "revolver" and arg:
				nome += " (proiettili d'argento)"
			out.append({"ogg": k, "id": o, "nome": nome, "bonus": b})
			if o == "revolver" and ha_mun:
				out.append({"ogg": k, "id": o, "nome": nome + " + Munizioni", "bonus": b + 3, "munizioni": true})
			# lo Scudo si usa insieme a un'altra arma
			if scudo >= 0 and k != scudo:
				out.append({"ogg": scudo, "ogg2": k, "id": o, "nome": "Scudo + " + Dati.OGGETTI[o]["nome"], "bonus": b + 1})
	return out

func _difesa(i: int, d: Dictionary, trappola: bool) -> Dictionary:
	var p: Dictionary = s["sopr"][i]
	var ndadi := maxi(0, 4 - int(p["paura"]))
	var dadi := []
	var tot := 0
	var k := int(d.get("ogg", -1))
	var k2 := int(d.get("ogg2", -1))
	var con_revolver := false
	for kk in [k, k2]:
		if kk >= 0 and kk < p["oggetti"].size() and p["oggetti"][kk] == "revolver":
			con_revolver = true
	var argento: bool = con_revolver and p["oggetti"].has("proiettile_argento")
	for n in ndadi:
		var f: int = Dati.DADO[rng.randi_range(0, 5)]
		if argento and (f == 1 or f == 3):
			f = 5
		dadi.append(f)
		tot += f
	var dettagli := ["dadi %s" % str(dadi)]
	if argento:
		dettagli.append("proiettili d'argento")
	var arma := false
	var usati := []
	for kk in [k, k2]:
		if kk >= 0 and kk < p["oggetti"].size() and not usati.has(kk):
			usati.append(kk)
	var da_scartare := []
	for kk in usati:
		var o: String = p["oggetti"][kk]
		var b: int = Dati.OGGETTI[o].get("difesa", 0)
		if b <= 0:
			continue
		tot += b
		arma = arma or Dati.OGGETTI[o].get("arma", false)
		dettagli.append("%s +%d" % [Dati.OGGETTI[o]["nome"], b])
		if o == "revolver" and d.get("munizioni", false) and p["oggetti"].has("munizioni"):
			tot += 3
			dettagli.append("Munizioni +3")
			da_scartare.append("munizioni")
		if not Dati.OGGETTI[o].get("infinito", false):
			da_scartare.append(o)
	if not usati.is_empty() and p["oggetti"].has("nota_difesa"):
		tot += 2
		dettagli.append("Nota di George +2")
	if argento:
		da_scartare.append("proiettile_argento")
	for o in da_scartare:
		_scarta_oggetto(i, o)
	if p["id"] == "william" and not arma:
		tot += 1
		dettagli.append("Tenacia +1")
	if p["incoraggiamento"]:
		p["incoraggiamento"] = false
		tot += 1
		dettagli.append("Incoraggiamento +1")
	if trappola:
		tot += 2
		dettagli.append("Trappola +2")
	_ev("%s tira %d dadi: %s → totale %d." % [nome_s(i), ndadi, ", ".join(dettagli), tot], "tutti",
		{"tipo": "tiro", "i": i, "dadi": dadi, "totale": tot})
	return {"totale": tot, "dadi": dadi, "trappola": trappola}

# ================================================================ effetti delle carte

func _effetto(id: String) -> void:
	var k: Dictionary = s["killer"]
	match id:
		"inseguimento":
			await _muovi_k(1, 1, "Inseguimento")
		"percezione":
			var d := await chiedi("K", {"tipo": "zona", "titolo": "[PERCEPISCI] una zona di colore"})
			var z: String = d.get("zona", "R")
			if not Dati.ZONE.has(z):
				z = "R"
			var luoghi := []
			for l in mappa["luoghi"]:
				if zona(l) == z:
					luoghi.append(l)
			_percepisci(luoghi, "zona " + Dati.ZONE[z])
		"follia":
			await _blocca_qui(1)
			k["bonus_turno"] += 2
			_ev("Follia: +2 Forza in questo turno (Forza %d)." % forza(), "tutti")
		"barricata":
			await _blocca_qui(1)
		"resta":
			for p in porte_di(k["pos"]):
				_metti_blocco(p)
		"motosega":
			await _paura_raggio(1)
			if s["vincitore"] != "":
				return
			await _muovi_k(0, 1, "Motosega")
			for i in in_luogo(k["pos"]):
				await _danno(i, "la motosega")
				if s["vincitore"] != "":
					return
		"furia":
			var giri := 0
			while giri < 5:
				giri += 1
				var m := await _muovi_k(1, 2, "Furia brutale")
				var trovato := await _cerca_k()
				if trovato or s["vincitore"] != "" or m["sblocchi"] == 0:
					break
				_ev("Furia brutale: nessuno, ma un blocco è caduto. Ancora!", "tutti")
		"urlo":
			await _paura_raggio(1)
		"svanire":
			await _furtivo(0, 2, "svanire")
		"scia":
			var riv := []
			for i in vivi():
				if s["sopr"][i]["paura"] > 0:
					riv.append(i)
					_ev("%s è rivelato nel %s." % [nome_s(i), nome_luogo(s["sopr"][i]["pos"])], "tutti",
						{"tipo": "rivelato", "i": i, "luogo": s["sopr"][i]["pos"]})
			if riv.is_empty():
				_ev("Scia di paura: nessuno ha paura.", "tutti", {"tipo": "scia_vuota"})
		"sfrecciare":
			for i in in_luogo(k["pos"]):
				await _paura(i, nome_k())
			var giri := 0
			for n in 4:
				if s["vincitore"] != "":
					return
				var vk := vicini_k(k["pos"])
				var d := await chiedi("K", {"tipo": "muovi_k", "vicini": vk, "obbligo": n < 1, "passo": n + 1, "max": 4,
					"titolo": "Sfrecciare: passo %d di 4%s" % [n + 1, "" if n < 1 else " (puoi fermarti)"]})
				var dest: String = d.get("dest", "")
				if dest == "" or not vk.has(dest):
					if n < 1 and not vk.is_empty():
						dest = vk[0]
					else:
						break
				await _passo_killer(dest)
				for i in in_luogo(dest):
					await _paura(i, nome_k())
				cambiato.emit()
			if k["livello"] >= 2 and k["mano"].size() >= 2 and s["vincitore"] == "":
				var d := await chiedi("K", {"tipo": "si_no", "titolo": "Livello 2: scartare 2 carte per [CERCARE] qui?"})
				if d.get("si", false):
					for n in 2:
						k["scarti"].append(k["mano"].pop_back())
					await _cerca_k()
		"risucchio":
			for i in vivi():
				if s["sopr"][i]["paura"] > 0:
					await _danno(i, "Risucchio vitale")
					if s["vincitore"] != "":
						return
		"deduzione":
			var d := await chiedi("K", {"tipo": "luoghi2", "titolo": "[PERCEPISCI] due luoghi collegati: scegli il primo e il secondo"})
			var ll: Array = d.get("luoghi", [])
			if ll.size() != 2 or not vicini(ll[0]).has(ll[1]):
				ll = [k["pos"], vicini(k["pos"])[0]]
			_percepisci(ll, "%s e %s" % [nome_luogo(ll[0]), nome_luogo(ll[1])])
		"avviso":
			for i in vivi():
				await _paura(i, nome_k())
		"minaccia":
			await _furtivo(0, 2, "minaccia")
		"appostamento":
			await _furtivo(0, 2, "")
		"fioritura":
			await _furtivo(0, 2, "fioritura")
		_:
			await _effetto_espansioni(id)

func _luoghi_zona(z: String) -> Array:
	var out := []
	for l in mappa["luoghi"]:
		if zona(l) == z:
			out.append(l)
	return out

func _chiedi_zona(titolo := "[PERCEPISCI] una zona di colore") -> String:
	var d := await chiedi("K", {"tipo": "zona", "titolo": titolo})
	var z: String = d.get("zona", "R")
	return z if Dati.ZONE.has(z) else "R"

## Gli effetti delle carte dei Killer delle espansioni.
func _effetto_espansioni(id: String) -> void:
	var k: Dictionary = s["killer"]
	match id:
		# ---------------- Lupo Mannaro
		"ululato":
			await _paura_raggio(2)
			if s["vincitore"] == "":
				await _muovi_k(1, 1, "Ululato")
		"caccia_sangue":
			await _muovi_k(2, 2, "Caccia di sangue")
		"territorio":
			if k["fase_carta"] == "lenta":
				await _furtivo(0, 3, "")
			else:
				var ll := []
				for l in mappa["luoghi"]:
					if mappa["luoghi"][l].get("chiave", false):
						ll.append(l)
				_percepisci(ll, "i luoghi delle chiavi")
		"udito":
			# verso il rumore più vicino, al massimo 6 passi, poi [CERCA]
			var rum: Array = s["rumori"]
			if rum.is_empty():
				_ev("Udito iperacuto: nessun rumore da seguire.", "K")
			else:
				var dist := _distanze_k(k["pos"])
				var md := 99
				for l in rum:
					md = mini(md, int(dist.get(l, 99)))
				var vicini_r := []
				for l in rum:
					if int(dist.get(l, 99)) == md:
						vicini_r.append(l)
				var meta: String = vicini_r[0]
				if vicini_r.size() > 1:
					meta = await _chiedi_luogo(vicini_r, "Udito iperacuto: quale rumore segui?", "udito")
				var passi := 0
				while k["pos"] != meta and passi < 6:
					var nx := _passo_k_verso(k["pos"], meta)
					if nx == "":
						break
					await _passo_killer(nx)
					passi += 1
					cambiato.emit()
			if s["vincitore"] == "":
				await _cerca_k()
		# ---------------- Cacciatrice
		"istinto":
			var l := await _chiedi_luogo(mappa["luoghi"].keys(), "[PERCEPISCI] un luogo a tua scelta", "percepisci")
			_percepisci([l], nome_luogo(l))
		"fiato":
			await _pesca_in_mano(1)
			k["bonus_esteso"] = 3
			k["bonus_esteso_fino"] = s["turno"] + 1
			_ev("Fiato sospeso: +3 Forza fino alla fine del prossimo turno.", "tutti")
			await _furtivo(0, 2, "")
		"tracce":
			await _cerca_k()
			if s["vincitore"] != "":
				return
			var vv := vivi()
			var d := await chiedi("K", {"tipo": "sopravvissuto", "candidati": vv, "scopo": "distanza", "titolo": "Sulle tracce: di chi vuoi sapere la distanza?"})
			var i := int(d.get("i", vv[0]))
			if not vv.has(i):
				i = vv[0]
			var dd := distanza(k["pos"], s["sopr"][i]["pos"])
			_ev("Sulle tracce: %s è a %d di distanza dal %s." % [nome_s(i), dd, nome_luogo(k["pos"])], "tutti",
				{"tipo": "distanza", "i": i, "centro": k["pos"], "d": dd})
			if k["livello"] >= 4 and not k["incontro"]:
				await _muovi_k(0, 1, "Livello 4")
		"riarmo":
			var dest := await _chiedi_luogo(mappa["luoghi"].keys(), "Trappole riarmate: in quale luogo vai [FURTIVO]?", "furtivo")
			_teletrasporto(dest, true)
			var da_piazzare: Array = s["trappole_scattate"].duplicate()
			s["trappole_scattate"].clear()
			for t in da_piazzare:
				var cand := []
				for l in mappa["luoghi"]:
					if not s["trappole_k"].has(l) and in_luogo(l).is_empty():
						cand.append(l)
				var l := await _chiedi_luogo(cand, "Dove riarmi la trappola «%s»?" % Dati.TRAPPOLE[t]["nome"], "trappola")
				if l != "":
					s["trappole_k"][l] = t
					_ev("Una trappola viene riarmata nel %s." % nome_luogo(l), "tutti", {"tipo": "trappola_piazzata", "luogo": l})
		# ---------------- Regina
		"esplosione":
			var luoghi_z := []
			for z in s["zombi"]:
				if not luoghi_z.has(z):
					luoghi_z.append(z)
			var z := await _chiedi_luogo(luoghi_z, "Esplosione di cadavere: quale zombi sacrifichi?", "zombi_scelta")
			s["zombi"].erase(z)
			_ev("Uno zombi esplode nel %s!" % nome_luogo(z), "tutti", {"tipo": "zombi_tolto", "luogo": z, "esplode": true})
			var zona_l := entro(z, 1)
			var colpiti := []
			for i in vivi():
				if zona_l.has(s["sopr"][i]["pos"]):
					colpiti.append(i)
			_ev("[AVVELENA] entro 1 dal %s: %s." % [nome_luogo(z), "nessuno" if colpiti.is_empty() else ", ".join(colpiti.map(func(x): return nome_s(x)))],
				"tutti", {"tipo": "paura_raggio", "centro": z, "raggio": 1, "colpiti": colpiti})
			for i in colpiti:
				_avvelena(i)
		"vapore":
			await _furtivo(0, 3, "")
		"evocazione":
			_zombi_sorge(k["pos"])
			await _pesca_in_mano(1)
		"prendeteli":
			var luoghi_z := []
			for z in s["zombi"]:
				if not luoghi_z.has(z):
					luoghi_z.append(z)
			var z := await _chiedi_luogo(luoghi_z, "Prendeteli!: quale zombi cerca?", "zombi_scelta")
			await _cerca_luogo(z, "Uno zombi")
		"orda":
			var luoghi_z := []
			for z in s["zombi"]:
				if not luoghi_z.has(z):
					luoghi_z.append(z)
			var da := await _chiedi_luogo(luoghi_z, "Arriva l'orda: quali zombi si muovono?", "zombi_scelta")
			var dest := await _chiedi_luogo(vicini(da), "Arriva l'orda: verso dove?", "orda")
			var n := zombi_in(da)
			for x in n:
				s["zombi"].erase(da)
				s["zombi"].append(dest)
			_ev("%d zombi avanzano: %s → %s." % [n, nome_luogo(da), nome_luogo(dest)], "tutti", {"tipo": "zombi_muove", "da": da, "a": dest})
		"dominio":
			var l := await _chiedi_luogo(mappa["luoghi"].keys(), "Dominio: [PERCEPISCI] un luogo", "percepisci")
			_percepisci([l], nome_luogo(l))
			var trovati := []
			for i in in_luogo(l):
				if s["sopr"][i]["id"] != "anna":
					trovati.append(i)
			if not trovati.is_empty():
				var d := await chiedi("K", {"tipo": "sopravvissuto", "candidati": trovati, "scopo": "dominio", "titolo": "Dominio: chi muovi?"})
				var i := int(d.get("i", trovati[0]))
				if not trovati.has(i):
					i = trovati[0]
				for n in 2:
					var dest_l := passi_sopr(i, s["sopr"][i]["pos"])
					var dd := await _chiedi_luogo(dest_l, "Dominio: muovi %s (passo %d di 2)" % [nome_s(i), n + 1], "dominio", true)
					if dd == "":
						break
					_muovi_sopr(i, [dd], "è costretto a muoversi")
					_ev("%s è costretto a muoversi nel %s." % [nome_s(i), nome_luogo(dd)], "tutti", {"tipo": "rivelato", "i": i, "luogo": dd})
					cambiato.emit()
		# ---------------- Statue
		"stele":
			var tutte := []
			for p in _porte:
				if _porte[p]["tipo"] == "porta" and not s["blocchi"].has(p):
					tutte.append(p)
			if tutte.is_empty():
				return
			var d := await chiedi("K", {"tipo": "porta", "porte": tutte, "titolo": "Evocazione della stele: [BLOCCA] una porta qualsiasi"})
			var pt: String = d.get("porta", "")
			if not tutte.has(pt):
				pt = tutte[0]
			_metti_blocco(pt)
			var ab: PackedStringArray = pt.split("|")
			var colpiti := []
			for i in vivi():
				if s["sopr"][i]["pos"] in [ab[0], ab[1]]:
					colpiti.append(i)
			_ev("La stele sprigiona terrore: %s." % ("nessuno" if colpiti.is_empty() else ", ".join(colpiti.map(func(x): return nome_s(x)))), "tutti",
				{"tipo": "stele", "luoghi": [ab[0], ab[1]], "colpiti": colpiti})
			for i in colpiti:
				await _paura(i, nome_k())
		"riposiziona":
			await _pesca_in_mano(1)
			await _scegli_principale("Riposizionamento: quale Statua è la principale?")
			if not s["blocchi"].is_empty():
				var d := await chiedi("K", {"tipo": "si_no", "titolo": "Riposizionamento: vuoi spostare un blocco?", "scopo": "sposta_blocco"})
				if d.get("si", false):
					var d2 := await chiedi("K", {"tipo": "porta", "porte": s["blocchi"].duplicate(), "titolo": "Quale blocco sposti?"})
					var via: String = d2.get("porta", s["blocchi"][0])
					if not s["blocchi"].has(via):
						via = s["blocchi"][0]
					s["blocchi"].erase(via)
					_ev("Un blocco viene rimosso tra %s e %s." % [nome_luogo(via.split("|")[0]), nome_luogo(via.split("|")[1])], "tutti", {"tipo": "sblocco", "porta": via})
					var tutte := []
					for p in _porte:
						if _porte[p]["tipo"] == "porta" and not s["blocchi"].has(p) and p != via:
							tutte.append(p)
					if not tutte.is_empty():
						var d3 := await chiedi("K", {"tipo": "porta", "porte": tutte, "titolo": "Dove rimetti il blocco?"})
						var pt: String = d3.get("porta", tutte[0])
						if not tutte.has(pt):
							pt = tutte[0]
						_metti_blocco(pt)
		"pattuglia":
			await _pesca_in_mano(1)
			for j in s["statue"].size():
				if s["vincitore"] != "":
					return
				await _muovi_statua(j, 0, 1, "Pattuglia")
		"scatenate":
			var z := zona(k["pos"])
			var colpiti := []
			for i in vivi():
				if zona(s["sopr"][i]["pos"]) == z:
					colpiti.append(i)
			_ev("Le Statue si scatenano: [PAURA] nella zona %s (%s)." % [Dati.ZONE[z], "nessuno" if colpiti.is_empty() else ", ".join(colpiti.map(func(x): return nome_s(x)))],
				"tutti", {"tipo": "zona_paura", "zona": z, "colpiti": colpiti})
			for i in colpiti:
				await _paura(i, nome_k())
			if s["vincitore"] != "":
				return
			await _muovi_statua(k["principale"], 0, 2, "Scatenate")
			if s["statue"][k["principale"]]["gelo"] <= 0:
				await _cerca_luogo(s["statue"][k["principale"]]["pos"], "Una Statua")
		"accerchiamento":
			for j in s["statue"].size():
				if s["vincitore"] != "":
					return
				await _muovi_statua(j, 0, 2, "Accerchiamento")
			var fatte := []
			while fatte.size() < s["statue"].size() and s["vincitore"] == "":
				var opz := []
				var idx := []
				for j in s["statue"].size():
					if not fatte.has(j):
						idx.append(j)
						opz.append("Statua %s (%s)" % [s["statue"][j]["nome"], nome_luogo(s["statue"][j]["pos"])])
				var d := await chiedi("K", {"tipo": "scelta", "opzioni": opz, "scopo": "statua_cerca", "titolo": "Accerchiamento: quale Statua cerca ora?"})
				var j: int = idx[clampi(int(d.get("n", 0)), 0, idx.size() - 1)]
				fatte.append(j)
				if s["statue"][j]["gelo"] <= 0:
					var prima: bool = k["incontro"]
					k["incontro"] = false
					await _cerca_luogo(s["statue"][j]["pos"], "La Statua %s" % s["statue"][j]["nome"])
					k["incontro"] = k["incontro"] or prima
		# ---------------- Strangolatore
		"rampicante":
			var porte := []
			for l in s["nuclei"]:
				for p in porte_di(l):
					if not s["blocchi"].has(p) and not porte.has(p):
						porte.append(p)
			if porte.is_empty():
				return
			var d := await chiedi("K", {"tipo": "porta", "porte": porte, "titolo": "Crescita dei rampicanti: [BLOCCA] una porta di un luogo con un nucleo"})
			var pt: String = d.get("porta", "")
			if not porte.has(pt):
				pt = porte[0]
			_metti_blocco(pt)
		"germoglio":
			_metti_nucleo(k["pos"])
			await _blocca_qui(1)
		"telesintesi":
			var d := await chiedi("K", {"tipo": "scelta", "opzioni": ["Teletrasportati in un luogo con un nucleo o un blocco", "Sposta un nucleo in un luogo adiacente"],
				"scopo": "telesintesi", "titolo": "Telesintesi: cosa fai?"})
			if int(d.get("n", 0)) == 0:
				var cand := []
				for l in s["nuclei"]:
					if not cand.has(l) and l != k["pos"]:
						cand.append(l)
				for b in s["blocchi"]:
					for l in b.split("|"):
						if not cand.has(l) and l != k["pos"]:
							cand.append(l)
				var dest := await _chiedi_luogo(cand, "Telesintesi: dove ti teletrasporti?", "teletrasporto")
				if dest != "":
					_teletrasporto(dest, k["furtivo"])
			elif not s["nuclei"].is_empty():
				var cand := []
				for l in s["nuclei"]:
					if not cand.has(l):
						cand.append(l)
				var da := await _chiedi_luogo(cand, "Telesintesi: quale nucleo sposti?", "nucleo_scelta")
				var dest := await _chiedi_luogo(vicini(da), "Telesintesi: dove lo sposti?", "nucleo")
				s["nuclei"].erase(da)
				s["nuclei"].append(dest)
				_ev("Un nucleo si sposta: %s → %s." % [nome_luogo(da), nome_luogo(dest)], "tutti", {"tipo": "nucleo", "luogo": dest})
		"avvinghiare":
			await _cerca_k()
		"frenesia":
			for i in vivi():
				await _paura(i, nome_k())
				if s["vincitore"] != "":
					return
			for i in vivi():
				var l: String = s["sopr"][i]["pos"]
				if s["nuclei"].has(l) or not passaggi_di(l).is_empty():
					await _danno(i, "i rampicanti")
					if s["vincitore"] != "":
						return
		# ---------------- Non Identificato
		"strisciare":
			if k["evoluzioni"].has("rettile"):
				await _muovi_k(1, 3, "Strisciare da rettile")
			else:
				await _muovi_k(1, 1, "Strisciare")
		"cunicolo":
			if k["evoluzioni"].has("mimetismo"):
				var dest := await _chiedi_luogo(mappa["luoghi"].keys(), "Cunicolo: [FURTIVO] in un luogo qualsiasi", "furtivo")
				_teletrasporto(dest, true)
			else:
				var d := await chiedi("K", {"tipo": "scelta", "opzioni": ["[FURTIVO] x0-1", "[FURTIVO] in un luogo con un passaggio segreto"],
					"scopo": "cunicolo", "titolo": "Cunicolo inquietante: cosa fai?"})
				if int(d.get("n", 0)) == 1:
					var cand := []
					for l in mappa["luoghi"]:
						if not passaggi_di(l).is_empty():
							cand.append(l)
					var dest := await _chiedi_luogo(cand, "Cunicolo: in quale luogo con un passaggio segreto?", "furtivo")
					_teletrasporto(dest, true)
				else:
					await _furtivo(0, 1, "")
		"metamorfosi":
			await _rimuovi_scarti(2)
			k["forza_perm"] += 2
			_ev("Metamorfosi: +2 Forza per sempre (Forza %d)." % forza(), "tutti")
			if k["evoluzioni"].has("ghiandole"):
				await _pesca_in_mano(1)
				await _blocca_qui(2)
		"infrarossi":
			var d := await chiedi("K", {"tipo": "scelta", "opzioni": ["[PERCEPISCI] una zona di colore", "[PERCEPISCI] tutti i luoghi entro 1 di distanza"],
				"scopo": "infrarossi", "titolo": "Rilevamento a infrarossi: cosa fai?"})
			if int(d.get("n", 0)) == 1:
				_percepisci(entro(k["pos"], 1), "entro 1 dal %s" % nome_luogo(k["pos"]))
			else:
				var z := await _chiedi_zona()
				_percepisci(_luoghi_zona(z), "zona " + Dati.ZONE[z])
		"stridio":
			await _paura_raggio(3)
			if s["vincitore"] == "":
				var d := await chiedi("K", {"tipo": "si_no", "scopo": "cima", "titolo": "Rimetti «Rumore stridente» in cima al tuo mazzo?"})
				k["cima"] = d.get("si", false)
		"acido":
			var adj := vicini(k["pos"])
			var l2 := await _chiedi_luogo(adj, "Sputo acido: quale luogo adiacente colpisci?", "acido")
			for i in in_luogo(k["pos"]) + in_luogo(l2):
				await _danno(i, "lo Sputo acido")
				if s["vincitore"] != "":
					return
			var pt := chiave_porta(k["pos"], l2)
			if _porte.has(pt) and _porte[pt]["tipo"] == "porta":
				_metti_blocco(pt)

## Pesca n carte in mano (con il limite della mano).
func _pesca_in_mano(n: int) -> void:
	var k: Dictionary = s["killer"]
	for x in n:
		var c: String = await _pesca_killer_una()
		if c == "":
			return
		if k["mano"].size() >= Dati.MANO_MAX:
			k["scarti"].append(c)
		else:
			k["mano"].append(c)

## Distanze dal luogo l per il Killer (con i suoi collegamenti).
func _distanze_k(l: String) -> Dictionary:
	var vis := {l: 0}
	var coda := [l]
	while not coda.is_empty():
		var x = coda.pop_front()
		for v in vicini_k(x):
			if not vis.has(v):
				vis[v] = vis[x] + 1
				coda.append(v)
	return vis

func _passo_k_verso(da: String, a: String) -> String:
	if da == a:
		return ""
	var prec := {da: ""}
	var coda := [da]
	while not coda.is_empty():
		var x = coda.pop_front()
		for v in vicini_k(x):
			if not prec.has(v):
				prec[v] = x
				if v == a:
					var cur: String = v
					while prec[cur] != da:
						cur = prec[cur]
					return cur
				coda.append(v)
	return ""

# ================================================================ viste per l'interfaccia

## Che cosa vede un lato: i Sopravvissuti vedono tutto tranne il Killer furtivo e la sua mano.
func posizione_killer_per(lato: String) -> String:
	if s["killer"]["id"] == "statue":
		return ""
	if lato == "K" or lato == "tutti":
		return s["killer"]["pos"]
	return "" if s["killer"]["furtivo"] else s["killer"]["pos"]
