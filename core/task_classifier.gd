@tool
class_name TaskClassifier
extends RefCounted

## Infers how an activity should animate from what it is called.
##
## Schedules already say what each task is -- "Hormigonado de zapatas",
## "Mampostería de granito", "Excavación de zanjas" -- so asking the author to
## also type `fill_up` / `build_up` / `sink_down` against every row repeats
## information the name already carries. This reads the name instead.
##
## Spanish, Galician, Portuguese and English construction vocabulary. Matching
## is on word *starts* after normalisation (lower case, accents stripped,
## CamelCase and `_`/`-` split), so a code like `C10_PilaresPB` reads as
## "c pilares pb" and `hormig` covers hormigón, hormigonado and hormigonar.
##
## Several keywords can match one name ("Zapatas de hormigón armado" has an
## element, a material and a rebar word). Every rule has a priority, and the
## highest-priority match wins: what is being *done* (demolish, dig, pour)
## outranks what it is done *to* (a footing, a roof). Equal priorities go to
## the keyword that comes first, which is the head noun in Spanish/Galician/
## Portuguese ("Relleno de zanjas" is a fill, "Excavación y relleno" a dig).
##
## Only ever a default: an explicit type (a model property, a Project column,
## an inspector edit) always wins over this. See IFCScheduleGenerator._derive().

## One rule per kind of work. `words` are regex fragments matched at a word
## start; `\\b` at the end of one pins it to a whole word ("forja" the ironwork,
## not "forjado" the slab). `batch` is false for discrete pieces placed one
## after another, true for one operation split into several meshes.
const RULES: Array = [
	{"category": "demolition", "priority": 100, "type": "fade_out", "batch": false, "words": [
		"demol", "derrib", "derrub", "dismantl", "desmontaj", "desmontax", "desmontag",
		"levantado de", "picado de",
	]},
	{"category": "site_clearing", "priority": 95, "type": "fade_out", "batch": false, "words": [
		"desbro", "tala\\b", "talas\\b", "talado", "destocon", "desmata", "desarboriz", "rocada",
		"clearing", "grubbing", "tree felling", "tree removal", "felling",
	]},
	{"category": "excavation", "priority": 90, "type": "sink_down", "batch": true, "words": [
		"excav", "escav", "vaciado", "baleirad", "desmonte", "zanja", "zanxa", "vala\\b", "valas\\b",
		"terra vexetal", "tierra vegetal", "terra vegetal", "capa vegetal", "decapad", "decapax",
		"topsoil", "trench", "dig\\b", "digging", "dredg", "dragad", "movimiento de tierras",
		"movemento de terras", "earthwork", "earth work",
	]},
	{"category": "earth_fill", "priority": 90, "type": "fill_up", "batch": true, "words": [
		"relleno", "recheo", "aterro", "terraplen", "backfill", "embankment", "compactac",
		"subbase", "sub base", "zahorra", "base granular", "explanada",
	]},
	{"category": "concrete_pour", "priority": 80, "type": "fill_up", "batch": true, "words": [
		"hormig", "formig", "concret", "betao", "betonag", "beton\\b", "pour", "vertido de",
		"vertedura", "lean mix", "screed", "recrecido", "mortero autonivel",
	]},
	{"category": "rebar", "priority": 75, "type": "fade_in", "batch": false, "words": [
		"armadura", "armado de", "armado da", "armado do", "ferralla", "ferrallado", "rebar",
		"reinforcement", "reinforcing", "steel fixing", "malla electrosoldada",
	]},
	{"category": "scaffolding", "priority": 70, "type": "build_up", "batch": true, "words": [
		"andami", "andaim", "scaffold", "encofrad", "cofrage", "cofragem", "formwork",
		"cimbra", "apuntalam", "shoring", "falsework",
	]},
	{"category": "precast", "priority": 62, "type": "drop_in", "batch": false, "words": [
		"prefabric", "precast", "pre cast", "pre fabricad", "modular",
	]},
	{"category": "steel_timber_frame", "priority": 60, "type": "drop_in", "batch": false, "words": [
		"estructura metalica", "estrutura metalica", "metalic", "acero", "aceiro", "aco\\b",
		"steel", "perfil", "cercha", "celosia", "truss", "pares\\b", "cabrio", "correa", "purlin",
		"rafter", "madera", "madeira", "timber", "castineir", "carballo", "estrutura de cuberta",
		"estructura de cubierta", "estrutura de cobertura", "roof structure", "solaina",
	]},
	{"category": "concrete_element", "priority": 58, "type": "fill_up", "batch": true, "words": [
		"forjado", "forxado", "losa\\b", "losas\\b", "solera", "soleira", "zapata",
		"encepado", "riostra", "pantalla", "pilote", "pilotaje", "laje\\b", "lajes\\b", "sapata",
		"slab", "footing", "pile cap", "piles\\b", "raft",
	]},
	{"category": "stone_pieces", "priority": 55, "type": "drop_in", "batch": false, "words": [
		"mensula", "cornisa", "cornixa", "cornija", "esquinal", "esquinais", "silleria",
		"cantaria", "canteria", "recercad", "dintel", "lintel", "umbral", "imposta", "balaustr",
		"gargol", "escudo", "cruceiro", "horreo", "emparrado", "pergola", "bufarda", "buhardilla",
		"dormer", "corbel", "cornice", "quoin", "ashlar",
	]},
	{"category": "curtain_wall", "priority": 52, "type": "fade_in", "batch": false, "words": [
		"muro cortina", "fachada ventilada", "curtain wall", "cladding panel",
	]},
	{"category": "masonry", "priority": 50, "type": "build_up", "batch": true, "words": [
		"mamposter", "manposter", "alvenaria", "fabrica de", "fabrica\\b", "ladrillo", "ladrillos",
		"tijolo", "bloque", "bloco", "tabique", "tabiqueria", "muro", "muros", "parede", "cerramento",
		"cerramiento", "cierre", "cerre\\b", "peto\\b", "zocalo", "chimenea", "chemine", "chamine",
		"patin\\b", "escalinata", "brick", "block", "masonry", "stonework", "wall\\b", "walls\\b",
		"chimney",
	]},
	{"category": "roofing", "priority": 45, "type": "fade_in", "batch": true, "words": [
		"cubricion", "cubrimiento", "tejado", "teja\\b", "tejas\\b", "tella", "pizarra", "lousa\\b",
		"cubierta", "cuberta", "cobertura", "telhado", "roofing", "roof\\b", "slate", "tiling roof",
		"roof tiles",
	]},
	{"category": "ironwork_gates", "priority": 42, "type": "drop_in", "batch": false, "words": [
		"forja\\b", "forxa\\b", "cerrajer", "serralhar", "barandill", "barandal", "varand", "rejeria",
		"reja\\b", "rejas\\b", "balcon", "balcons\\b", "valla", "vallado", "cancela", "porton",
		"gate\\b", "gates\\b", "fence", "fencing", "railing", "balustrade", "guardrail",
		"mobiliario", "bancos\\b", "furniture",
	]},
	{"category": "openings", "priority": 40, "type": "fade_in", "batch": false, "words": [
		"carpinter", "ventan", "fiestra", "xanela", "janela", "puerta",
		"porta\\b", "portas\\b", "acristal", "vidrio", "vidro", "cristal", "glazing", "window",
		"door", "joinery",
	]},
	{"category": "lighting", "priority": 38, "type": "drop_in", "batch": false, "words": [
		"alumbrado", "alumeado", "iluminac", "luminaria", "farola", "lighting", "street light",
		"lamp post",
	]},
	{"category": "finishes", "priority": 35, "type": "fade_in", "batch": true, "words": [
		"pavimento", "pavimentac", "solado", "lousado", "enlosado", "alicatad", "revest",
		"revoco", "enfoscad", "enlucid", "pintura", "aislam", "illam", "isolam", "impermeab",
		"falso techo", "teito", "plaster", "render\\b", "paint", "flooring", "floor finish",
		"tiling", "cladding", "insulation", "waterproof", "terraza", "acabad",
	]},
	{"category": "services", "priority": 35, "type": "fade_in", "batch": true, "words": [
		"instalac", "fontaner", "electric", "saneam", "tuberia", "tubaxe", "conduct",
		"climatiz", "ventilac", "calefacc", "plumbing", "hvac", "pipe", "duct", "cabling", "drainage",
		"drenaje", "drenaxe",
	]},
	{"category": "paving", "priority": 32, "type": "fill_up", "batch": true, "words": [
		"firme\\b", "aglomerado", "asfalt", "bitumin", "rodadura", "asphalt", "paving",
	]},
	{"category": "landscaping", "priority": 30, "type": "scale_up", "batch": false, "words": [
		"jardin", "xardin", "ajardin", "plantac", "planta de arbo", "arbolado nuevo", "cesped",
		"herba", "landscap", "planting", "trees\\b", "hedge", "seto",
	]},
	{"category": "concrete_columns", "priority": 28, "type": "fill_up", "batch": true, "words": [
		"pilar", "piar\\b", "piares", "columna", "soporte", "cimentac", "cimiento", "foundation",
		"viga", "vigas", "beam", "column", "escalera", "stair", "rampa", "ramp\\b",
	]},
]

static var _compiled: Array = []


## {"type", "batch", "category", "keyword"} for the best rule matching any of
## `texts` (joined), or {} when nothing matches. Never errors on odd input.
static func classify(texts: Variant) -> Dictionary:
	var text := normalize(_join(texts))
	if text.is_empty():
		return {}
	var best: Dictionary = {}
	var best_priority := -1
	var best_pos := 1 << 30
	for rule in _rules():
		var m: RegExMatch = rule.regex.search(text)
		if m == null:
			continue
		var pos := m.get_start()
		if rule.priority > best_priority or (rule.priority == best_priority and pos < best_pos):
			best_priority = rule.priority
			best_pos = pos
			best = {
				"type": rule.type,
				"batch": rule.batch,
				"category": rule.category,
				"keyword": m.get_string().strip_edges(),
			}
	return best


## The inferred type alone, or `fallback` when the name says nothing usable.
static func infer_type(texts: Variant, fallback: String = "") -> String:
	var r := classify(texts)
	return str(r.type) if not r.is_empty() else fallback


## The text an action is classified by: its id plus the human label written into
## its comment by IFCScheduleGenerator ("<label> -- N part(s), dates"). The id
## alone is often a bare code, the label alone is sometimes missing.
static func action_text(action: Dictionary) -> String:
	var parts: Array = []
	for key in ["id", "target_prefix", "commander_prefix", "name"]:
		if action.has(key):
			parts.append(str(action[key]))
	var comment := str(action.get("comment", ""))
	if not comment.is_empty():
		parts.append(comment.get_slice(" -- ", 0))
	return " ".join(parts)


## Lower case, accents stripped, CamelCase split, every non-letter a space.
## "C10_PilaresPB" -> "c pilares pb", "Formigón de limpeza" -> "formigon de limpeza".
static func normalize(text: String) -> String:
	var camel := RegEx.new()
	camel.compile("([a-zà-ÿ])([A-ZÀ-Þ])")
	var s := camel.sub(text, "$1 $2", true).to_lower()
	var out := ""
	for ch in s:
		var mapped: String = _FOLD.get(ch, ch)
		var code := mapped.unicode_at(0)
		var is_letter := (code >= 97 and code <= 122)
		out += mapped if is_letter else " "
	var spaces := RegEx.new()
	spaces.compile(" +")
	return spaces.sub(out, " ", true).strip_edges()


const _FOLD := {
	"á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a", "å": "a",
	"é": "e", "è": "e", "ê": "e", "ë": "e",
	"í": "i", "ì": "i", "î": "i", "ï": "i",
	"ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u",
	"ñ": "n", "ç": "c", "ý": "y", "ÿ": "y",
}


static func _join(texts: Variant) -> String:
	if texts is Array or texts is PackedStringArray:
		var out: Array = []
		for t in texts:
			if t != null:
				out.append(str(t))
		return " ".join(out)
	return "" if texts == null else str(texts)


static func _rules() -> Array:
	if not _compiled.is_empty():
		return _compiled
	for rule in RULES:
		var re := RegEx.new()
		re.compile("\\b(?:%s)" % "|".join(rule.words))
		_compiled.append({
			"regex": re, "priority": rule.priority, "type": rule.type,
			"batch": rule.batch, "category": rule.category,
		})
	return _compiled
