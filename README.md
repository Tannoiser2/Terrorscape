# Terrorscape — versione digitale (uso personale)

Versione digitale di **Terrorscape** (Ice Makes), il gioco horror di sopravvivenza a squadre:
tre Sopravvissuti intrappolati nella Villa cercano le chiavi o riparano la radio per fuggire,
mentre il Killer li bracca senza sapere dove si nascondono. Fatto in Godot 4.7, gira nel browser.

Grafica, carte, regole e personaggi appartengono a Ice Makes e ai rispettivi autori:
questa conversione è solo per uso personale, ricavata dal modulo per Tabletop Simulator.

## Cosa c'è

- **Cinque mappe**, ognuna con porte bloccabili, radio e luoghi delle chiavi:
  - **La Villa** (gioco base);
  - **La Baita** (valigia nella Stanza 102, passaggio riservato al Killer);
  - **Il Castello** (controllo della leva e saracinesca: il Killer deve scartare 3 carte per
    attraversarla; il Corridoio delle Statue spaventa il primo che ci entra);
  - **La Tomba** (Camera delle reliquie da aprire, con il suo mazzo di reliquie; corridoi che
    possono crollare);
  - **Il Laboratorio** (armadietto di primo soccorso, Stanza sterile rumorosa, porta già bloccata).
  La plancia è in 3D e mostra solo il tabellone del lato che stai giocando:
  il Killer vede il suo (con i rumori e i Sopravvissuti avvistati), i Sopravvissuti il loro.
- **Nove Killer** con mazzo, carta bloccata e i cinque livelli: il Macellaio, lo Spettro, l'Assassino
  (gioco base) e, dalle espansioni, il **Lupo Mannaro** (scrigni con armi d'argento), la **Cacciatrice**
  (trappole coperte), la **Regina** (zombi, veleno e la Balestra), le **Statue** (quattro statue, una
  sola è la principale), lo **Strangolatore** (noccioli e viticci) e l'**Ignoto** (passaggi segreti e
  carte Evoluzione).
- **Nove Sopravvissuti** con le loro abilità e i loro oggetti personali: Anna, William, Sophia, Marco,
  Johnson (gioco base) e George, Ophelia, Dylan, Caleb (espansioni).
- Tutte le regole del turno: azioni dei Sopravvissuti, azioni extra, scambi, scoperta, rumori,
  paura che trabocca, blocchi, furtività e ricomparsa, incontri con tiro dei dadi difesa,
  fuga dopo l'incontro, livelli del Killer, vittoria per fuga (anche dall'uscita nascosta con la
  Mappa segreta), per soccorso o per eliminazione.
- **Contro il computer** in entrambi i ruoli, oppure "guarda il computer giocare".
  L'IA non bara: il Killer automatico ragiona su una mappa di probabilità costruita solo con quello
  che sa davvero (rumori, percezioni, paura, incontri); i Sopravvissuti automatici vedono il Killer
  solo quando non è furtivo.
- **Gioco online** a due (Killer contro Sopravvissuti) con Firebase.
- Interfaccia, testi delle carte e regole in italiano (passando sopra una carta la si ingrandisce
  con il testo tradotto).

## Note sul materiale

Il modulo TTS di partenza ha alcune immagini vuote: mancano 18 delle 32 carte del mazzo scoperta,
7 delle 10 del mazzo ricerca, la tessera salute di William e il tabellone del Laboratorio.
Le carte oggetto mancanti sono ricostruite dal regolamento (Chiave, Torcia, Petardo, Bottiglia di
whisky, Polvere di calce, Tranquillante, Revolver, Munizioni) e disegnate dal gioco nello stesso
stile; i loro effetti sono in `scripts/dati.gd` e si possono correggere facilmente.
Le regole speciali di mappe e Killer delle espansioni seguono il regolamento italiano delle
espansioni (Immortali letali, Pericolo informe, Istinti selvaggi). Restano ricostruite da me:
- **Il Laboratorio**: nel modulo il tabellone è vuoto, quindi è ricavato (ingrandito) dalla
  panoramica delle mappe ed è meno nitido degli altri; i collegamenti sono letti da quell'immagine.
- **La Tomba**: il regolamento in mano non la descrive. Ho dedotto le regole dai simboli: la Camera
  delle reliquie si apre con un'azione speciale (rumore) e poi vi si cerca nel mazzo delle reliquie;
  i corridoi con le macerie possono crollare (una volta il Killer, una volta i Sopravvissuti).
- **Regina**: il regolamento in mano non la descrive. Gli zombi non agiscono da soli; la Balestra
  elimina prima gli zombi del proprio luogo.
- Le carte promo «Dice Tower» (Lampada a olio, Pacco misterioso, Dadi della fortuna) non sono incluse.

## Gioco online

Si usa lo stesso progetto Firebase degli altri giochi della ludoteca (flammerouge-f8669), con la
radice `terrorscape/rooms`. Chi crea la stanza sceglie il proprio ruolo, il Killer, i Sopravvissuti
e la mappa, e comunica il codice di 4 lettere; l'altro entra col codice e prende il ruolo opposto.
Le due copie del gioco ricevono le stesse decisioni nello stesso ordine e usano lo stesso seme:
giocano quindi esattamente la stessa partita, e ognuna mostra solo ciò che il proprio lato può
vedere. Chi ricarica la pagina può rientrare: la partita viene rigiocata fino al punto giusto.

**Regole del database.** In `firebase/database.rules.json` c'è la sezione `terrorscape` da aggiungere
alle regole già pubblicate (Realtime Database → Regole), accanto alle radici degli altri giochi.

## Struttura

- `scripts/dati.gd`: mappe, Killer, carte abilità, Sopravvissuti e oggetti.
- `scripts/regole.gd`: il motore delle regole, senza grafica (una coroutine che chiede le decisioni).
- `scripts/ia.gd`: il giocatore automatico per i due lati.
- `scripts/plancia3d.gd`: tabellone, sagome, segnalini e telecamera.
- `scripts/main.gd`: menu, preparazione, interfaccia dei due ruoli e gioco online.
- `scripts/rete.gd`: collegamento a Firebase.
- `tests/`: simulazioni IA contro IA (`sim.gd`), collaudo dell'interfaccia (`ui_auto.gd`),
  screenshot automatici (`foto.gd`).

La versione web viene costruita e pubblicata su GitHub Pages da `.github/workflows/pages.yml`.
