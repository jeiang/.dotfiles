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

NAMES = {"-": "hyphen", "=": "equal", "<": "less", ">": "greater", "!": "exclam"}

# "stretch" widens a glyph through its thinnest vertical slice to span every cell;
# "center" places a glyph unchanged in the middle of the cells.
LIGATURES = {
    "<=>": [("stretch", "arrowdblboth")],
    "<->": [("stretch", "arrowboth")],
    "===": [("stretch", "equivalence")],
    "->": [("stretch", "arrowright")],
    "<-": [("stretch", "arrowleft")],
    "=>": [("stretch", "arrowdblright")],
    "==": [("stretch", "equal")],
    "!=": [("stretch", "equal"), ("center", "notequal")],
    ">=": [("center", "greaterequal")],
    "<=": [("center", "lessequal")],
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


def build(glyphs, width, chars, recipe):
    span = (len(chars) - 1) * width
    path = pathops.Path()
    for how, source in recipe:
        value = recording(glyphs, source)
        if how == "stretch":
            at = thinnest_x(value)
            value = moved(value, lambda p, at=at: (p[0] + span if p[0] > at else p[0], p[1]))
        else:
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
