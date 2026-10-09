extends RefCounted
## ImpactBadgeModel
##
## Pure model behind the "x N" impact badges (ТЗ §42: no scene, no simulation
## access). Strikes on the same ship that land within MERGE_WINDOW_S of each
## other (wall-clock) merge into ONE badge, so a 20-missile salvo reads as a
## single "x20" tag instead of twenty overlapping ones. ImpactBadgeOverlay draws
## it; ImpactFxDirector feeds it from ImpactRecord snapshots.
class_name ImpactBadgeModel

const MERGE_WINDOW_S: float = 0.8
const LIFE_S: float = 2.4

## ship_id -> {ship_id, hits, absorbed, damage, first_s, last_s, by_outcome}
var badges: Dictionary = {}

## `incoming`/`damage`: yield offered / yield that got through (absorbed =
## incoming - damage). `outcome`: MissileResolution.Outcome of the strike.
func add(ship_id: String, hits: int, incoming: float, damage: float, outcome: int, now_s: float) -> void:
	var badge: Dictionary = badges.get(ship_id, {})
	if badge.is_empty() or now_s - float(badge["last_s"]) > MERGE_WINDOW_S:
		badge = {"ship_id": ship_id, "hits": 0, "absorbed": 0.0, "damage": 0.0, "first_s": now_s, "last_s": now_s, "by_outcome": {}}
	badge["hits"] += hits
	badge["absorbed"] += maxf(incoming - damage, 0.0)
	badge["damage"] += damage
	badge["last_s"] = now_s
	var by_outcome: Dictionary = badge["by_outcome"]
	by_outcome[outcome] = float(by_outcome.get(outcome, 0.0)) + incoming
	badges[ship_id] = badge

## Drops badges whose life has run out.
func prune(now_s: float) -> void:
	for ship_id in badges.keys():
		if now_s - float(badges[ship_id]["last_s"]) > LIFE_S:
			badges.erase(ship_id)

## Outcome that carried the most incoming yield in `badge` (-1 if empty).
static func dominant_outcome(badge: Dictionary) -> int:
	var best: int = -1
	var best_value: float = -1.0
	for outcome in badge["by_outcome"].keys():
		var v: float = badge["by_outcome"][outcome]
		if v > best_value:
			best_value = v
			best = outcome
	return best

## 1.0 while fresh, falling to 0.0 over the last 0.6 s of life.
static func alpha(badge: Dictionary, now_s: float) -> float:
	var remaining: float = LIFE_S - (now_s - float(badge["last_s"]))
	return clampf(remaining / 0.6, 0.0, 1.0)
