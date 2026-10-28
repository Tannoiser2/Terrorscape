## Giocatore automatico per entrambi i lati.
## Il Killer non sbircia: tiene una mappa di probabilità per ogni Sopravvissuto, aggiornata solo con le
## informazioni che il Killer riceve davvero (rumori, percezioni, paura, incontri).
## I Sopravvissuti vedono il Killer solo quando non è furtivo.
class_name IA
extends RefCounted

var p: Partita
var lato := "K"
var rng := RandomNumberGenerator.new()
var cred := []            # per ogni Sopravvissuto: {luogo: peso}
var obiettivo_k := ""
var _piano_ultimo_turno := -1
var ruoli := {}           # Sopravvissuto -> "radio" / "chiavi"

func _init(partita: Partita, quale_lato: String, seme := 7) -> void:
	p = partita
	lato = quale_lato
	rng.seed = seme
	if lato == "K":
		for i in p.s["sopr"].size():
			cred.append({p.mappa["partenza_s"]: 1.0})
		p.evento.connect(_su_evento)

# ================================================================ conoscenza del Killer

func _norm(i: int) -> void:
	var tot := 0.0
	for l in cred[i]:
		tot += cred[i][l]
	if tot <= 0.0001:
		# nessuna ipotesi rimasta: si ricomincia uniformi sulla mappa
		for l in p.mappa["luoghi"]:
			cred[i][l] = 1.0
		tot = float(p.mappa["luoghi"].size())
	for l in cred[i].keys():
		cred[i][l] /= tot
		if cred[i][l] < 0.002:
			cred[i].erase(l)

func _diffondi(i: int, passi: int) -> void:
	for n in passi:
		var nuovo := {}
		for l in cred[i]:
			var w: float = cred[i][l]
			var dest: Array = [l]
			for v in p.vicini(l):
				if not p.chiusa_sopr(l, v):
					dest.append(v)
			for d in dest:
				nuovo[d] = nuovo.get(d, 0.0) + w / dest.size()
			for pass_seg in p.passaggi_di(l):
				nuovo[pass_seg] = nuovo.get(pass_seg, 0.0) + w * 0.08
		cred[i] = nuovo
		_norm(i)

func _fissa(i: int, l: String) -> void:
	cred[i] = {l: 1.0}

func _escludi(i: int, luoghi: Array) -> void:
	for l in luoghi:
		cred[i].erase(l)
	_norm(i)

func _limita(i: int, luoghi: Array) -> void:
	for l in cred[i].keys():
		if not luoghi.has(l):
			cred[i].erase(l)
	_norm(i)

func _su_evento(e: Dictionary) -> void:
	if e.get("vis", "tutti") == "S":
		return
	var vv := p.vivi()
	match e.get("tipo", ""):
		"rumori":
			# fine turno dei Sopravvissuti: si sono mossi, poi i rumori
			for i in vv:
				_diffondi(i, 2)
			var lr: Array = e.get("luoghi", [])
			if not lr.is_empty():
				for i in vv:
					for l in cred[i].keys():
						if lr.has(l):
							cred[i][l] *= 4.0
					_norm(i)
		"petardo":
			for i in vv:
				_diffondi(i, 2)
		"percepisci":
			var luoghi: Array = e.get("luoghi", [])
			var trovati: Array = e.get("trovati", [])
			for i in vv:
				if trovati.has(i):
					_limita(i, luoghi)
				elif p.s["sopr"][i]["id"] != "anna":
					_escludi(i, luoghi)
		"paura_raggio":
			var zona_l := p.entro(e["centro"], int(e["raggio"]))
			for i in vv:
				if e["colpiti"].has(i):
					_limita(i, zona_l)
				else:
					_escludi(i, zona_l)
		"trabocca", "rivelato":
			_fissa(int(e["i"]), e["luogo"])
		"incontro":
			for i in vv:
				if e["trovati"].has(i):
					_fissa(i, e["luogo"])
				else:
					_escludi(i, [e["luogo"]])
		"cerca_k":
			for i in vv:
				_escludi(i, [e["luogo"]])
		"trappola_scattata":
			_fissa(int(e["i"]), e["luogo"])
		"distanza":
			var i := int(e["i"])
			var giusti := []
			for l in p.mappa["luoghi"]:
				if p.distanza(e["centro"], l) == int(e["d"]):
					giusti.append(l)
			_limita(i, giusti)
		"stele":
			for i in vv:
				if e["colpiti"].has(i):
					_limita(i, e["luoghi"])
				else:
					_escludi(i, e["luoghi"])
		"zona_paura":
			var zl := []
			for l in p.mappa["luoghi"]:
				if p.zona(l) == e["zona"]:
					zl.append(l)
			for i in vv:
				if e["colpiti"].has(i):
					_limita(i, zl)
				else:
					_escludi(i, zl)
		"movimento_s":
			pass

func calore() -> Dictionary:
	var h := {}
	for i in p.vivi():
		if i >= cred.size():
			continue
		for l in cred[i]:
			h[l] = h.get(l, 0.0) + cred[i][l]
	return h

func _passo_verso(da: String, a: String) -> String:
	if da == a:
		return ""
	var vis := {da: ""}
	var coda := [da]
	while not coda.is_empty():
		var x = coda.pop_front()
		for v in p.vicini_k(x):
			if not vis.has(v):
				vis[v] = x
				if v == a:
					var cur: String = v
					while vis[cur] != da:
						cur = vis[cur]
					return cur
				coda.append(v)
	return ""

func _obiettivo() -> String:
	var h := calore()
	var kpos: String = p.s["killer"]["pos"]
	var best := kpos
	var bv := -1.0
	for l in h:
		var v: float = h[l] / (1.0 + 0.25 * p.distanza(kpos, l))
		if v > bv:
			bv = v
			best = l
	return best

# ================================================================ decisioni

func decidi(req: Dictionary) -> Dictionary:
	if lato == "K":
		return _decidi_k(req)
	return _decidi_s(req)

func _valore_carta(c: String) -> float:
	var v := {"inseguimento": 3.0, "percezione": 4.0, "follia": 3.0, "barricata": 1.5, "resta": 2.0, "motosega": 6.0, "furia": 8.0,
		"urlo": 3.0, "svanire": 4.0, "scia": 4.0, "sfrecciare": 6.0, "risucchio": 9.0, "deduzione": 4.0, "avviso": 3.5,
		"minaccia": 4.0, "appostamento": 3.0, "fioritura": 9.0,
		"morso": 4.0, "ululato": 4.0, "caccia_sangue": 3.0, "territorio": 4.0, "udito": 9.0,
		"istinto": 4.0, "ascia": 5.0, "fiato": 5.0, "tracce": 4.5, "riarmo": 7.0,
		"esplosione": 5.0, "tocco": 4.0, "vapore": 4.0, "evocazione": 3.5, "prendeteli": 4.0, "orda": 3.0, "dominio": 7.0,
		"stele": 3.5, "riposiziona": 2.5, "pattuglia": 4.0, "scatenate": 6.0, "esecuzione": 5.0, "accerchiamento": 9.0,
		"rampicante": 2.0, "germoglio": 3.0, "telesintesi": 4.0, "strangolare": 5.0, "avvinghiare": 3.0, "frenesia": 9.0,
		"strisciare": 3.0, "agguato": 4.0, "cunicolo": 3.5, "metamorfosi": 6.0, "infrarossi": 4.0, "adattamento": 4.5,
		"stridio": 6.0, "acido": 8.0}
	return v.get(c, 2.0)

func _peggiori(n: int, esclusa := -1) -> Array:
	var mano: Array = p.s["killer"]["mano"]
	var idx := []
	for k in mano.size():
		if k != esclusa:
			idx.append(k)
	idx.sort_custom(func(a, b): return _valore_carta(mano[a]) < _valore_carta(mano[b]))
	return idx.slice(0, n)

func _decidi_k(req: Dictionary) -> Dictionary:
	var k: Dictionary = p.s["killer"]
	var mano: Array = k["mano"]
	var h := calore()
	var qui: String = k["pos"]
	var p_qui: float = h.get(qui, 0.0)
	var obj := _obiettivo()
	var vicino_caldo := 0.0
	for l in p.entro(qui, 1):
		vicino_caldo += h.get(l, 0.0)
	match req["tipo"]:
		"veloce":
			for idx in req["carte"]:
				var c: String = mano[idx]
				if _nuova_carta(c, "veloce", h, obj, vicino_caldo, p_qui):
					return {"carta": idx}
				match c:
					"percezione":
						if _incertezza() > 0.45:
							return {"carta": idx}
					"inseguimento":
						if obj != qui and p_qui < 0.35:
							return {"carta": idx}
					"urlo":
						if vicino_caldo > 0.6:
							return {"carta": idx}
					"avviso":
						if mano.size() >= 3:
							return {"carta": idx}
					"scia":
						var paurosi := 0
						for i in p.vivi():
							if p.s["sopr"][i]["paura"] > 0 and _max_cred(i) < 0.7:
								paurosi += 1
						if paurosi > 0 and mano.size() >= 2:
							return {"carta": idx}
					"deduzione":
						if _incertezza() > 0.5 and mano.size() >= 3:
							return {"carta": idx}
					"follia":
						if (p_qui > 0.35 or vicino_caldo > 0.9) and mano.size() >= 4:
							return {"carta": idx}
					"motosega":
						if vicino_caldo > 0.8:
							return {"carta": idx}
			return {"carta": -1}
		"principale":
			for idx in req["carte"]:
				var c: String = mano[idx]
				if _nuova_carta(c, "speciale", h, obj, vicino_caldo, p_qui):
					return {"carta": idx}
				match c:
					"furia":
						if h.get(obj, 0.0) > 0.25 and p.distanza(qui, obj) <= 2:
							return {"carta": idx}
					"motosega":
						if vicino_caldo > 0.7:
							return {"carta": idx}
					"sfrecciare":
						if p.distanza(qui, obj) >= 2 or vicino_caldo > 0.5:
							return {"carta": idx}
					"risucchio":
						var paurosi := 0
						for i in p.vivi():
							if p.s["sopr"][i]["paura"] > 0:
								paurosi += 1
						if paurosi >= 1:
							return {"carta": idx}
			return {"carta": -1}
		"azione_k":
			var da: String = req.get("da", qui)
			var o2 := _obiettivo_da(da)
			if h.get(da, 0.0) > 0.3:
				return {"a": "cerca"}
			if da == qui and p._puo_crollare() and p.s["turno"] >= 3:
				var vic := 0.0
				for l in p.entro(qui, 1):
					vic += h.get(l, 0.0)
				if vic > 0.4 and rng.randf() < 0.5:
					return {"a": "crollo"}
			var passo := _passo_verso(da, o2)
			if passo == "":
				return {"a": "cerca"}
			return {"a": "muovi", "dest": passo}
		"lenta":
			for idx in req["carte"]:
				var c: String = mano[idx]
				if _nuova_carta(c, "lenta", h, obj, vicino_caldo, p_qui):
					return {"carta": idx}
				if c in ["fioritura", "svanire", "minaccia"]:
					return {"carta": idx}
				if c == "appostamento" and p.distanza(qui, obj) >= 1 and rng.randf() < 0.5:
					return {"carta": idx}
				if c in ["barricata", "resta"] and p_qui > 0.2 and not p.porte_di(qui).is_empty():
					return {"carta": idx}
			return {"carta": -1}
		"costo":
			var esclusa := -1
			return {"carte": _peggiori(int(req["n"]), esclusa)}
		"muovi_k":
			if req["vicini"].is_empty():
				return {"dest": ""}
			if req.has("da") and req["da"] != qui:
				var da2: String = req["da"]
				var pv := _passo_verso(da2, _obiettivo_da(da2))
				if pv != "" and req["vicini"].has(pv) and h.get(da2, 0.0) < 0.3:
					return {"dest": pv}
				return {"dest": req["vicini"][0] if req.get("obbligo", false) else ""}
			var passo := _passo_verso(qui, obj)
			if passo == "" or not req["vicini"].has(passo):
				if req.get("obbligo", false):
					# un passo verso il vicino più caldo
					var best: String = req["vicini"][0]
					for v in req["vicini"]:
						if h.get(v, 0.0) > h.get(best, 0.0):
							best = v
					return {"dest": best}
				return {"dest": ""}
			if not req.get("obbligo", false) and p_qui > 0.4:
				return {"dest": ""}
			return {"dest": passo}
		"zona":
			var mass := {"R": 0.0, "B": 0.0, "G": 0.0}
			for l in h:
				mass[p.zona(l)] += h[l]
			var best := "R"
			for z in mass:
				# la zona più vicina a metà certezza dà più informazioni
				if abs(mass[z] - 0.9) < abs(mass[best] - 0.9):
					best = z
			return {"zona": best}
		"luoghi2":
			var bestv := -1.0
			var bestp := [qui, p.vicini(qui)[0]]
			for a in p.mappa["luoghi"]:
				for b in p.vicini(a):
					var v: float = h.get(a, 0.0) + h.get(b, 0.0)
					if v > bestv:
						bestv = v
						bestp = [a, b]
			return {"luoghi": bestp}
		"porta":
			var porte: Array = req["porte"]
			var best: String = porte[0]
			var bv := -1.0
			for pt in porte:
				var ab: PackedStringArray = pt.split("|")
				var v: float = h.get(ab[0], 0.0) + h.get(ab[1], 0.0)
				for l in ab:
					if p.mappa["luoghi"][l].get("radio", false) or p.mappa["luoghi"][l].get("uscita", false):
						v += 0.3
				v += rng.randf() * 0.05
				if v > bv:
					bv = v
					best = pt
			return {"porta": best}
		"attacco":
			return {"carta": req["carte"][0]}
		"si_no":
			if "CERCARE" in req.get("titolo", ""):
				return {"si": p_qui > 0.3}
			if req.get("scopo", "") == "cima":
				return {"si": true}
			return {"si": mano.size() >= 4}
		"bersaglio_paura":
			var best: int = p.vivi()[0]
			for i in p.vivi():
				if p.s["sopr"][i]["paura"] > p.s["sopr"][best]["paura"]:
					best = i
			return {"i": best}
		"scarta_mano":
			return {"carta": _peggiori(1)[0]}
		"luogo":
			return {"dest": _scegli_luogo_k(req, h, obj)}
		"scelta":
			return {"n": _scegli_opzione_k(req, h, obj)}
		"sopravvissuto":
			var cand: Array = req["candidati"]
			var best: int = cand[0]
			var bv := 2.0
			for i in cand:
				var m := _max_cred(i)
				if m < bv:
					bv = m
					best = i
			return {"i": best}
	return {}

## Il luogo caldo più vicino a un certo punto (per le Statue).
func _obiettivo_da(da: String) -> String:
	var h := calore()
	var best := da
	var bv := -1.0
	for l in h:
		var v: float = h[l] / (1.0 + 0.35 * p.distanza(da, l))
		if v > bv:
			bv = v
			best = l
	return best

func _scegli_luogo_k(req: Dictionary, h: Dictionary, _obj: String) -> String:
	var cand: Array = req.get("luoghi", [])
	if cand.is_empty():
		return ""
	var k: Dictionary = p.s["killer"]
	var scopo: String = req.get("scopo", "")
	var best: String = cand[0]
	var bv := -999.0
	for l in cand:
		var v := 0.0
		var ld: Dictionary = p.mappa["luoghi"][l]
		match scopo:
			"trappola":
				v = -p.distanza(l, p.mappa["partenza_s"]) * 0.6 + (2.0 if ld.get("chiave", false) or ld.get("radio", false) else 0.0) + h.get(l, 0.0) * 3.0
				if p.distanza(l, p.mappa["partenza_s"]) == 0:
					v -= 5.0
			"statua":
				v = (2.0 if ld.get("chiave", false) or ld.get("radio", false) else 0.0) - p.distanza(l, p.mappa["partenza_s"]) * 0.3
				for st in p.s["statue"]:
					if p.distanza(st["pos"], l) <= 1:
						v -= 1.5
			"zombi", "nucleo":
				v = h.get(l, 0.0) * 3.0
				for x in p.entro(l, 1):
					v += h.get(x, 0.0)
				if ld.get("chiave", false) or ld.get("radio", false):
					v += 0.8
			"percepisci":
				v = h.get(l, 0.0) * (1.0 - h.get(l, 0.0))
			"furtivo", "teletrasporto":
				for x in p.entro(l, 1):
					v += h.get(x, 0.0)
				v += h.get(l, 0.0) * 2.0
			"zombi_scelta":
				for x in p.entro(l, 1):
					v += h.get(x, 0.0)
				v += p.zombi_in(l) * 0.1
			"orda", "acido":
				v = h.get(l, 0.0)
				for x in p.entro(l, 1):
					v += h.get(x, 0.0) * 0.3
			"dominio":
				v = -p.distanza(l, k["pos"])
			"nucleo_scelta":
				v = -h.get(l, 0.0)
			"udito":
				v = -p.distanza(k["pos"], l)
			_:
				v = h.get(l, 0.0)
		v += rng.randf() * 0.01
		if v > bv:
			bv = v
			best = l
	return best

func _scegli_opzione_k(req: Dictionary, h: Dictionary, _obj: String) -> int:
	var k: Dictionary = p.s["killer"]
	match req.get("scopo", ""):
		"principale":
			var best := 0
			var bv := -1.0
			for j in p.s["statue"].size():
				var v := 0.0
				for x in p.entro(p.s["statue"][j]["pos"], 2):
					v += h.get(x, 0.0)
				v += rng.randf() * 0.3
				if v > bv:
					bv = v
					best = j
			return best
		"statua_azione":
			var libere := []
			for j in p.s["statue"].size():
				if p.s["statue"][j]["gelo"] <= 0:
					libere.append(j)
			var best := 0
			var bv := -1.0
			for n in libere.size():
				var pos: String = p.s["statue"][libere[n]]["pos"]
				var v: float = h.get(pos, 0.0) * 3.0
				for x in p.vicini(pos):
					v += h.get(x, 0.0)
				v += rng.randf() * 0.2
				if v > bv:
					bv = v
					best = n
			return best
		"evoluzione":
			var chiavi: Array = req.get("chiavi", [])
			for e in ["mimetismo", "rettile", "sonar", "ghiandole"]:
				if chiavi.has(e):
					return chiavi.find(e)
			return 0
		"ultima":
			return 1
		"rimuovi":
			var ids: Array = req.get("carte_id", [])
			var peggio := 0
			for n in ids.size():
				if _valore_carta(ids[n]) < _valore_carta(ids[peggio]):
					peggio = n
			return peggio
		"telesintesi":
			var bv := 0.0
			for l in p.s["nuclei"]:
				bv = maxf(bv, h.get(l, 0.0))
			return 0 if bv > h.get(k["pos"], 0.0) + 0.15 else 1
		"cunicolo":
			return 1 if rng.randf() < 0.5 else 0
		"infrarossi":
			var vic := 0.0
			for l in p.entro(k["pos"], 1):
				vic += h.get(l, 0.0)
			return 1 if vic > 0.35 else 0
	return 0

## Decide se giocare una carta delle espansioni in una fase.
func _nuova_carta(c: String, fase: String, h: Dictionary, obj: String, vicino_caldo: float, p_qui: float) -> bool:
	var k: Dictionary = p.s["killer"]
	var mano: Array = k["mano"]
	var qui: String = k["pos"]
	match c:
		"ululato":
			var v2 := 0.0
			for l in p.entro(qui, 2):
				v2 += h.get(l, 0.0)
			return v2 > 0.6
		"caccia_sangue":
			return obj != qui and p.distanza(qui, obj) >= 2
		"territorio":
			if fase == "veloce":
				return _incertezza() > 0.55 and rng.randf() < 0.5
			return fase == "lenta"
		"udito":
			return not p.s["rumori"].is_empty()
		"istinto":
			return _incertezza() > 0.4 and mano.size() >= 3
		"tracce":
			return p_qui > 0.25 or _incertezza() > 0.5
		"fiato":
			return vicino_caldo > 0.4 or rng.randf() < 0.4
		"riarmo":
			return not p.s["trappole_scattate"].is_empty()
		"esplosione":
			for z in p.s["zombi"]:
				var v := 0.0
				for l in p.entro(z, 1):
					v += h.get(l, 0.0)
				if v > 0.6:
					return true
			return false
		"prendeteli":
			for z in p.s["zombi"]:
				if h.get(z, 0.0) > 0.3:
					return true
			return false
		"orda":
			return p.s["zombi"].size() >= 2 and rng.randf() < 0.5
		"dominio":
			return _incertezza() < 0.6
		"vapore":
			return fase == "lenta" and rng.randf() < 0.6
		"evocazione", "stele", "rampicante", "germoglio", "frenesia", "cunicolo":
			return fase == "lenta"
		"riposiziona":
			return fase == "lenta" and mano.size() >= 4
		"pattuglia":
			return fase == "speciale" and rng.randf() < 0.6
		"scatenate", "accerchiamento":
			return fase == "speciale"
		"telesintesi":
			return fase == "lenta" and rng.randf() < 0.6
		"avvinghiare":
			return fase == "lenta" and p_qui > 0.25
		"strisciare":
			return obj != qui and p_qui < 0.35
		"metamorfosi":
			return fase == "speciale" and k["scarti"].size() >= 2
		"infrarossi":
			return _incertezza() > 0.4
		"stridio":
			return true
		"acido":
			var v: float = h.get(qui, 0.0)
			for l in p.vicini(qui):
				v = maxf(v, h.get(qui, 0.0) + h.get(l, 0.0))
			return v > 0.35
	return false

func _max_cred(i: int) -> float:
	var m := 0.0
	for l in cred[i]:
		m = maxf(m, cred[i][l])
	return m

func _incertezza() -> float:
	var vv := p.vivi()
	if vv.is_empty():
		return 0.0
	var t := 0.0
	for i in vv:
		t += 1.0 - _max_cred(i)
	return t / vv.size()

# ================================================================ Sopravvissuti

func _kpos() -> String:
	return p.killer_visto()

func pericolo(l: String) -> float:
	var d := p.distanza_killer(l)
	if p.s["killer"]["furtivo"]:
		d = maxi(0, d - 1)
	var extra := 0.0
	if p.s["killer"]["id"] == "statue":
		for st in p.s["statue"]:
			if st["pos"] == l and st["gelo"] > 0 and d == 0:
				extra -= 0.5
	extra += 0.2 * p.zombi_in(l)
	if p.s["trappole_k"].has(l):
		extra += 0.6
	var base := 0.05
	match d:
		0: base = 1.0
		1: base = 0.75
		2: base = 0.4
		3: base = 0.15
	return maxf(0.0, base + extra)

## Una trappola lungo il percorso (prima della meta) ferma il movimento: meglio evitarla.
func _penalita(perc: Array) -> float:
	for n in perc.size():
		if p.s["trappole_k"].has(perc[n]):
			return 3.0 if n < perc.size() - 1 else 1.0
	return 0.0

func _obiettivo_s(i: int) -> String:
	var pp: Dictionary = p.s["sopr"][i]
	var luoghi: Dictionary = p.mappa["luoghi"]
	if p.s["soccorso"] > 0:
		# nascondersi il più lontano possibile
		var best: String = pp["pos"]
		for l in luoghi:
			if p.distanza_killer(l) > p.distanza_killer(best):
				best = l
		return best
	if p.s["chiavi"] >= 5:
		for l in luoghi:
			if luoghi[l].get("uscita", false):
				return l
	var ruolo: String = ruoli.get(i, "")
	if ruolo == "radio" and p.s["riparazione"] < Dati.RIPARAZIONE_MAX:
		for l in luoghi:
			if luoghi[l].get("radio", false):
				return l
	# luogo chiave più sicuro e vicino
	var best := ""
	var bv := 999.0
	for l in luoghi:
		var cerca_qui: bool = luoghi[l].get("chiave", false) or (pp["id"] == "caleb" and luoghi[l].get("spirale", false)) \
			or (luoghi[l].get("reliquie", false) and (not p.s["reliquie_aperte"] or not p.s["reliquie"].is_empty()))
		if cerca_qui:
			var v: float = p.distanza(pp["pos"], l) + 6.0 * pericolo(l)
			if v < bv:
				bv = v
				best = l
	return best if best != "" else pp["pos"]

func _assegna_ruoli() -> void:
	if _piano_ultimo_turno == p.s["turno"]:
		return
	_piano_ultimo_turno = p.s["turno"]
	ruoli.clear()
	var radio := ""
	for l in p.mappa["luoghi"]:
		if p.mappa["luoghi"][l].get("radio", false):
			radio = l
	var vv := p.vivi()
	if p.s["riparazione"] < Dati.RIPARAZIONE_MAX and radio != "":
		# il più vicino alla radio (meglio chi ha la cassetta o è Johnson)
		var best: int = vv[0]
		var bv := 999.0
		for i in vv:
			var v: float = p.distanza(p.s["sopr"][i]["pos"], radio)
			if p.ha_oggetto(i, "cassetta"):
				v -= 2
			if p.s["sopr"][i]["id"] == "johnson":
				v -= 1
			if v < bv:
				bv = v
				best = i
		ruoli[best] = "radio"
		# secondo riparatore se le chiavi scarseggiano
		if p.s["ricerca"].size() < 3:
			for i in vv:
				if not ruoli.has(i):
					ruoli[i] = "radio"
					break
	for i in vv:
		if not ruoli.has(i):
			ruoli[i] = "chiavi"

func _valore_ogg(o: String) -> float:
	var v := {"chiave": 10.0, "cassetta": 6.0, "mappa_segreta": 4.0, "revolver": 5.0, "spada": 5.0, "polvere": 4.5, "accetta": 4.0,
		"munizioni": 2.5, "erbe": 4.0, "adrenalina": 3.5, "tranquillante": 3.0, "torcia": 2.5, "petardo": 2.0, "whisky": 1.5,
		"trappola": 2.0, "kit_medico": 9.0, "moneta": 7.0, "macchina_foto": 1.0, "nota_difesa": 6.0, "nota_blocchi": 2.0, "nota_rumore": 2.0}
	if o == "cassetta" and p.s["riparazione"] >= Dati.RIPARAZIONE_MAX:
		return 1.0
	return v.get(o, 1.0)

func _decidi_s(req: Dictionary) -> Dictionary:
	match req["tipo"]:
		"azione_s":
			return _azione_s()
		"scoperta_chi":
			var vv := p.vivi()
			var best: int = vv[0]
			var bv := 999.0
			for i in vv:
				var pp: Dictionary = p.s["sopr"][i]
				var v: float = pericolo(pp["pos"]) * 3.0 + pp["oggetti"].size() * 0.5 - (1.0 if pp["id"] == "johnson" else 0.0)
				if v < bv:
					bv = v
					best = i
			return {"i": best}
		"scoperta_tieni":
			var carte: Array = req["carte"]
			var best := 0
			for k in carte.size():
				if _valore_ogg(carte[k]) > _valore_ogg(carte[best]):
					best = k
			return {"tieni": best}
		"cerca_tieni":
			return {"tieni": _valore_ogg(req["carta"]) >= 2.0}
		"cerca_ophelia":
			var c: Array = req["carte"]
			return {"tieni": 0 if _valore_ogg(c[0]) >= _valore_ogg(c[1]) else 1}
		"troppi_oggetti":
			var ogg: Array = p.s["sopr"][int(req["i"])]["oggetti"]
			var peggio := 0
			for k in ogg.size():
				if _valore_ogg(ogg[k]) < _valore_ogg(ogg[peggio]):
					peggio = k
			return {"ogg": peggio}
		"difensore":
			var cand: Array = req["candidati"]
			var best: int = cand[0]
			var bv := -99.0
			for i in cand:
				var pp: Dictionary = p.s["sopr"][i]
				var mig := 0
				for o in p.oggetti_difesa(i):
					mig = maxi(mig, int(o["bonus"]))
				var v: float = (4 - pp["paura"]) * 1.0 + mig - pp["ferite"] * 2.5 + (1.0 if pp["id"] == "william" and mig == 0 else 0.0)
				if v > bv:
					bv = v
					best = i
			return {"i": best}
		"oggetto_difesa":
			var opz: Array = req["opzioni"]
			if opz.is_empty():
				return {"ogg": -1}
			var best: Dictionary = opz[0]
			for o in opz:
				if int(o["bonus"]) > int(best["bonus"]):
					best = o
			# William senza arma ha già +1: un'arma da +1 non serve
			var pp: Dictionary = p.s["sopr"][int(req["i"])]
			if pp["id"] == "william" and int(best["bonus"]) <= 1:
				return {"ogg": -1}
			return {"ogg": best["ogg"], "ogg2": best.get("ogg2", -1), "munizioni": best.get("munizioni", false)}
		"fuga":
			var best := ""
			var bd := p.distanza_killer(p.s["sopr"][int(req["i"])]["pos"])
			for l in req["luoghi"]:
				var d := p.distanza_killer(l)
				if d > bd:
					bd = d
					best = l
			return {"dest": best}
		"sopravvissuto":
			var cand: Array = req["candidati"]
			var best: int = cand[0]
			for i in cand:
				if p.s["sopr"][i]["oggetti"].size() < p.s["sopr"][best]["oggetti"].size():
					best = i
			return {"i": best}
		"nota_george":
			var i := int(req["i"])
			if not p.ha_oggetto(i, "nota_difesa"):
				return {"nota": "nota_difesa"}
			return {"nota": "nota_blocchi"}
	return {}

func _azione_s() -> Dictionary:
	_assegna_ruoli()
	var vv := p.vivi()
	# prima gli extra utili, poi l'azione principale di chi non ha ancora agito
	vv.sort_custom(func(a, b): return pericolo(p.s["sopr"][a]["pos"]) > pericolo(p.s["sopr"][b]["pos"]))
	# con 5 chiavi: tutti all'uscita
	if p.s["chiavi"] >= 5:
		var uscita := _obiettivo_s(vv[0])
		for i in vv:
			var pp: Dictionary = p.s["sopr"][i]
			if pp["agito"] or pp["pos"] == uscita:
				continue
			var ragg := p.raggiungibili_sopr(i, 3 if pp["id"] == "william" else 2)
			var best: Array = []
			var bd := p.distanza(pp["pos"], uscita)
			for l in ragg:
				if p.distanza(l, uscita) < bd and ragg[l].size() <= (3 if pp["id"] == "william" else 2):
					bd = p.distanza(l, uscita)
					best = ragg[l]
			if not best.is_empty():
				return {"a": "scatto" if best.size() == 3 else "muovi", "i": i, "percorso": best}
	for i in vv:
		var pp: Dictionary = p.s["sopr"][i]
		var poss := p.azioni_possibili(i)
		var l: String = pp["pos"]
		var danger := pericolo(l)
		# extra: tranquillante se la paura è al massimo
		if poss.has("usa"):
			for k in poss["usa"]:
				var o: String = pp["oggetti"][k]
				if o == "tranquillante" and pp["paura"] >= 2:
					return {"a": "usa", "i": i, "ogg": k, "bersaglio": i}
				if o == "adrenalina" and pp["agito"] and danger >= 0.75:
					var fuga := _miglior_rifugio(i, 1)
					if fuga.size() == 1:
						return {"a": "usa", "i": i, "ogg": k, "percorso": fuga}
				if o == "moneta" and pp["agito"]:
					var perc := _miglior_rifugio(i, 2) if danger >= 0.4 else []
					return {"a": "usa", "i": i, "ogg": k, "percorso": perc}
		if poss.has("meccanica") and p.s["riparazione"] < Dati.RIPARAZIONE_MAX:
			return {"a": "meccanica", "i": i}
		if poss.has("forziere") and danger < 1.0:
			return {"a": "forziere", "i": i}
		if poss.has("usa"):
			for k in poss["usa"]:
				if pp["oggetti"][k] == "specchio" and danger >= 0.75:
					return {"a": "usa", "i": i, "ogg": k}
		if poss.has("valigia") and danger < 0.75:
			return {"a": "valigia", "i": i}
		if poss.has("leva") and not p.s["killer"]["furtivo"]:
			var kp := _kpos()
			var miglior := ""
			var md := 99
			for pt in p.porte_di(kp):
				var ab: PackedStringArray = pt.split("|")
				var oltre: String = ab[1] if ab[0] == kp else ab[0]
				for j in p.vivi():
					var dd := p.distanza(oltre, p.s["sopr"][j]["pos"])
					if dd < md:
						md = dd
						miglior = pt
			if miglior != "" and p.s["cancello"] != miglior and md <= 2:
				return {"a": "leva", "i": i, "porta": miglior}
		if pp["agito"]:
			continue
		# azione principale
		if poss.has("congela") and danger >= 0.75:
			return {"a": "congela", "i": i}
		if poss.has("usa"):
			for k in poss["usa"]:
				if pp["oggetti"][k] == "balestra" and danger < 1.0:
					return {"a": "usa", "i": i, "ogg": k}
				if pp["oggetti"][k] == "sfera" and danger < 0.75:
					return {"a": "usa", "i": i, "ogg": k}
		if poss.has("crollo") and danger >= 0.4 and danger < 1.0 and rng.randf() < 0.35:
			return {"a": "crollo", "i": i}
		if pp["ferite"] > 0 and poss.has("usa"):
			for k in poss["usa"]:
				if pp["oggetti"][k] in ["erbe", "kit_medico"] and danger < 0.75:
					return {"a": "usa", "i": i, "ogg": k, "bersaglio": i}
		if danger >= 0.75:
			# scappa
			var dove := _miglior_rifugio(i, 3 if poss.has("scatto") and danger >= 1.0 else 2)
			if not dove.is_empty():
				return {"a": "scatto" if dove.size() == 3 else "muovi", "i": i, "percorso": dove}
		if pp["paura"] >= 2 and poss.has("paura") and danger >= 0.4:
			return {"a": "paura", "i": i}
		if poss.has("ripara") and danger < 0.75:
			for k in pp["oggetti"].size():
				if pp["oggetti"][k] == "cassetta" and p.puo_usare(i, k):
					return {"a": "usa", "i": i, "ogg": k}
			return {"a": "ripara", "i": i}
		if poss.has("cerca") and danger < 0.75 and ruoli.get(i, "") != "radio":
			return {"a": "cerca", "i": i}
		if poss.has("apri_reliquie") and danger < 0.75:
			return {"a": "apri_reliquie", "i": i}
		if poss.has("cerca_reliquie") and danger < 0.75:
			return {"a": "cerca_reliquie", "i": i}
		if poss.has("nucleo") and danger < 0.75:
			return {"a": "nucleo", "i": i}
		if poss.has("cerca") and danger < 0.4 and p.s["riparazione"] >= Dati.RIPARAZIONE_MAX:
			return {"a": "cerca", "i": i}
		if poss.has("mente"):
			return {"a": "mente", "i": i, "scelta": poss["mente"][0]}
		if poss.has("incoraggia"):
			for j in poss["incoraggia"]:
				if p.s["sopr"][j]["paura"] >= 2:
					return {"a": "incoraggia", "i": i, "bersaglio": j}
		var obj := _obiettivo_s(i)
		if obj != l:
			var perc := _percorso_sicuro(i, obj, 2)
			if not perc.is_empty():
				return {"a": "muovi", "i": i, "percorso": perc}
		if poss.has("blocco"):
			return {"a": "blocco", "i": i, "porta": poss["blocco"][0]}
		if poss.has("paura"):
			return {"a": "paura", "i": i}
	return {"a": "fine"}

## Il percorso (fino a n passi) che porta più vicino all'obiettivo evitando il Killer.
func _percorso_sicuro(i: int, obj: String, n: int) -> Array:
	var ragg := p.raggiungibili_sopr(i, n)
	var best: Array = []
	var pp: Dictionary = p.s["sopr"][i]
	var bv: float = p.distanza(pp["pos"], obj) + 5.0 * pericolo(pp["pos"])
	for l in ragg:
		var v: float = p.distanza(l, obj) + 5.0 * pericolo(l) + _penalita(ragg[l]) * 2.0 + rng.randf() * 0.1
		if v < bv:
			bv = v
			best = ragg[l]
	return best

func _miglior_rifugio(i: int, n: int) -> Array:
	var ragg := p.raggiungibili_sopr(i, n)
	var best: Array = []
	var bv := pericolo(p.s["sopr"][i]["pos"])
	for l in ragg:
		if ragg[l].size() > n:
			continue
		var v := pericolo(l) + _penalita(ragg[l]) * 0.5 + rng.randf() * 0.05
		if v < bv:
			bv = v
			best = ragg[l]
	return best
