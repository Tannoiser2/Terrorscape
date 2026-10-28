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
			"motosega_veloce": false, "furtivo_turni": 0},
		"sopr": [],
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
			"agito": false, "moneta": false, "incoraggiamento": false, "tempra": id == "dylan"}
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

func _mescola(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t

func gioca() -> void:
	_ev("La notte cala sulla %s. I Sopravvissuti entrano dall'%s, il Killer attende nel %s." % [
		mappa["nome"], nome_luogo(mappa["partenza_s"]), nome_luogo(mappa["partenza_k"])], "S")
	_ev("La notte cala sulla %s. Tu attendi nel %s: i Sopravvissuti sono entrati dall'%s." % [
		mappa["nome"], nome_luogo(mappa["partenza_k"]), nome_luogo(mappa["partenza_s"])], "K")
	while s["vincitore"] == "":
		await _turno_sopravvissuti()
		if s["vincitore"] != "":
			break
		await _turno_killer()
	cambiato.emit()
	finita.emit(s["vincitore"], s["motivo"])

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
	return out

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
	for v in vicini(da):
		if not chiusa_sopr(da, v):
			out.append(v)
	if con_passaggi or ha_oggetto(i, "torcia"):
		for p in passaggi_di(da):
			if not out.has(p):
				out.append(p)
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
	if p["ferite"] > 0:
		p["ferite"] = 0
		_ev("%s è curato." % nome_s(i), "tutti", {"tipo": "cura", "i": i})

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
		if p["id"] == "george" and distanza(p["pos"], s["killer"]["pos"]) <= 1:
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
	var kv := killer_visto()
	var killer_qui: bool = (not s["killer"]["furtivo"]) and kv == l
	if not p["agito"]:
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
				and not s["riparato_turno"] and not (not s["killer"]["furtivo"] and killer_visto() == l)
		"erbe":
			if p["agito"]:
				return false
			for j in in_luogo(l):
				if s["sopr"][j]["ferite"] > 0:
					return true
			return false
		"kit_medico":
			if p["agito"]:
				return false
			for j in in_luogo(l):
				if s["sopr"][j]["ferite"] > 0 or s["sopr"][j]["paura"] > 0:
					return true
			return false
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
			if not in_luogo(l).has(j) or s["sopr"][j]["ferite"] == 0:
				j = -1
				for x in in_luogo(l):
					if s["sopr"][x]["ferite"] > 0:
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
		_:
			return false
	return true

# ================================================================ turno del Killer

func forza() -> int:
	var k: Dictionary = s["killer"]
	return mini(Dati.FORZA_MAX, k["forza_base"] + k["bonus_livello"] + k["bonus_turno"] + k["bonus_attacco"])

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
	var c: int = carta(mano[idx])["costo"]
	if c < 0:
		return true
	return mano.size() - 1 >= c

func giocabili(tipo: String) -> Array:
	var out := []
	var mano: Array = s["killer"]["mano"]
	for k in mano.size():
		if tipo_carta(mano[k]) == tipo and pagabile(k):
			out.append(k)
	return out

func _turno_killer() -> void:
	var k: Dictionary = s["killer"]
	s["fase"] = "K"
	k["incontro"] = false
	k["bonus_turno"] = 0
	k["bonus_attacco"] = 0
	_ev("— Turno %d: %s —" % [s["turno"], nome_k()], "tutti", {"tipo": "turno"})
	cambiato.emit()
	if k["furtivo"]:
		await _riappari()
	# carte veloci
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
				var d2 := await chiedi("K", {"tipo": "azione_k", "n": n + 1, "vicini": vicini_k(k["pos"]),
					"titolo": "Azione %d di 2: [MUOVI] x1 o [CERCA]" % (n + 1)})
				if d2.get("a", "") == "muovi" and vicini_k(k["pos"]).has(d2.get("dest", "")):
					await _passo_killer(d2["dest"])
				elif d2.get("a", "") == "cerca":
					await _cerca_k()
				cambiato.emit()
	# carta lenta (solo se non c'è stato un incontro)
	if not k["incontro"] and s["vincitore"] == "":
		var g := giocabili("lenta")
		if not g.is_empty():
			var d := await chiedi("K", {"tipo": "lenta", "carte": g, "titolo": "Puoi giocare una carta lenta"})
			var idx := int(d.get("carta", -1))
			if idx >= 0 and g.has(idx):
				await _gioca_carta(idx)
	if s["vincitore"] != "":
		return
	# pesca 3
	await _pesca_fine_turno()
	cambiato.emit()

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
	cambiato.emit()

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
	var costo: int = carta(id)["costo"]
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
	await _effetto(id)
	k["scarti"].append(id)
	cambiato.emit()

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
	var k: Dictionary = s["killer"]
	var qui := in_luogo(k["pos"])
	if qui.is_empty():
		_ev("%s cerca nel %s: nessuno." % [nome_k(), nome_luogo(k["pos"])], "tutti", {"tipo": "cerca_k", "luogo": k["pos"], "trovati": []})
		return false
	await _incontro(automatica)
	return true

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
	await _cerca_k(true)
	k["bonus_attacco"] = 0

# ================================================================ incontro e attacco

func _incontro(_automatica := false) -> void:
	var k: Dictionary = s["killer"]
	k["incontro"] = true
	var luogo: String = k["pos"]
	var bersagli := in_luogo(luogo)
	_ev("INCONTRO! %s trova %s nel %s." % [nome_k(), ", ".join(bersagli.map(func(x): return nome_s(x))), nome_luogo(luogo)],
		"tutti", {"tipo": "incontro", "luogo": luogo, "trovati": bersagli})
	cambiato.emit()
	# effetti dei livelli
	if k["id"] == "spettro":
		for i in bersagli:
			await _paura(i, nome_k())
	var danno_prima: bool = (k["id"] in ["macellaio", "spettro", "assassino"]) and k["livello"] >= 5
	if danno_prima:
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
		if not att.is_empty():
			var d := await chiedi("K", {"tipo": "attacco", "carte": att, "titolo": "Vuoi giocare una carta d'attacco?"})
			var idx := int(d.get("carta", -1))
			if att.has(idx):
				var id: String = k["mano"][idx]
				k["mano"].remove_at(idx)
				k["scarti"].append(id)
				k["bonus_attacco"] += 1
				_ev("%s gioca «%s»: +1 Forza in questo attacco." % [nome_k(), carta(id)["nome"]], "tutti", {"tipo": "carta", "carta": id, "killer": k["id"]})
		var d := await chiedi("S", {"tipo": "difensore", "candidati": restanti, "forza": forza(),
			"titolo": "Attacco! Forza del Killer: %d. Chi si difende?" % forza()})
		var i := int(d.get("i", restanti[0]))
		if not restanti.has(i):
			i = restanti[0]
		attaccati.append(i)
		var d2 := await chiedi("S", {"tipo": "oggetto_difesa", "i": i, "forza": forza(), "opzioni": oggetti_difesa(i),
			"titolo": "%s si difende (Forza %d): usi un oggetto?" % [nome_s(i), forza()]})
		var res := _difesa(i, d2, (not trappola_usata) and s["trappola"] == luogo)
		if res["trappola"]:
			trappola_usata = true
			s["trappola"] = ""
		cambiato.emit()
		if res["totale"] >= forza():
			_ev("%s respinge l'attacco! (difesa %d contro Forza %d) Il Killer scarta 2 carte dal mazzo." % [nome_s(i), res["totale"], forza()],
				"tutti", {"tipo": "difesa_ok", "i": i, "dadi": res["dadi"], "totale": res["totale"], "forza": forza()})
			await _scarta_dal_mazzo(2)
			break
		else:
			_ev("%s non riesce a difendersi (difesa %d contro Forza %d)." % [nome_s(i), res["totale"], forza()],
				"tutti", {"tipo": "difesa_ko", "i": i, "dadi": res["dadi"], "totale": res["totale"], "forza": forza()})
			await _danno(i, nome_k())
	k["bonus_attacco"] = 0
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

## Oggetti con cui un Sopravvissuto può difendersi: [{ogg: indice, nome, bonus, munizioni}]
func oggetti_difesa(i: int) -> Array:
	var p: Dictionary = s["sopr"][i]
	var out := []
	var ha_mun: bool = p["oggetti"].has("munizioni")
	for k in p["oggetti"].size():
		var o: String = p["oggetti"][k]
		var b: int = Dati.OGGETTI[o].get("difesa", 0)
		if b > 0:
			out.append({"ogg": k, "id": o, "nome": Dati.OGGETTI[o]["nome"], "bonus": b})
			if o == "revolver" and ha_mun:
				out.append({"ogg": k, "id": o, "nome": "Revolver + Munizioni", "bonus": b + 3, "munizioni": true})
	return out

func _difesa(i: int, d: Dictionary, trappola: bool) -> Dictionary:
	var p: Dictionary = s["sopr"][i]
	var ndadi := maxi(0, 4 - int(p["paura"]))
	var dadi := []
	var tot := 0
	for n in ndadi:
		var f: int = Dati.DADO[rng.randi_range(0, 5)]
		dadi.append(f)
		tot += f
	var dettagli := ["dadi %s" % str(dadi)]
	var k := int(d.get("ogg", -1))
	var arma := false
	if k >= 0 and k < p["oggetti"].size():
		var o: String = p["oggetti"][k]
		var b: int = Dati.OGGETTI[o].get("difesa", 0)
		if b > 0:
			tot += b
			arma = Dati.OGGETTI[o].get("arma", false)
			dettagli.append("%s +%d" % [Dati.OGGETTI[o]["nome"], b])
			if o == "revolver" and d.get("munizioni", false) and p["oggetti"].has("munizioni"):
				tot += 3
				dettagli.append("Munizioni +3")
				_scarta_oggetto(i, "munizioni")
			if p["oggetti"].has("nota_difesa"):
				tot += 2
				dettagli.append("Nota di George +2")
			if not Dati.OGGETTI[o].get("infinito", false):
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

# ================================================================ viste per l'interfaccia

## Che cosa vede un lato: i Sopravvissuti vedono tutto tranne il Killer furtivo e la sua mano.
func posizione_killer_per(lato: String) -> String:
	if lato == "K" or lato == "tutti":
		return s["killer"]["pos"]
	return "" if s["killer"]["furtivo"] else s["killer"]["pos"]
