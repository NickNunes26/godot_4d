## Headless test for TaskClassifier: activity names -> animation type.
##
## Run (after the editor has scanned the project once so class_names resolve):
##   godot --headless --path . --editor --quit
##   godot --headless --path . --script res://addons/construction_4d_tool/tests/test_task_classifier.gd
extends SceneTree

var _fails := 0

func _check(label: String, got, want) -> void:
	var ok = got == want
	if not ok:
		_fails += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", label, "" if ok else "   got=%s want=%s" % [str(got), str(want)]])

func _type(text) -> String:
	return TaskClassifier.infer_type(text, "?")

func _init() -> void:
	print("=== normalisation")
	_check("codes split on _ and CamelCase", TaskClassifier.normalize("C10_PilaresPB"), "c pilares pb")
	_check("accents and case folded", TaskClassifier.normalize("Formigón de LIMPEZA"), "formigon de limpeza")
	_check("punctuation and digits are spaces", TaskClassifier.normalize("Zapatas (Z-1..Z-12), 2ª fase"), "zapatas z z fase")
	_check("empty text matches nothing", TaskClassifier.classify(""), {})
	_check("null is safe", TaskClassifier.classify(null), {})

	# Every activity of the Galician test model (code + label), as the IFC
	# generator and the dock's Auto types button see them.
	print("=== a real Galician schedule")
	var galicia := {
		"C01_Desbroce Desbroce e retirada de arboredo": "fade_out",
		"C02_TerraVexetal Retirada de terra vexetal": "sink_down",
		"C03_Escavacion Escavación ata cota de cimentación": "sink_down",
		"C04_Limpeza Formigón de limpeza": "fill_up",
		"C05_Armaduras Armado de zapatas": "fade_in",
		"C06_Zapatas Zapatas de formigón armado": "fill_up",
		"C07_Riostras Vigas riostras": "fill_up",
		"C08_Zocalo Zócalo de mampostería granítica": "build_up",
		"C09_Soleira Soleira e forxado sanitario": "fill_up",
		"C10_PilaresPB Piares de planta baixa": "fill_up",
		"C11_ForxadoP1 Forxado de planta primeira": "fill_up",
		"C15_ForxadoCuberta Forxado de cuberta e zuncho": "fill_up",
		"C16_MamposteriaPB Mampostería de granito, planta baixa": "build_up",
		"C17_EsquinaisPB Esquinais de sillería, planta baixa": "drop_in",
		"C22_MensulasGaleria Ménsulas de granito da galería": "drop_in",
		"C23_Recercados Recercados e cantería de fachada": "drop_in",
		"C24_CornixaP1 Cornixa de planta primeira": "drop_in",
		"C27_EstruturaCuberta Estrutura de cuberta en castiñeiro": "drop_in",
		"C28_Pares Pares e cabrios": "drop_in",
		"C29_Lousa Cubrición de lousa": "fade_in",
		"C30_Bufardas Bufardas": "drop_in",
		"C31_Chemineas Chemineas de granito": "build_up",
		"C32_CarpinteriaGaleria Carpintería da galería": "fade_in",
		"C33_CarpinteriaExterior Carpintería exterior e portas": "fade_in",
		"C34_Acristalamento Acristalamento": "fade_in",
		"C35_Escudo Escudo heráldico": "drop_in",
		"C36_Balcons Balcóns e forxa": "drop_in",
		"C37_Solaina Solaina": "drop_in",
		"C38_Patin Patín de acceso": "build_up",
		"C39_Terraza Terraza e lousado exterior": "fade_in",
		"C40_Emparrado Emparrado": "drop_in",
		"C41_Cerre Muro de cerre da parcela": "build_up",
		"C42_Cancela Cancela e piares de entrada": "drop_in",
		"C43_Horreo Hórreo": "drop_in",
		"C44_Cruceiro Cruceiro": "drop_in",
		"C45_Xardineria Xardinería": "scale_up",
		"C46_Alumeado Alumeado exterior": "drop_in",
		"Z99_Andamio Andamio de fachada": "build_up",
	}
	for text in galicia:
		_check(text, _type(text), galicia[text])

	print("=== Spanish, Portuguese, English")
	var other := {
		"Hormigonado de losa de planta 2": "fill_up",
		"Hormigonar muros de sótano": "fill_up",
		"Excavación de zanjas": "sink_down",
		"Relleno de zanjas": "fill_up",          # head noun first: a fill, not a dig
		"Excavación y relleno": "sink_down",
		"Demolición de edificio existente": "fade_out",
		"Desmontaje de andamio": "fade_out",     # dismantling outranks the scaffold word
		"Encofrado y hormigonado de pilares": "fill_up",
		"Montaje de estructura metálica": "drop_in",
		"Pilares metálicos HEB-200": "drop_in",  # steel outranks the column noun
		"Forjado de vigueta prefabricada": "drop_in",
		"Fábrica de ladrillo cara vista": "build_up",
		"Tabiquería interior": "build_up",
		"Muro cortina": "fade_in",
		"Tejado de teja cerámica": "fade_in",
		"Colocación de ventanas": "fade_in",
		"Instalaciones de fontanería": "fade_in",
		"Firme de aglomerado asfáltico": "fill_up",
		"Plantación de árboles": "scale_up",
		"Tala de árboles": "fade_out",
		"Betonagem de sapatas": "fill_up",
		"Alvenaria de tijolo": "build_up",
		"Escavação": "sink_down",
		"Pour ground floor slab": "fill_up",
		"Topsoil strip": "sink_down",
		"Brickwork to first floor": "build_up",
		"Erect steel frame": "drop_in",
		"Install windows": "fade_in",
		"Slab formwork": "build_up",             # a formwork activity animates its forms
		"Scaffolding": "build_up",
	}
	for text in other:
		_check(text, _type(text), other[text])

	print("=== words that must not match")
	_check("forja (ironwork) is not forjado (slab)", _type("Forjado sanitario"), "fill_up")
	_check("forxa alone is ironwork", _type("Forxa"), "drop_in")
	_check("desmonte (cut) is not desmontaje (dismantling)", _type("Desmonte de terreno"), "sink_down")
	_check("hormigón armado is not rebar", _type("Muros de hormigón armado"), "fill_up")
	_check("unknown activity", _type("Reunión de coordinación"), "?")
	_check("bare code with nothing to read", _type("C99_X"), "?")

	print("=== result details")
	var r := TaskClassifier.classify(["C10_PilaresPB", "Piares de planta baixa"])
	_check("type", r.type, "fill_up")
	_check("batch: one pour", r.batch, true)
	_check("category", r.category, "concrete_columns")
	_check("keyword reported", r.keyword, "pilar")
	_check("pieces are staggered", TaskClassifier.classify("Esquinais").batch, false)
	_check("every inferred type is a real type", TaskClassifier.RULES.all(func(rule): return rule.type in AnimationApplier.TYPES), true)

	print("=== action_text")
	_check("id + label from the comment",
		TaskClassifier.action_text({"id": "C04_Limpeza", "target_prefix": "C04_Limpeza", "comment": "Formigón de limpeza -- 6 part(s), 2027-04-04..2027-04-09"}),
		"C04_Limpeza C04_Limpeza Formigón de limpeza")
	_check("no comment", TaskClassifier.action_text({"commander_prefix": "Col"}), "Col")

	print(("ALL CHECKS PASSED" if _fails == 0 else "%d CHECK(S) FAILED" % _fails))
	quit(_fails)
