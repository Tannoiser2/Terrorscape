## Dati di Terrorscape: mappe, Killer, Sopravvissuti, carte abilità e oggetti.
## Le posizioni sulle mappe sono frazioni (0..1) della larghezza e dell'altezza del tabellone.
class_name Dati
extends RefCounted

# ---------------------------------------------------------------- mappe

## Ogni luogo: nome, zona (R rossa, B blu, G verde), posizione sul tabellone e simboli speciali:
##   chiave = si può [CERCARE] (luogo oggetti), radio = si ripara la radio,
##   passaggio = gruppo del passaggio segreto (I, II), libro / martello / spirale = luoghi speciali
##   uscita = uscita principale, uscita_nascosta = uscita nascosta (serve la Mappa segreta)
const MAPPE := {
	"villa": {
		"nome": "La Villa",
		"tabellone_k": "res://assets/tabelloni/villa_killer.webp",
		"tabellone_s": "res://assets/tabelloni/villa_sopravvissuti.webp",
		"partenza_s": "R1", "partenza_k": "G5",
		"uscita_xy": [0.161, 0.465], "uscita_nascosta_xy": [0.754, 0.465],
		"luoghi": {
			"B1": {"nome": "Salotto", "xy": [0.263, 0.215], "radio": true, "passaggio": "I"},
			"B2": {"nome": "Sala da pranzo", "xy": [0.405, 0.235]},
			"B3": {"nome": "Cucina", "xy": [0.537, 0.165]},
			"B4": {"nome": "Ripostiglio", "xy": [0.672, 0.205], "chiave": true},
			"B5": {"nome": "Sala dei banchetti", "xy": [0.575, 0.465], "passaggio": "II"},
			"R1": {"nome": "Atrio", "xy": [0.245, 0.455], "uscita": true},
			"R2": {"nome": "Galleria", "xy": [0.250, 0.700], "chiave": true},
			"R3": {"nome": "Corridoio", "xy": [0.430, 0.435]},
			"R4": {"nome": "Studio", "xy": [0.440, 0.585], "libro": true},
			"R5": {"nome": "Biblioteca", "xy": [0.415, 0.755]},
			"G1": {"nome": "Sentiero", "xy": [0.360, 0.885]},
			"G2": {"nome": "Cimitero", "xy": [0.495, 0.880], "passaggio": "I", "spirale": true},
			"G3": {"nome": "Capanno", "xy": [0.690, 0.840], "martello": true},
			"G4": {"nome": "Serra", "xy": [0.555, 0.725], "chiave": true},
			"G5": {"nome": "Giardino", "xy": [0.708, 0.465], "uscita_nascosta": true},
		},
		## Collegamenti: porta (si può bloccare) o aperto (linea tratteggiata). xy = dove sta la porta.
		"collegamenti": [
			["B1", "B2", "porta", [0.324, 0.161]],
			["B2", "B3", "porta", [0.457, 0.161]],
			["B3", "B4", "porta", [0.609, 0.161]],
			["B1", "R1", "porta", [0.237, 0.317]],
			["R1", "B2", "porta", [0.311, 0.357]],
			["B2", "B5", "porta", [0.499, 0.309]],
			["R3", "B5", "porta", [0.499, 0.422]],
			["R4", "B5", "porta", [0.499, 0.570]],
			["B4", "G5", "porta", [0.689, 0.313]],
			["R1", "R3", "porta", [0.300, 0.574]],
			["R2", "R3", "porta", [0.304, 0.643]],
			["R1", "R2", "porta", [0.243, 0.600]],
			["R2", "R5", "porta", [0.333, 0.726]],
			["R4", "R5", "porta", [0.452, 0.687]],
			["R5", "G4", "porta", [0.499, 0.748]],
			["G4", "G3", "porta", [0.609, 0.683]],
			["R2", "G1", "porta", [0.296, 0.813]],
			["G1", "G2", "aperto", [0.428, 0.870]],
			["G2", "G3", "aperto", [0.559, 0.870]],
			["G5", "G3", "aperto", [0.698, 0.630]],
		],
	},
}

const ZONE := {"R": "Rossa", "B": "Blu", "G": "Verde"}
const ZONA_COLORE := {"R": Color("#c0392b"), "B": Color("#2f6fd6"), "G": Color("#3c9a3c")}

# ---------------------------------------------------------------- Killer

## tipo: veloce (fulmine arancio), speciale (freccia blu), lenta (clessidra verde), attacco (spade viola).
## costo: carte da scartare dalla mano (diverse da questa); -1 = tutta la mano.
const CARTE_KILLER := {
	# ---- comuni (ogni Killer ha le sue copie)
	"inseguimento": {"nome": "Inseguimento", "tipo": "veloce", "costo": 0, "testo": "[MUOVI] x1"},
	"percezione": {"nome": "Percezione", "tipo": "veloce", "costo": 0, "testo": "[PERCEPISCI] una zona di colore"},
	# ---- Macellaio
	"follia": {"nome": "Follia", "tipo": "veloce", "costo": 2, "testo": "[BLOCCA] x1 nella tua posizione\n+2 Forza in questo turno"},
	"barricata": {"nome": "Barricata", "tipo": "lenta", "costo": 0, "testo": "[BLOCCA] x1 nella tua posizione"},
	"resta": {"nome": "RESTAAA!", "tipo": "lenta", "costo": 4, "testo": "[BLOCCA] tutte le porte della tua posizione"},
	"motosega": {"nome": "Motosega rombante", "tipo": "speciale", "costo": 2, "testo": "[PAURA] entro 1 di distanza\n[MUOVI] x0-1, ferisci tutti i Sopravvissuti nella tua posizione"},
	"furia": {"nome": "Furia brutale", "tipo": "speciale", "costo": 1, "testo": "[MUOVI] x1-2, [CERCA]\nSe non trovi nessuno E hai rimosso un blocco, ripeti."},
	# ---- Spettro
	"urlo": {"nome": "Urlo", "tipo": "veloce", "costo": 0, "testo": "[PAURA] entro 1 di distanza"},
	"svanire": {"nome": "Svanire", "tipo": "lenta", "costo": 1, "testo": "[FURTIVO] x0-2\n[PAURA] entro 1 di distanza quando riappari"},
	"scia": {"nome": "Scia di paura", "tipo": "veloce", "costo": 1, "testo": "Tutti i Sopravvissuti con almeno 1 paura rivelano la loro posizione"},
	"sfrecciare": {"nome": "Sfrecciare", "tipo": "speciale", "costo": 0, "testo": "[MUOVI] x1-4, [PAURA] a tutti i Sopravvissuti lungo il percorso (partenza compresa)"},
	"risucchio": {"nome": "Risucchio vitale", "tipo": "speciale", "costo": -1, "testo": "Costo: scarta tutta la mano.\nFerisci tutti i Sopravvissuti con almeno 1 paura"},
	# ---- Assassino
	"deduzione": {"nome": "Deduzione logica", "tipo": "veloce", "costo": 1, "testo": "[PERCEPISCI] 2 luoghi collegati a tua scelta"},
	"avviso": {"nome": "Avviso di morte", "tipo": "veloce", "costo": 1, "testo": "[PAURA] a tutti i Sopravvissuti"},
	"minaccia": {"nome": "Minaccia in agguato", "tipo": "lenta", "costo": 1, "testo": "[FURTIVO] x0-2\n[PAURA] a 1 Sopravvissuto a tua scelta quando riappari"},
	"appostamento": {"nome": "Appostamento", "tipo": "lenta", "attacco": true, "costo": 0, "testo": "+1 Forza in questo attacco\noppure\n[FURTIVO] x0-2"},
	"fioritura": {"nome": "Fioritura di morte", "tipo": "lenta", "costo": 2, "testo": "[FURTIVO] x0-2\nUccidi tutti i Sopravvissuti entro 1 di distanza quando riappari"},
}

const KILLER := {
	"macellaio": {
		"nome": "Il Macellaio", "forza": 5, "mini": "res://assets/mini/macellaio.webp",
		"plancia": "res://assets/killer/macellaio_plancia.webp", "dorso": "res://assets/killer/macellaio_dorso.webp",
		"mazzo": {"inseguimento": 3, "follia": 1, "barricata": 3, "percezione": 2, "resta": 1, "motosega": 2},
		"bloccata": "furia",
		"livelli": ["—", "+1 Forza", "Sblocca «Furia brutale»", "«Motosega rombante» diventa veloce",
			"Quando avviene un incontro, ferisci tutti i bersagli prima di attaccare"],
		"descrizione": "Diretto e brutale: barrica le porte e fa a pezzi chi trova. Consigliato per la prima partita da Killer.",
	},
	"spettro": {
		"nome": "Lo Spettro", "forza": 3, "mini": "res://assets/mini/spettro.webp",
		"plancia": "res://assets/killer/spettro_plancia.webp", "dorso": "res://assets/killer/spettro_dorso.webp",
		"mazzo": {"inseguimento": 2, "urlo": 2, "svanire": 2, "percezione": 3, "sfrecciare": 2, "scia": 1},
		"bloccata": "risucchio",
		"livelli": ["[PAURA] a tutti i bersagli quando incontri dei Sopravvissuti",
			"Dopo «Sfrecciare» puoi scartare 2 carte per [CERCARE]",
			"Quando la paura di un Sopravvissuto trabocca, puoi scartare 3 carte per ferirlo",
			"Sblocca «Risucchio vitale»",
			"Ferisci subito tutti i bersagli quando incontri dei Sopravvissuti, poi prosegui l'attacco"],
		"descrizione": "Debole in combattimento ma terrorizzante: semina paura ovunque e svanisce nel nulla.",
	},
	"assassino": {
		"nome": "L'Assassino", "forza": 4, "mini": "res://assets/mini/assassino.webp",
		"plancia": "res://assets/killer/assassino_plancia.webp", "dorso": "res://assets/killer/assassino_dorso.webp",
		"mazzo": {"inseguimento": 4, "appostamento": 2, "avviso": 1, "percezione": 2, "deduzione": 2, "minaccia": 1},
		"bloccata": "fioritura",
		"livelli": ["—", "+3 Forza se incontri dei Sopravvissuti quando riappari",
			"Sblocca «Fioritura di morte»", "+2 Forza; [BLOCCA] x4 in luoghi qualsiasi, subito",
			"Ferisci subito tutti i bersagli quando incontri dei Sopravvissuti, poi prosegui l'attacco"],
		"descrizione": "Un cacciatore metodico: si muove nell'ombra, deduce, e colpisce quando riappare.",
	},
}

## Immagine della carta: res://assets/carte/<killer>_<carta>.webp
static func img_carta(killer: String, carta: String) -> String:
	var nomi := {"inseguimento": "inseguimento", "percezione": "percezione", "follia": "follia", "barricata": "barricata",
		"resta": "resta", "motosega": "motosega", "furia": "furia", "urlo": "urlo", "svanire": "svanire", "scia": "scia",
		"sfrecciare": "sfrecciare", "risucchio": "risucchio", "deduzione": "deduzione", "avviso": "avviso",
		"minaccia": "minaccia", "appostamento": "appostamento", "fioritura": "fioritura"}
	return "res://assets/carte/%s_%s.webp" % [killer, nomi.get(carta, carta)]

# ---------------------------------------------------------------- Sopravvissuti

const SOPRAVVISSUTI := {
	"anna": {"nome": "Anna Kubrick", "ruolo": "Studentessa", "colore": Color("#d65a3a"),
		"abilita": [["Basso profilo", "Sei invisibile a [PERCEPISCI]."], ["Meticolosa", "Non fai rumore quando [CERCHI]."]]},
	"william": {"nome": "William Hooper", "ruolo": "Atleta", "colore": Color("#e0b030"),
		"abilita": [["Tenacia", "+1 difesa se non usi un'arma."], ["Scatto", "Sostituisce l'azione: [MUOVI] x3, rumore nel luogo d'arrivo."]]},
	"sophia": {"nome": "Sophia Scott", "ruolo": "Detective", "colore": Color("#e07a2a"), "inizio": ["macchina_foto"],
		"abilita": [["Ingegnosa", "Inizia con la Macchina fotografica di Sophia."], ["Osservatrice", "Sostituisce l'azione: attraversa un passaggio segreto (diventa un'azione extra se hai una Torcia)."]]},
	"marco": {"nome": "Marco Carven", "ruolo": "Medico", "colore": Color("#7a5ad0"), "inizio": ["kit_medico"],
		"abilita": [["Previdente", "Inizia con il Kit medico di Marco."], ["Pieno di risorse", "Sostituisce l'azione: prendi un'Adrenalina o un Tranquillante dagli scarti."]]},
	"johnson": {"nome": "Johnson Nispel", "ruolo": "Ingegnere", "colore": Color("#3aa6c8"),
		"abilita": [["Zaino XL", "Nessun limite al numero di oggetti."], ["Esperto di meccanica", "+1 riparazione extra quando ripari la radio con una Cassetta degli attrezzi."]]},
	"george": {"nome": "George Carpenter", "ruolo": "Professore", "colore": Color("#4fbf4f"),
		"abilita": [["Mente brillante", "(Nel luogo col libro) Azione speciale: scarta una Cassetta degli attrezzi per +1 riparazione, OPPURE pesca dal mazzo ricerca."], ["Percettivo", "A fine turno dei Sopravvissuti, se sei entro 1 di distanza dal Killer, prendi una Nota di George a scelta."]]},
	"ophelia": {"nome": "Ophelia Romero", "ruolo": "Reporter", "colore": Color("#d04080"),
		"abilita": [["Parole d'incoraggiamento", "Azione speciale: togli tutta la paura a un Sopravvissuto nel tuo luogo e dagli un segnalino Incoraggiamento (annulla una paura o +1 difesa)."], ["Sesto senso", "Quando [CERCHI] peschi 2 carte e ne rimetti 1 in cima al mazzo (senza rumore)."]]},
	"dylan": {"nome": "Dylan Wan", "ruolo": "Cameraman", "colore": Color("#a07040"),
		"abilita": [["Tempra", "Inizia con un segnalino Tempra: evita la prima ferita togliendolo."], ["Meccanica", "(Nel luogo col martello) Azione extra: prendi una Cassetta degli attrezzi dagli scarti."]]},
	"caleb": {"nome": "Caleb Peele", "ruolo": "Produttore", "colore": Color("#3a60c0"), "inizio": ["moneta"],
		"abilita": [["La moneta fortunata", "Inizia con la Moneta fortunata di Caleb."], ["Appassionato di misteri", "Puoi [CERCARE] nel luogo con la spirale."]]},
}

# ---------------------------------------------------------------- oggetti

## arma: conta come arma (William perde Tenacia). difesa: bonus in difesa. infinito: non si scarta.
## uso: "speciale" (azione dei Sopravvissuti), "extra" (azione extra), "difesa", "passivo".
## rumore: fa rumore quando lo peschi. img: immagine originale (se manca, la carta è disegnata dal gioco).
const OGGETTI := {
	"chiave": {"nome": "Chiave", "rumore": true, "uso": "passivo", "testo": "Va subito sul portachiavi. Servono 5 chiavi per fuggire."},
	"cassetta": {"nome": "Cassetta degli attrezzi", "rumore": true, "uso": "speciale", "img": "cassetta",
		"testo": "(Nel luogo della radio) Azione speciale: +2 riparazione e rumore nel tuo luogo."},
	"erbe": {"nome": "Erbe medicinali", "uso": "speciale", "img": "erbe", "testo": "Azione speciale: [CURA] e rumore nel tuo luogo."},
	"accetta": {"nome": "Accetta", "arma": true, "difesa": 1, "uso": "difesa", "img": "accetta",
		"testo": "+1 difesa, oppure Azione extra: togli un blocco nel tuo luogo."},
	"adrenalina": {"nome": "Adrenalina", "uso": "extra", "img": "adrenalina", "testo": "Azione extra: [MUOVI] x1."},
	"spada": {"nome": "Spada corta", "arma": true, "difesa": 1, "infinito": true, "uso": "difesa", "img": "spada", "testo": "+1 difesa. (Infinito)"},
	"mappa_segreta": {"nome": "Mappa segreta", "uso": "passivo", "img": "mappa_segreta", "testo": "Con 5 chiavi potete fuggire anche dall'uscita nascosta."},
	"trappola": {"nome": "Pezzi di trappola", "uso": "speciale", "img": "trappola",
		"testo": "Azione speciale: piazza la trappola nel tuo luogo (+2 difesa nel prossimo attacco qui)."},
	"polvere": {"nome": "Polvere di calce", "difesa": 2, "uso": "difesa", "testo": "+2 difesa (si scarta dopo l'uso)."},
	"whisky": {"nome": "Bottiglia di whisky", "uso": "extra", "testo": "Azione extra: lanciala per fare rumore in un luogo entro 1 di distanza (anche oltre un blocco)."},
	"tranquillante": {"nome": "Tranquillante", "uso": "extra", "testo": "Azione extra: togli tutta la paura a un Sopravvissuto nel tuo luogo."},
	"torcia": {"nome": "Torcia", "uso": "passivo", "infinito": true, "testo": "Puoi [MUOVERTI] attraverso i passaggi segreti. (Infinito)"},
	"petardo": {"nome": "Petardo", "uso": "extra", "testo": "Azione extra: rumore ovunque. Copre tutti i rumori di questo turno (il segnalino va nel luogo del Killer)."},
	"revolver": {"nome": "Revolver", "arma": true, "difesa": 1, "infinito": true, "uso": "difesa", "testo": "+1 difesa. Scartando anche le Munizioni: +3 difesa in più. (Infinito)"},
	"munizioni": {"nome": "Munizioni", "uso": "passivo", "testo": "Con il Revolver: +3 difesa (si scartano)."},
	# oggetti dei personaggi
	"macchina_foto": {"nome": "Macchina fotografica di Sophia", "uso": "extra", "img": "macchina_foto", "solo": "sophia",
		"testo": "(Solo Sophia) Azione extra: rumore nel tuo luogo (un diversivo)."},
	"kit_medico": {"nome": "Kit medico di Marco", "uso": "speciale", "img": "kit_medico", "solo": "marco", "infinito": true,
		"testo": "(Solo Marco) Azione speciale: [CURA] e togli tutta la paura."},
	"moneta": {"nome": "Moneta fortunata di Caleb", "uso": "extra", "img": "moneta", "solo": "caleb", "infinito": true,
		"testo": "(Solo Caleb) Azione extra, una volta per turno: scarta la prima carta del mazzo ricerca: se è una Chiave [CURA], altrimenti [MUOVI] x0-2."},
	"nota_blocchi": {"nome": "Nota di George (blocchi)", "uso": "extra", "img": "nota_blocchi", "solo": "george",
		"testo": "(Solo George) Azione extra: togli 2 blocchi nel tuo luogo."},
	"nota_rumore": {"nome": "Nota di George (rumore)", "uso": "extra", "img": "nota_rumore", "solo": "george",
		"testo": "(Solo George) Azione extra: rumore in un luogo qualsiasi."},
	"nota_difesa": {"nome": "Nota di George (difesa)", "uso": "passivo", "img": "nota_difesa", "solo": "george", "infinito": true,
		"testo": "(Solo George) Quando usi un oggetto per difenderti, +2 difesa extra."},
}

## Composizione dei mazzi oggetto del gioco base (ricostruita dal modulo TTS: 14 carte hanno l'immagine originale,
## le altre sono ricostruite dal regolamento).
const MAZZO_RICERCA := {"chiave": 4, "cassetta": 2, "erbe": 1, "torcia": 1, "petardo": 1, "polvere": 1}
const MAZZO_SCOPERTA := {"accetta": 3, "erbe": 3, "adrenalina": 3, "polvere": 3, "whisky": 3, "tranquillante": 3,
	"chiave": 2, "cassetta": 2, "torcia": 2, "spada": 1, "mappa_segreta": 1, "trappola": 1, "revolver": 1, "munizioni": 2,
	"petardo": 2}

static func img_oggetto(id: String) -> String:
	var o: Dictionary = OGGETTI.get(id, {})
	return "res://assets/oggetti/%s.webp" % o["img"] if o.has("img") else ""

## Facce del dado difesa.
const DADO := [0, 0, 1, 1, 1, 3]
const BLOCCHI_MAX := 7
const RIPARAZIONE_MAX := 5
const SOCCORSO_TURNI := 5
const MANO_MAX := 5
const FORZA_MAX := 10
