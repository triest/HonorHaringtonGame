extends RefCounted
## IndividualCommandState
##
## ТЗ §31 Individual Override ("The override must be represented in
## simulation state") + §35 Command Queue applied at the single-ship
## level. One instance per ship that currently has (or has ever had) an
## individual order issued to it -- deliberately the mirror image of
## FormationState's own `current_order`/`order_queue` pair, kept as a
## SEPARATE small class (not folded into ShipPhysicsState, which stays a
## pure physics data object per its own class doc, and not shared with
## FormationState, which is a formation-level concept) so "does this ship
## have a standing individual order overriding its formation" is a single,
## explicit, queryable piece of state (`is_active()`), not something a
## caller has to infer from thrust values.
class_name IndividualCommandState

var current_order = null
var order_queue: Array = []

## §35 Command Queue: append an order to run once earlier queued orders
## (and the current one, if any) complete.
func issue_order(order) -> void:
	order_queue.append(order)

func issue_orders(orders: Array) -> void:
	for order in orders:
		order_queue.append(order)

## Interrupt whatever is currently executing (or queued) and start this
## order immediately.
func issue_order_now(order) -> void:
	order_queue.clear()
	current_order = order

## §30 "return to formation": drop any individual order/queue for this
## ship. Not itself a maneuver -- once `is_active()` is false, this ship's
## thrust/orientation are no longer touched by
## SimulationWorld._resolve_individual_orders, so whatever the ship's
## formation (if any) computes for it in `_resolve_formation_keeping`
## simply takes effect again next tick, unmodified. A ship with no
## formation at all just keeps whatever thrust its last order left it at.
func clear_orders() -> void:
	order_queue.clear()
	current_order = null

## True while an order is active or queued -- i.e. this ship is currently
## under individual command rather than left to its formation (or to
## nothing, for a ship with no formation).
func is_active() -> bool:
	return current_order != null or not order_queue.is_empty()
