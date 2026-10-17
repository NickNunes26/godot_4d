# Galicia pazo sample

A 633-element IFC house plus a planning for it, ready to load in the Build4D dock.

- `galicia_model.ifc`: house and site. Import this first.
- `galicia_medios_auxiliares.ifc`: scaffold (`Z99_Andamio`), phase "Medios auxiliares". Import second; it lands as an extra container by georeference.
- `galicia_model.xml`: the same planning as an MS Project XML (import/export).
- `construction_steps.json`: the schedule (47 actions), using `Pset_Construcion4D/TipoAnimacion` as the type property.
