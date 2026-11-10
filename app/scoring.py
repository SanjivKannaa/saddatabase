"""Points for a solve. Kept per attempt; a user's score for a scenario is their best attempt."""

BASE = {"easy": 100, "medium": 200, "hard": 300}
HINT_PENALTY = 0.15      # of base, per hint seen (ever, for this scenario)
FAST_HALF = 0.30         # solved in under half the estimated minutes
FAST = 0.15              # solved within the estimate
FIRST_CHECK = 0.10       # the first Check of the attempt passed
FLOOR = 0.10             # any honest solve is worth at least this


def max_points(difficulty: str) -> int:
    b = BASE.get(difficulty, 100)
    return round(b * (1 + FAST_HALF + FIRST_CHECK))


def compute(difficulty: str, minutes: int, seconds: int, hints: int, peeked: bool, checks: int) -> dict:
    """checks = number of checks in this attempt including the passing one."""
    b = BASE.get(difficulty, 100)
    if peeked:
        return {"total": 0, "parts": [["Solution viewed before solving", 0]]}
    parts = [[f"Base ({difficulty})", b]]
    est = max(1, minutes) * 60
    if seconds <= est / 2:
        parts.append([f"Fast: under half the {minutes} min estimate", round(b * FAST_HALF)])
    elif seconds <= est:
        parts.append([f"Within the {minutes} min estimate", round(b * FAST)])
    if checks <= 1:
        parts.append(["Passed on the first check", round(b * FIRST_CHECK)])
    if hints:
        parts.append([f"{hints} hint{'s' if hints > 1 else ''} used", -round(b * HINT_PENALTY * hints)])
    total = max(round(b * FLOOR), sum(p[1] for p in parts))
    return {"total": total, "parts": parts}


RULES = {
    "base": BASE, "hint_penalty_pct": round(HINT_PENALTY * 100), "fast_half_pct": round(FAST_HALF * 100),
    "fast_pct": round(FAST * 100), "first_check_pct": round(FIRST_CHECK * 100), "floor_pct": round(FLOOR * 100),
}
