# Adds coding ligatures to a mononoki TTF, built only from mononoki's own glyphs.
# usage: python3 ligate.py IN.ttf OUT.ttf
import sys

import pathops
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.recordingPen import RecordingPen, replayRecording
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables import otTables

NAMES = {
    "-": "hyphen", "=": "equal", "<": "less", ">": "greater", "!": "exclam",
    ".": "period", ":": "colon", "|": "bar",
}

# ("place", glyph, cell) puts a glyph in its own cell, unchanged;
# ("bars", glyph, cell, left, right) extends each bar of a glyph until it meets the glyph placed in cell left or right;
# ("stretch", glyph) widens a glyph through its thinnest vertical slice to span every cell;
# ("center", glyph) places a glyph unchanged in the middle of the cells;
# ("repeat", glyph) sets one copy per character at the dot spacing of mononoki's ellipsis, centered.
LIGATURES = {
    "<=>": [("place", "less", 0), ("place", "greater", 2), ("bars", "equal", 1, 0, 2)],
    "<->": [("place", "less", 0), ("place", "greater", 2), ("bars", "hyphen", 1, 0, 2)],
    "===": [("stretch", "equal"), ("stretch", "hyphen")],
    "...": [("repeat", "period")],
    "->": [("place", "greater", 1), ("bars", "hyphen", 0, None, 1)],
    "<-": [("place", "less", 0), ("bars", "hyphen", 1, 0, None)],
    "=>": [("place", "greater", 1), ("bars", "equal", 0, None, 1)],
    "|-": [("place", "bar", 0), ("bars", "hyphen", 1, 0, None)],
    "==": [("stretch", "equal")],
    "!=": [("stretch", "equal"), ("center", "notequal")],
    ">=": [("center", "greaterequal")],
    "<=": [("center", "lessequal")],
    "..": [("repeat", "period")],
    "::": [("repeat", "colon")],
}

# Contexts that keep a sequence plain, besides a repeat of its first or last character.
IGNORE = {
    "==": ["equal' equal greater", "less equal' equal", "exclam equal' equal"],
    ">=": ["greater' equal greater"],
    "<=": ["less' equal less"],
}

SPACER = "LIG"


def liga_name(chars):
    return "_".join(NAMES[c] for c in chars) + ".liga"


def recording(glyphs, name):
    pen = RecordingPen()
    glyphs[name].draw(pen)
    return pen.value


def moved(value, f):
    return [(op, tuple(None if p is None else f(p) for p in args)) for op, args in value]


def path_of(value):
    path = pathops.Path()
    replayRecording(value, path.getPen())
    return path


def coverage(path, x):
    strip = path_of([
        ("moveTo", ((x, -4096),)),
        ("lineTo", ((x + 1, -4096),)),
        ("lineTo", ((x + 1, 4096),)),
        ("lineTo", ((x, 4096),)),
        ("closePath", ()),
    ])
    return abs(pathops.op(path, strip, pathops.PathOp.INTERSECTION).area)


def thinnest_x(value):
    path = path_of(value)
    x0, _, x1, _ = path.bounds
    mid = (x0 + x1) / 2
    xs = [x0 + (x1 - x0) * i / 40 for i in range(8, 33)]
    return min(xs, key=lambda x: (round(coverage(path, x) / 4), abs(x - mid)))


def contours(value):
    out, current = [], []
    for op, args in value:
        current.append((op, args))
        if op in ("closePath", "endPath"):
            out.append(current)
            current = []
    return out


def meet(target, y0, y1, x, rightward):
    """Middle of the nearest part of target that the band y0..y1 crosses, right or left of x."""
    band = path_of([
        ("moveTo", ((-4096, y0),)),
        ("lineTo", ((4096, y0),)),
        ("lineTo", ((4096, y1),)),
        ("lineTo", ((-4096, y1),)),
        ("closePath", ()),
    ])
    pen = RecordingPen()
    pathops.op(target, band, pathops.PathOp.INTERSECTION).draw(pen)
    pieces = [path_of(c).bounds for c in contours(pen.value)]
    if rightward:
        piece = min((b for b in pieces if b[0] > x), key=lambda b: b[0])
    else:
        piece = max((b for b in pieces if b[2] < x), key=lambda b: b[2])
    return (piece[0] + piece[2]) / 2

def rhythm(glyphs):
    """Dot pitch over dot width in mononoki's own ellipsis."""
    dots = sorted(path_of(c).bounds for c in contours(recording(glyphs, "ellipsis")))
    return (dots[1][0] - dots[0][0]) / (dots[0][2] - dots[0][0])


def build(glyphs, width, chars, recipe):
    span = (len(chars) - 1) * width
    path = pathops.Path()
    placed = {}
    for step in recipe:
        how, value = step[0], recording(glyphs, step[1])
        if how == "place":
            value = moved(value, lambda p, dx=step[2] * width: (p[0] + dx, p[1]))
            placed[step[2]] = path_of(value)
        elif how == "bars":
            _, _, cell, left, right = step
            bars = []
            for bar in contours(moved(value, lambda p, dx=cell * width: (p[0] + dx, p[1]))):
                x0, y0, x1, y1 = path_of(bar).bounds
                mid = (x0 + x1) / 2
                dl = 0 if left is None else meet(placed[left], y0, y1, mid, False) - x0
                dr = 0 if right is None else meet(placed[right], y0, y1, mid, True) - x1
                bars += moved(bar, lambda p, m=mid, dl=dl, dr=dr: (p[0] + (dr if p[0] > m else dl), p[1]))
            value = bars
        elif how == "stretch":
            at = thinnest_x(value)
            value = moved(value, lambda p, at=at: (p[0] + span if p[0] > at else p[0], p[1]))
        else:
            if how == "repeat":
                x0, _, x1, _ = path_of(value).bounds
                pitch = rhythm(glyphs) * (x1 - x0)
                value = [s for i in range(len(chars)) for s in moved(value, lambda p, dx=i * pitch: (p[0] + dx, p[1]))]
            x0, _, x1, _ = path_of(value).bounds
            dx = (span + width) / 2 - (x0 + x1) / 2
            value = moved(value, lambda p, dx=dx: (p[0] + dx, p[1]))
        # The ligature glyph sits in the last cell and draws back over the spacers before it.
        replayRecording(moved(value, lambda p: (p[0] - span, p[1])), path.getPen())
    path.simplify(clockwise=True)
    pen = TTGlyphPen(None)
    path.draw(Cu2QuPen(pen, max_err=1))
    return pen.glyph()


def lookup(chars):
    names = [NAMES[c] for c in chars]
    first, last, n = names[0], names[-1], len(names)
    rules = [
        f"ignore sub {first} {first}' {' '.join(names[1:])};",
        f"ignore sub {first}' {' '.join(names[1:])} {last};",
    ]
    rules += [f"ignore sub {ctx};" for ctx in IGNORE.get(chars, [])]
    rules.append(f"sub {' '.join([SPACER] * (n - 1))} {last}' by {liga_name(chars)};")
    for i in range(n - 2, 0, -1):
        rules.append(f"sub {' '.join([SPACER] * i)} {names[i]}' {' '.join(names[i + 1:])} by {SPACER};")
    rules.append(f"sub {first}' {' '.join(names[1:])} by {SPACER};")
    tag = liga_name(chars).replace(".", "_")
    return f"lookup {tag} {{\n  " + "\n  ".join(rules) + f"\n}} {tag};\n", tag


def shift_nested(obj, base):
    # Contextual rules name the lookups they apply by index, which moves when appended.
    if isinstance(obj, otTables.SubstLookupRecord):
        obj.LookupListIndex += base
    elif isinstance(obj, list):
        for item in obj:
            shift_nested(item, base)
    elif isinstance(obj, otTables.BaseTable):
        for value in vars(obj).values():
            shift_nested(value, base)

def add_calt(font):
    # feaLib replaces GSUB, so the new lookups are appended to mononoki's own table afterwards.
    old = font["GSUB"]
    bodies, tags = zip(*(lookup(c) for c in sorted(LIGATURES, key=len, reverse=True)), strict=True)
    fea = "languagesystem DFLT dflt;\n" + "".join(bodies)
    fea += "feature calt {\n" + "".join(f"  lookup {t};\n" for t in tags) + "} calt;\n"
    addOpenTypeFeaturesFromString(font, fea, tables=["GSUB"])
    new = font["GSUB"].table
    table = old.table
    base = len(table.LookupList.Lookup)
    shift_nested(new.LookupList.Lookup, base)
    table.LookupList.Lookup += new.LookupList.Lookup
    table.LookupList.LookupCount = len(table.LookupList.Lookup)
    feature = otTables.Feature()
    feature.FeatureParams = None
    feature.LookupListIndex = sorted({base + i for r in new.FeatureList.FeatureRecord for i in r.Feature.LookupListIndex})
    feature.LookupCount = len(feature.LookupListIndex)
    record = otTables.FeatureRecord()
    record.FeatureTag = "calt"
    record.Feature = feature
    index = len(table.FeatureList.FeatureRecord)
    table.FeatureList.FeatureRecord.append(record)
    table.FeatureList.FeatureCount = len(table.FeatureList.FeatureRecord)
    for script in table.ScriptList.ScriptRecord:
        for langsys in [script.Script.DefaultLangSys] + [r.LangSys for r in script.Script.LangSysRecord]:
            if langsys is not None:
                langsys.FeatureIndex.append(index)
                langsys.FeatureCount = len(langsys.FeatureIndex)
    font["GSUB"] = old


def rename(font):
    for record in font["name"].names:
        text = record.toUnicode()
        if record.nameID == 6:
            record.string = text.replace("mononoki", "MononokiLiga")
        elif record.nameID in (1, 3, 4, 16, 18):
            record.string = text.replace("mononoki", "Mononoki Liga")


def main(source, target):
    font = TTFont(source)
    glyphs = font.getGlyphSet()
    width = font["hmtx"]["space"][0]
    assert SPACER not in glyphs
    new = {SPACER: TTGlyphPen(None).glyph()}
    for chars, recipe in LIGATURES.items():
        new[liga_name(chars)] = build(glyphs, width, chars, recipe)
    font.setGlyphOrder(font.getGlyphOrder() + list(new))
    for name, glyph in new.items():
        font["glyf"][name] = glyph
        glyph.recalcBounds(font["glyf"])
        font["hmtx"][name] = (width, getattr(glyph, "xMin", 0))
    add_calt(font)
    rename(font)
    font.save(target)


if __name__ == "__main__":
    main(*sys.argv[1:])
