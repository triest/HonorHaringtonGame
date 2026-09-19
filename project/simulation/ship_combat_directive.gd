extends RefCounted
## ShipCombatDirective
##
## ТЗ §30 Individual Ship Orders -- "target"/"target priority" and "weapon
## mode" slice (Milestone 11, second slice). Until this pass EVERY ship's
## weapon-target selection was fully automatic every tick
## (TacticalAI.select_weapon_target -- nearest usable hostile contact, see
## tactical_ai.gd), with no way for a commander to designate a specific
## target ("target priority") or to order a ship to stand down its
## weapons ("weapon mode" -- e.g. hold fire while closing to range, or
## under a local ceasefire) independent of whether a valid target exists.
##
## Deliberately a SEPARATE small state object from IndividualCommandState
## (the kinematic order queue, §30 course/speed/orientation) and
## FormationState -- a combat directive has no "queue"/"completion"
## concept (holding a target or holding fire is a standing POSTURE, not a
## maneuver that finishes), so forcing it into the order/queue model used
## for CHANGE_COURSE etc. would be dishonest. One instance per ship that
## has ever received a combat directive, created lazily exactly like
## IndividualCommandState (see SimulationWorld._get_or_create_combat_directive).
##
## HONEST SCOPE: covers only §30's "target"/"target priority"
## (manual_target_ship_id) and "weapon mode" (weapons_free), applied
## together to ship-to-ship ENERGY weapons and missile launches (both
## gated the same way -- see SimulationWorld._resolve_weapons_ai /
## _resolve_missile_launch_ai / _resolve_weapon_target). Still explicitly
## OUT of scope, honestly left open (see ASSUMPTIONS.md): "missile
## launch" as a distinct one-shot action separate from this standing
## posture, "counter-missile policy"/"point-defense policy" (PD target
## selection is threat-based -- nearest missile actually targeting this
## ship, see TacticalAI.select_pd_target -- a fundamentally different
## concept from picking which ENEMY SHIP to shoot at, so this directive
## deliberately does not touch PD at all), "sensor mode", "ECM mode",
## "defensive posture" -- none of these get new mechanics in this pass.
class_name ShipCombatDirective

## "" = no manual override; SimulationWorld._resolve_weapon_target falls
## through to the pre-existing automatic TacticalAI.select_weapon_target
## nearest-hostile-contact selection unchanged. Non-empty = a commander-
## designated target ship_id (§30 "target"/"target priority"), used by
## BOTH energy weapons and missile launch target selection in place of
## the automatic pick -- for as long as it remains a valid USABLE hostile
## contact (see TacticalAI.select_directed_weapon_target). The instant it
## stops being one (destroyed, or lost from this ship's own sensors), the
## directive is honestly treated as no longer executable and
## SimulationWorld falls back to automatic selection rather than either
## silently holding fire or firing on stale/no information -- no crew
## doctrine expects "keep shooting the last known bearing of a target we
## can no longer see" to be the correct default.
var manual_target_ship_id: String = ""

## §30 "weapon mode": true (default, matches all pre-existing behavior
## before this pass) = free to fire at will per whatever target selection
## above resolves to. false = hold fire -- neither energy weapons nor
## missile tubes fire this ship's weapons, even at a valid designated or
## automatically-selected target. Missile tubes still advance their own
## cooldown while held (see SimulationWorld._resolve_missile_launch_ai) --
## this is a fire-control decision, not equipment damage or a jammed tube.
var weapons_free: bool = true

func set_manual_target(target_ship_id: String) -> void:
	manual_target_ship_id = target_ship_id

func clear_manual_target() -> void:
	manual_target_ship_id = ""

func set_weapons_free(is_free: bool) -> void:
	weapons_free = is_free
