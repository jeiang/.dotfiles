# Renders added.png (each built ligature: plain mononoki, built, Fira Code) and
# skipped.png (Fira Code ligatures not built: plain mononoki, Fira Code).
# usage: python3 preview.py LIGATE_PY LIGATURIZER_DIR MONONOKI_DIR BUILT_DIR FIRA_DIR OUT_DIR
import runpy
import subprocess
import sys
import tempfile

ligate_py, ligaturizer, mononoki, built, fira, out = sys.argv[1:]
LIGATURES = runpy.run_path(ligate_py)["LIGATURES"]
char_dict = runpy.run_path(f"{ligaturizer}/char_dict.py")["char_dict"]
ligatures = runpy.run_path(f"{ligaturizer}/ligatures.py")["ligatures"]

STYLES = ["Regular", "Bold", "Italic", "BoldItalic"]
SAMPLES = ["if (a != b && c >= d)", "xs.map(x => x == 1)", "a -> b <- c <-> d", "p <=> q, a === b"]
tmp = tempfile.mkdtemp()
count = 0


def view(font, lines, size, features=""):
    global count
    count += 1
    path = f"{tmp}/{count}.png"
    with open(f"{tmp}/{count}.txt", "w") as text:
        text.write("\n".join(lines))
    subprocess.run(
        [
            "hb-view", f"--font-file={font}", f"--font-size={size}", "--margin=12 40",
            "--background=1F1F28", "--foreground=DCD7BA", f"--features={features}",
            f"--text-file={tmp}/{count}.txt", "-o", path,
        ],
        check=True,
    )
    return path


def magick(*args):
    global count
    count += 1
    path = f"{tmp}/{count}.png"
    subprocess.run(["magick", *args, "-background", "#1F1F28", path], check=True)
    return path


rows = list(LIGATURES) + [""] + SAMPLES
blocks = []
for style in STYLES:
    columns = [
        view(f"{mononoki}/mononoki-{style}.ttf", [f"{style}: plain", *rows], 36),
        view(f"{built}/mononoki-liga-{style}.ttf", ["built from mononoki", *rows], 36),
        view(f"{fira}/fira-{style}.ttf", ["Fira Code", *rows], 36),
    ]
    blocks.append(magick(*columns, "+append"))
subprocess.run(["magick", *blocks, "-background", "#1F1F28", "-append", f"{out}/added.png"], check=True)

skipped = []
for lig in ligatures:
    if lig["firacode_ligature_name"]:
        chars = "".join(char_dict[c] for c in lig["chars"])
        if chars not in LIGATURES:
            skipped.append(chars)
groups = []
for i in range(0, len(skipped), 44):
    chunk = skipped[i:i + 44]
    groups.append(magick(
        view(f"{mononoki}/mononoki-Regular.ttf", ["plain", *chunk], 30),
        view(f"{fira}/fira-Regular.ttf", ["Fira", *chunk], 30),
        "+append",
    ))
subprocess.run(["magick", *groups, "-background", "#1F1F28", "+append", f"{out}/skipped.png"], check=True)
