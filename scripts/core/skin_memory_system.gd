extends RefCounted
class_name SkinMemorySystem

# Data-driven implementation of the 25-fragment skin memory board.
# HTML is the current playable entrance; this class keeps the Godot project architecture aligned.

static func fresh_board() -> Dictionary:
    return {"counts": [], "claimed_lines": [], "draws": 0, "unlocked": false}

static func normalize_board(board: Dictionary) -> Dictionary:
    var out := board.duplicate(true)
    var counts: Array = out.get("counts", [])
    while counts.size() < 25:
        counts.append(0)
    if counts.size() > 25:
        counts.resize(25)
    out["counts"] = counts
    out["claimed_lines"] = out.get("claimed_lines", [])
    out["draws"] = int(out.get("draws", 0))
    out["unlocked"] = bool(out.get("unlocked", false))
    return out

static func unique_count(board: Dictionary) -> int:
    var n := 0
    for value in board.get("counts", []):
        if int(value) > 0:
            n += 1
    return n

static func next_new_probability(board: Dictionary, rules: Dictionary) -> float:
    var target := unique_count(board) + 1
    if target > 25:
        return 0.0
    var table: Dictionary = rules.get("new_fragment_probability_by_target_unique_count", {})
    return float(table.get(str(target), 0.0)) / 100.0

static func draw_one(board: Dictionary, rules: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
    var out := normalize_board(board)
    var counts: Array = out["counts"]
    var lit: Array[int] = []
    var unlit: Array[int] = []
    for i in range(25):
        if int(counts[i]) > 0:
            lit.append(i)
        else:
            unlit.append(i)
    var is_new := false
    if lit.is_empty():
        is_new = true
    elif not unlit.is_empty():
        is_new = rng.randf() < next_new_probability(out, rules)
    var pool: Array[int] = unlit if is_new else lit
    if pool.is_empty():
        pool = unlit if not unlit.is_empty() else lit
    var index: int = pool[rng.randi_range(0, pool.size() - 1)]
    counts[index] = int(counts[index]) + 1
    out["counts"] = counts
    out["draws"] = int(out.get("draws", 0)) + 1
    if unique_count(out) >= 25:
        out["unlocked"] = true
    return {"board": out, "fragment": index, "new": is_new}
