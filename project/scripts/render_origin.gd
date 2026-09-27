extends RefCounted
## RenderOrigin
##
## 2026-09-27 (user: "can't zoom in on the ships themselves"): floating
## render origin. Simulation positions are in metres at canon scale
## (millions of km); Godot's 32-bit render transforms lose all sub-km
## detail that far from (0,0,0), so a 500 m hull zoomed into at 2.6e9 m
## renders as garbage. Every 3D view subtracts `origin` from simulation
## positions before assigning a transform, and OrbitCamera (when its
## use_floating_origin is on -- the live game) keeps `origin` equal to its
## pivot, so whatever the camera looks at sits near (0,0,0) in render
## space at full precision. Default ZERO = old behavior (tests, tools).
## Pure rendering concern: the simulation itself never reads this.
class_name RenderOrigin

static var origin: Vector3 = Vector3.ZERO

static func to_render(world_pos: Vector3) -> Vector3:
	return world_pos - origin

static func to_world(render_pos: Vector3) -> Vector3:
	return render_pos + origin
