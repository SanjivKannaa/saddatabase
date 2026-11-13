"""Scenario catalogue: engines (tracks) and scenario metadata. No side effects, so tools can import it."""
import tomllib
from pathlib import Path

SCENARIOS_DIR = Path(__file__).resolve().parent.parent / "scenarios"
STORIES_DIR = Path(__file__).resolve().parent.parent / "stories"

ENGINES = {
    "postgres": {"name": "PostgreSQL", "version": "17", "color": "#336791",
                 "blurb": "Startup failures, auth layers, slow plans, locks, sequences and connection limits."},
    "mysql": {"name": "MySQL", "version": "8.4", "color": "#00758f",
              "blurb": "Upgrade-broken configs, account and role gotchas, type conversion and metadata locks."},
    "mongo": {"name": "MongoDB", "version": "7.0", "color": "#13aa52",
              "blurb": "YAML configs, ESR indexes, authSource confusion and cleaning up duplicates."},
    "redis": {"name": "Redis", "version": "8", "color": "#d82c20",
              "blurb": "AOF repair, eviction policies and finding the key that eats memory."},
}


def load_scenarios() -> dict[str, dict]:
    out = {}
    for f in SCENARIOS_DIR.glob("*/scenario.toml"):
        meta = tomllib.loads(f.read_text())
        meta["slug"] = f.parent.name
        if meta.get("engine") in ENGINES:
            out[meta["slug"]] = meta
    order = list(ENGINES)
    return dict(sorted(out.items(), key=lambda kv: (order.index(kv[1]["engine"]), kv[1].get("order", 99))))


def load_stories(scenarios: dict[str, dict]) -> dict[str, dict]:
    """stories/<id>/story.toml. Chapters are scenarios; a chapter that isn't built yet is listed as coming soon."""
    out = {}
    for f in sorted(STORIES_DIR.glob("*/story.toml")):
        st = tomllib.loads(f.read_text())
        st["id"] = f.parent.name
        n = 0
        for act in st.get("acts", []):
            for slug in act["chapters"]:
                n += 1
                if slug in scenarios:
                    scenarios[slug]["story"] = st["id"]
                    scenarios[slug]["chapter"] = n
        st["chapter_slugs"] = [c for a in st.get("acts", []) for c in a["chapters"]]
        out[st["id"]] = st
    order = list(ENGINES)
    return dict(sorted(out.items(), key=lambda kv: order.index(kv[1]["engine"]) if kv[1].get("engine") in order else 99))
