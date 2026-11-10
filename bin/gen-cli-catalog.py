"""Regenerate cli/saddb/catalog.json and cli/saddb/scoring.py from the web app's sources (run via bin/sadb catalog)."""
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from app.catalog import ENGINES, load_scenarios  # noqa: E402

keys = ["slug", "engine", "title", "difficulty", "minutes", "order", "tags", "summary", "description", "hints", "solution"]
cat = {"engines": ENGINES, "scenarios": [{k: s.get(k) for k in keys} for s in load_scenarios().values()]}
out = ROOT / "cli" / "saddb" / "catalog.json"
new = json.dumps(cat, indent=1, ensure_ascii=False) + "\n"
changed = not out.exists() or out.read_text() != new
out.write_text(new)
src = (ROOT / "app" / "scoring.py").read_text()
dst = ROOT / "cli" / "saddb" / "scoring.py"
hdr = "# GENERATED from app/scoring.py by bin/sadb catalog. Do not edit.\n"
changed |= not dst.exists() or dst.read_text() != hdr + src
dst.write_text(hdr + src)
print(f"{'updated' if changed else 'unchanged'}: {len(cat['scenarios'])} scenarios")
sys.exit(1 if changed and "--check" in sys.argv else 0)
