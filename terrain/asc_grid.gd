@tool
class_name AscGrid
extends RefCounted

## ESRI ASCII grid (.asc): the format the Spanish elevation WCS returns and
## the one most GIS tools export. Also accepts the WCS's multipart MIME
## wrapper: everything before "ncols" and from the next "\n--" boundary on is
## ignored.
##
## Coordinates are whatever the file is in (degrees for the WCS, metres for a
## projected export); this class never interprets them. Row 0 is the north edge.

var ncols: int = 0
var nrows: int = 0
var xll: float = 0.0 ## west edge
var yll: float = 0.0 ## south edge
var cellsize: float = 0.0
var nodata: float = -9999.0
var values := PackedFloat64Array() ## nrows * ncols, row-major from the north-west corner

const _HEADER_KEYS := ["ncols", "nrows", "xllcorner", "yllcorner", "xllcenter", "yllcenter", "cellsize", "nodata_value", "dx", "dy"]

## Parses `text`; returns null (and fills `error` if given a Dictionary) when
## it is not a grid.
static func parse(text: String, error: Dictionary = {}) -> AscGrid:
	var start := text.findn("ncols")
	if start < 0:
		error["message"] = "no 'ncols' header: %s" % text.substr(0, 300).strip_edges()
		return null
	var end := text.find("\n--", start)
	var body := text.substr(start, end - start if end > 0 else -1)
	var lines := body.split("\n")
	var hdr := {}
	var k := 0
	while k < lines.size():
		var parts := lines[k].strip_edges().split(" ", false)
		if parts.size() == 2 and parts[0].to_lower() in _HEADER_KEYS:
			hdr[parts[0].to_lower()] = parts[1].to_float()
			k += 1
		else:
			break
	if not (hdr.has("ncols") and hdr.has("nrows") and (hdr.has("cellsize") or hdr.has("dx"))):
		error["message"] = "incomplete ASC header: %s" % str(hdr)
		return null
	var g := AscGrid.new()
	g.ncols = int(hdr.ncols)
	g.nrows = int(hdr.nrows)
	g.cellsize = hdr.get("cellsize", hdr.get("dx", 0.0))
	g.xll = hdr.xllcorner if hdr.has("xllcorner") else hdr.get("xllcenter", 0.0) - g.cellsize / 2.0
	g.yll = hdr.yllcorner if hdr.has("yllcorner") else hdr.get("yllcenter", 0.0) - g.cellsize / 2.0
	g.nodata = hdr.get("nodata_value", -9999.0)
	var data := "\n".join(lines.slice(k)).replace("\r", " ").replace("\n", " ").replace("\t", " ")
	var nums := data.split_floats(" ", false)
	var count := g.ncols * g.nrows
	if nums.size() < count:
		error["message"] = "ASC body has %d values, header says %d" % [nums.size(), count]
		return null
	g.values = nums.slice(0, count) if nums.size() > count else nums
	return g

## Replaces no-data cells (the declared value, or anything below -1000 m) with
## the median of the valid ones. Returns the number of valid cells; 0 means the
## grid is all no-data (typically: the point is outside the service's area).
func fill_nodata() -> int:
	var valid := PackedFloat64Array()
	var bad := PackedInt32Array()
	for i in values.size():
		var v := values[i]
		if v == nodata or v < -1000.0 or is_nan(v):
			bad.append(i)
		else:
			valid.append(v)
	if valid.is_empty():
		return 0
	if not bad.is_empty():
		valid.sort()
		var med := valid[valid.size() >> 1]
		for i in bad:
			values[i] = med
	return valid.size()

## Bilinear sample at (x, y) in the grid's own coordinates, clamped to the
## edges. Cell values sit at cell centres.
func sample(x: float, y: float) -> float:
	var u := clampf((x - xll) / cellsize - 0.5, 0.0, ncols - 1.001)
	var v := clampf((yll + nrows * cellsize - y) / cellsize - 0.5, 0.0, nrows - 1.001)
	var c0 := int(u)
	var r0 := int(v)
	var fu := u - c0
	var fv := v - r0
	var i := r0 * ncols + c0
	return lerpf(lerpf(values[i], values[i + 1], fu), lerpf(values[i + ncols], values[i + ncols + 1], fu), fv)

## Whether (x, y) falls inside the grid.
func contains(x: float, y: float) -> bool:
	return x >= xll and x <= xll + ncols * cellsize and y >= yll and y <= yll + nrows * cellsize

## Mean of the valid cells, or NAN if there are none. Sea is reported by the
## Spanish service as all exact zeros, which is treated as no data too (a real
## coast returns small non-zero heights and passes).
func land_mean() -> float:
	var total := 0.0
	var count := 0
	var all_zero := true
	for v in values:
		if v == nodata or v < -1000.0 or is_nan(v):
			continue
		total += v
		count += 1
		if v != 0.0:
			all_zero = false
	if count == 0 or all_zero:
		return NAN
	return total / count
