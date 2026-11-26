"""Native menu selector for Hyprland keyboard layouts."""

from collections import Counter
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(os.environ.get("QUATTRO_PATH") or Path(__file__).resolve().parents[2])
NON_LATIN = set(
  "af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua".split()
)
NON_LATIN_US_VARIANTS = {"chr", "rus"}


def run(args, **kwargs):
  return subprocess.run(args, check=True, text=True, capture_output=True, **kwargs).stdout.strip()


def read(path):
  return path.read_text() if path.exists() else ""


def atomic_write(path, text):
  # Follow a user's config symlink rather than replacing the link itself.
  path = path.resolve()
  if read(path) == text:
    return False
  path.parent.mkdir(parents=True, exist_ok=True)
  mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
  fd, temporary = tempfile.mkstemp(prefix=".quattro-input-", dir=path.parent)
  try:
    with os.fdopen(fd, "w") as file:
      file.write(text)
    os.chmod(temporary, mode)
    os.replace(temporary, path)
  finally:
    if os.path.exists(temporary):
      os.unlink(temporary)
  return True


def _read_keyboard_layouts_file():
  layouts_file = ROOT / "default/input-methods/keyboard-layouts.sh"
  text = layouts_file.read_text(encoding="utf-8")
  marker = "QUATTRO_KEYBOARD_LAYOUTS=$'"
  start = text.find(marker)
  if start != -1:
    end = text.rfind("'")
    if end > start + len(marker):
      return text[start + len(marker) : end]
  return run([
    "bash",
    "-c",
    'source "$1"; printf "%s\\n" "$QUATTRO_KEYBOARD_LAYOUTS"',
    "bash",
    str(layouts_file),
  ])


def keyboard_catalog():
  # Read the shared keyboard layout list and convert console keymaps through
  # systemd's mapping, just as localectl does during install.
  choices = _read_keyboard_layouts_file()
  mappings = {}
  kbd_map = Path("/usr/share/systemd/kbd-model-map")
  if kbd_map.exists():
    for line in kbd_map.read_text().splitlines():
      fields = line.split()
      if not fields or fields[0].startswith("#"):
        continue
      layout = fields[1].split(",")[0]
      variant = fields[3].split(",")[0]
      mappings.setdefault(fields[0], layout + (":" + variant if variant != "-" else ""))
  # Console keymap names that systemd's table lacks, mapped to XKB layout:variant.
  mappings.update({
    "bg-cp1251": "bg:phonetic",
    "colemak": "us:colemak",
    "cz": "cz:qwerty",
    "kyrgyz": "kg",
    "de_CH-latin1": "ch",
    "no-latin1": "no",
  })
  catalog = {}
  for choice in choices.splitlines():
    if not choice.strip():
      continue
    label, keymap, *input_settings = choice.split("|")
    layout = input_settings[1] if len(input_settings) > 1 else mappings.get(keymap, keymap)
    catalog.setdefault(layout, label)
  return catalog


def keyboard_selection():
  batch = run(["hyprctl", "--batch", "-j", "getoption input:kb_layout;getoption input:kb_variant"])
  decoder = json.JSONDecoder()
  parsed = []
  idx = 0
  length = len(batch)
  while idx < length:
    while idx < length and batch[idx].isspace():
      idx += 1
    if idx >= length:
      break
    obj, idx = decoder.raw_decode(batch, idx)
    parsed.append(obj)
  raw_layouts = parsed[0]["str"] if len(parsed) > 0 else ""
  raw_variants = parsed[1]["str"] if len(parsed) > 1 else ""
  layouts = [item.strip() for item in raw_layouts.split(",") if item.strip()]
  variants = [item.strip() for item in raw_variants.split(",")]
  if not layouts:
    return ["us"]
  return [
    layout + (":" + variants[index] if index < len(variants) and variants[index] else "")
    for index, layout in enumerate(layouts)
  ]


def picker_rows(catalog, selected):
  # Current entries stay first, in switching order, followed by the catalog.
  keys = list(dict.fromkeys(selected + sorted(catalog, key=lambda key: catalog[key])))
  labels = {key: catalog.get(key, key) for key in keys}
  counts = Counter(labels.values())
  rows = {
    key: "\t" + labels[key] + (f" ({key})" if counts[labels[key]] > 1 else "")
    for key in keys
  }
  return rows


def choose(title, catalog, selected, kind):
  catalog = {**catalog, **{key: catalog.get(key, key) for key in selected}}
  rows = picker_rows(catalog, selected)
  args = ["quattro-menu-select", title] + list(rows.values())
  on_change = [
    "/usr/bin/python3",
    "-B",
    str(ROOT / "default/input-methods/typing_setup.py"),
    "apply",
    kind,
    json.dumps({"catalog": catalog}),
  ]
  args += [
    "--",
    "--multiple",
    "--width",
    "620",
    "--maxheight",
    "650",
    "--on-change",
    json.dumps(on_change),
    "--change-key",
    "typing:" + kind,
  ]
  for key in selected:
    args += ["--selected", rows[key][1:]]
  result = subprocess.run(args, text=True, capture_output=True)
  if result.returncode == 1:
    return None
  if result.returncode:
    raise RuntimeError(result.stderr.strip() or "The selection menu could not open")


def keyboard_values(selected):
  if not selected:
    raise ValueError("Select at least one keyboard layout")
  parts = [value.split(":", 1) for value in selected]
  first_layout = parts[0][0]
  first_variant = parts[0][1] if len(parts[0]) > 1 else ""
  # Preserve the Latin-leading rule for desktop keybindings (matches default/hypr/input.lua).
  if first_layout in NON_LATIN or (first_layout == "us" and first_variant in NON_LATIN_US_VARIANTS):
    us_entry = next(
      (
        part
        for part in parts
        if part[0] == "us" and (len(part) == 1 or part[1] not in NON_LATIN_US_VARIANTS)
      ),
      ["us"],
    )
    parts = [us_entry] + [part for part in parts if part != us_entry]
  layouts = ",".join(part[0] for part in parts)
  variants = ",".join(part[1] if len(part) > 1 else "" for part in parts)
  return layouts, variants


def save_keyboard(selected):
  layouts, variants = keyboard_values(selected)
  config_home = Path(os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config"))
  path = config_home / "quattro/keyboard-layouts"
  original = read(path) if path.exists() else None
  previous_errors = run(["hyprctl", "configerrors"])
  try:
    atomic_write(path, f"XKBLAYOUT={layouts}\nXKBVARIANT={variants}\n")
    run(["hyprctl", "reload"])
    errors = run(["hyprctl", "configerrors"])
    if errors and errors != previous_errors:
      raise RuntimeError(errors)
    expected = [
      layout + (":" + variant if variant else "")
      for layout, variant in zip(layouts.split(","), variants.split(","))
    ]
    if keyboard_selection() != expected:
      raise RuntimeError("Your personal keyboard layout override takes precedence over this selection")
  except BaseException:
    if original is None:
      path.resolve().unlink(missing_ok=True)
    else:
      atomic_write(path, original)
    try:
      run(["hyprctl", "reload"])
    except subprocess.CalledProcessError:
      pass
    raise


def configure_keyboard():
  current = keyboard_selection()
  catalog = keyboard_catalog()
  choose("Keyboard Layouts", catalog, current, "keyboard")


def apply_selection(context, values):
  catalog = context["catalog"]
  rows = picker_rows(catalog, [])
  valid = {row[1:]: key for key, row in rows.items()}
  if not isinstance(values, list) or any(
    not isinstance(value, str) or value not in valid for value in values
  ):
    raise ValueError("The menu returned an invalid selection")
  selected = list(dict.fromkeys(valid[value] for value in values))
  save_keyboard(selected)
  selected = keyboard_selection()
  print(json.dumps([rows[key][1:] for key in selected]))


def main():
  applying = len(sys.argv) == 5 and sys.argv[1] == "apply"
  kind = sys.argv[2] if applying else sys.argv[1] if len(sys.argv) == 2 else ""
  if kind != "keyboard":
    raise ValueError("Choose keyboard setup")
  try:
    if applying:
      apply_selection(json.loads(sys.argv[3]), json.loads(sys.argv[4]))
    else:
      configure_keyboard()
  except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
    i18n = subprocess.run(
      ["quattro-i18n", "input.keyboardLayoutsFailed"], text=True, capture_output=True
    )
    title = i18n.stdout.strip() if i18n.returncode == 0 and i18n.stdout.strip() else "Keyboard layouts could not be updated"
    subprocess.run(["quattro-notification-send", title, str(error)], check=False)
    raise SystemExit(1)


if __name__ == "__main__":
  main()
