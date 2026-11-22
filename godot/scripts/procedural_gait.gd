class_name ProceduralGait
extends RefCounted
## Procedural body animation for AniGen skeletons: walk cycle plus "wave" and
## "dance" actions. AniGen bones have generated names (joint_0...) that change
## per model, so limbs are found from the hierarchy and rest positions instead:
##   root = pelvis; its two lowest child chains = legs; its highest child = spine;
##   the leaf bones furthest left/right in the spine subtree = hands (arm chains
##   [clavicle, upper arm, forearm, hand]); the remaining branch at the top of the
##   spine = neck/head.
## Model space: +Y up, faces -Z, +X is the character's right; swing axis is +X.
## Each frame builds a pose (bone -> rotation in skeleton space) for walking and
## for the current action, and blends between them.
## If the skeleton can't be classified, `ok` is false and the caller uses a simple waddle.

const STEP_RATE := 1.7 # steps (full cycles) per second at full walk
const LEG_SWING := 0.45 # radians
const KNEE_BEND := 0.7
const ARM_SWING := 0.4
const ARM_OUT := 0.22 # how far the lowered arms stay away from the body (x per unit down)
const BLEND_RATE := 4.0 # how fast actions fade in/out (per second)
const ACTIONS := ["wave", "dance"]

var ok := false
var skeleton: Skeleton3D
var phase := 0.0
var amount := 0.0 # 0 = standing, 1 = full walk
var action := "" # "", "wave" or "dance"
var action_weight := 0.0 # 0..1 blend of the action over the walk/idle pose
## Ragdoll-style dangling while picked up: set by the resident each frame.
var dangle_weight := 0.0 # 0..1 blend of the dangle pose over everything else
var swing := Vector2.ZERO # body swing (x = pitch fwd/back, y = roll sideways), radians
var struggle := 0.0 # 0..1 how much the limbs flail

var _action_time := 0.0
var _action_left := 0.0
var _dangle_time := 0.0
var _legs: Array[Dictionary] = [] # {hip, knee, side}
var _arms: Array[Dictionary] = [] # {shoulder, elbow, side, dir, down}; [0] is the right arm
var _spine := -1
var _neck := -1
var _managed: Array[int] = [] # every bone this class poses


func setup(sk: Skeleton3D) -> bool:
	skeleton = sk
	ok = false
	_legs.clear()
	_arms.clear()
	_managed.clear()
	_spine = -1
	_neck = -1
	# Every part below is optional: a model with an odd skeleton (different bone
	# count, arms tight to the body, no neck...) still animates whatever was found.
	# Only if nothing is found does the caller fall back to whole-body motion.
	if sk == null or sk.get_bone_count() < 3:
		return false

	var root := _find_root()
	var root_y := _pos(root).y
	var height := _subtree_max_y(root) - _subtree_min_y(root)
	if height <= 0.0:
		return false
	var kids: Array = Array(sk.get_bone_children(root))

	# Legs: the two root children whose chains reach lowest, well below the pelvis,
	# on opposite sides.
	kids.sort_custom(func(a: int, b: int) -> bool: return _subtree_min_y(a) < _subtree_min_y(b))
	var leg_roots: Array = kids.filter(func(c: int) -> bool: return _subtree_min_y(c) < root_y - height * 0.3)
	if leg_roots.size() >= 2:
		var legs: Array[Dictionary] = []
		for c in leg_roots.slice(0, 2):
			var chain := _chain_to_lowest(c)
			if chain.size() >= 2:
				legs.append({"hip": chain[0], "knee": chain[1], "side": _side_of(chain[-1], height)})
		if legs.size() == 2 and legs[0].side != legs[1].side and legs[0].side != 0.0 and legs[1].side != 0.0:
			_legs = legs

	# Spine: the root child that reaches highest (not a leg).
	for c in kids:
		if c in leg_roots and _legs.size() == 2:
			continue
		if _spine == -1 or _subtree_max_y(c) > _subtree_max_y(_spine):
			_spine = c
	if _spine != -1 and _subtree_max_y(_spine) <= root_y:
		_spine = -1 # nothing above the pelvis: not a spine

	# Arms: the leaf bones furthest to each side above the pelvis, traced back to
	# where they leave the spine (so extra branches like fingers don't matter).
	var arm_roots: Array = []
	if _spine != -1:
		var spine_path := _chain_to_highest(_spine)
		var leaves := _subtree(_spine).filter(func(b: int) -> bool: return sk.get_bone_children(b).is_empty())
		var right_hand := -1
		var left_hand := -1
		for b in leaves:
			if right_hand == -1 or _pos(b).x > _pos(right_hand).x:
				right_hand = b
			if left_hand == -1 or _pos(b).x < _pos(left_hand).x:
				left_hand = b
		var arms: Array[Dictionary] = []
		for hand in [right_hand, left_hand]:
			if hand == -1 or _side_of(hand, height) == 0.0:
				continue # hand too close to the middle to tell which side it's on
			var chain := _chain_up_to_spine(hand, spine_path)
			if chain.size() < 2:
				continue
			# Rotate at the upper arm if there is a clavicle in front of it.
			var shoulder: int = chain[1] if chain.size() >= 4 else chain[0]
			var elbow: int = chain[2] if chain.size() >= 4 else (chain[1] if chain.size() == 3 else -1)
			var arm_dir := _pos(hand) - _pos(shoulder)
			if arm_dir.length() < height * 0.05:
				continue
			arm_dir = arm_dir.normalized()
			var side := _side_of(hand, height)
			var target := Vector3(side * ARM_OUT, -1.0, 0.0).normalized()
			arms.append({"shoulder": shoulder, "elbow": elbow, "side": side, "dir": arm_dir, "down": Quaternion(arm_dir, target)})
			arm_roots.append(chain[0])
		if arms.size() == 2 and arms[0].side != arms[1].side:
			_arms = arms # [0] is the right arm (+X)
		else:
			arm_roots.clear()

	# Neck: the other branch where the arms attach, the one reaching highest.
	if not arm_roots.is_empty():
		var branch := sk.get_bone_parent(arm_roots[0])
		if branch != -1:
			for c in sk.get_bone_children(branch):
				if c in arm_roots:
					continue
				if _neck == -1 or _subtree_max_y(c) > _subtree_max_y(_neck):
					_neck = c

	if _legs.is_empty() and _arms.is_empty() and _spine == -1:
		return false

	for bone in [_spine, _neck]:
		if bone != -1:
			_managed.append(bone)
	for leg in _legs:
		_managed.append_array([leg.hip, leg.knee])
	for arm in _arms:
		_managed.append(arm.shoulder)
		if arm.elbow != -1:
			_managed.append(arm.elbow)

	ok = true
	apply(0.0, false)
	return true


## Start an action ("wave" or "dance") for `duration` seconds.
func play(name: String, duration: float) -> void:
	if name not in ACTIONS:
		return
	action = name
	_action_time = 0.0
	_action_left = duration


func is_acting() -> bool:
	return _action_left > 0.0


## Cancel the current action (it blends out).
func stop_action() -> void:
	_action_left = 0.0


## Advance one frame. Returns a vertical bob offset for the avatar root.
func apply(delta: float, walking: bool) -> float:
	amount = move_toward(amount, 1.0 if walking else 0.0, delta * 4.0)
	phase = fmod(phase + delta * TAU * STEP_RATE * amount, TAU)
	_action_left = maxf(0.0, _action_left - delta)
	_action_time += delta
	action_weight = move_toward(action_weight, 1.0 if _action_left > 0.0 else 0.0, delta * BLEND_RATE)
	if action_weight == 0.0 and _action_left == 0.0:
		action = ""
	if not ok:
		return 0.0

	var walk := _walk_pose()
	var act := {}
	var act_bob := 0.0
	match action:
		"wave":
			act = _wave_pose(_action_time)
		"dance":
			act = _dance_pose(_action_time)
			act_bob = -0.05 * (1.0 - cos(_action_time * TAU * 2.0)) * 0.5
	var dangle := {}
	if dangle_weight > 0.0:
		_dangle_time += delta
		dangle = _dangle_pose(_dangle_time)
	for bone in _managed:
		var from: Quaternion = walk.get(bone, Quaternion.IDENTITY)
		var to: Quaternion = act.get(bone, Quaternion.IDENTITY)
		var rot := from.slerp(to, action_weight) if action_weight > 0.0 else from
		if dangle_weight > 0.0:
			rot = rot.slerp(dangle.get(bone, Quaternion.IDENTITY), dangle_weight)
		_rotate_bone(bone, rot)
	var walk_bob := 0.03 * amount * (1.0 - absf(sin(phase)))
	return lerpf(lerpf(walk_bob, act_bob, action_weight), 0.0, dangle_weight)


func _walk_pose() -> Dictionary:
	var pose := {}
	var s := sin(phase)
	var c := cos(phase)
	for leg in _legs:
		var side: float = leg.side
		pose[leg.hip] = Quaternion(Vector3.RIGHT, s * side * LEG_SWING * amount)
		pose[leg.knee] = Quaternion(Vector3.RIGHT, -KNEE_BEND * amount * maxf(0.0, c * side))
	for arm in _arms:
		# Arms swing opposite to the leg on the same side.
		var side: float = arm.side
		pose[arm.shoulder] = Quaternion(Vector3.RIGHT, -s * side * ARM_SWING * amount) * (arm.down as Quaternion)
	return pose


## Right arm raised, forearm swinging side to side; left arm relaxed.
func _wave_pose(t: float) -> Dictionary:
	var pose := {}
	if _arms.size() < 2:
		# No arms found: a friendly side-to-side sway of the upper body instead.
		if _spine != -1:
			pose[_spine] = Quaternion(Vector3.BACK, 0.15 * sin(t * TAU * 1.6))
		return pose
	var waving: Dictionary = _arms[0]
	var other: Dictionary = _arms[1]
	var side: float = waving.side
	var up := Vector3(side * 0.45, 1.0, -0.15).normalized()
	pose[waving.shoulder] = Quaternion(waving.dir as Vector3, up)
	if waving.elbow != -1:
		pose[waving.elbow] = Quaternion(Vector3.BACK, side * (0.3 + 0.45 * sin(t * TAU * 1.6)))
	pose[other.shoulder] = other.down
	if _spine != -1:
		pose[_spine] = Quaternion(Vector3.BACK, -side * 0.06)
	if _neck != -1:
		pose[_neck] = Quaternion(Vector3.BACK, side * 0.1 * sin(t * TAU * 0.8))
	return pose


## Bouncing knees, swaying/twisting torso, arms pumping in turn, head bobbing.
func _dance_pose(t: float) -> Dictionary:
	var pose := {}
	var beat := t * TAU * 2.0 # two bounces per second
	var bounce := (1.0 - cos(beat)) * 0.5
	for leg in _legs:
		pose[leg.hip] = Quaternion(Vector3.RIGHT, 0.25 * bounce)
		pose[leg.knee] = Quaternion(Vector3.RIGHT, -0.5 * bounce)
	if _spine != -1:
		pose[_spine] = Quaternion(Vector3.UP, 0.35 * sin(beat * 0.5)) * Quaternion(Vector3.BACK, 0.12 * sin(beat * 0.5))
	for arm in _arms:
		var side: float = arm.side
		var lift := (sin(beat * 0.5 + (0.0 if side > 0.0 else PI)) + 1.0) * 0.5
		var dir := Vector3(side * 0.7, lerpf(-0.2, 1.0, lift), -0.3).normalized()
		pose[arm.shoulder] = Quaternion(arm.dir as Vector3, dir)
		if arm.elbow != -1:
			pose[arm.elbow] = Quaternion(Vector3.BACK, side * 0.8)
	if _neck != -1:
		pose[_neck] = Quaternion(Vector3.RIGHT, 0.12 * sin(beat))
	return pose


## Picked up and dangling: legs hang and kick, arms flail out, head flops, and
## every limb lags behind the body's swing like a ragdoll.
func _dangle_pose(t: float) -> Dictionary:
	var pose := {}
	var lag := Quaternion(Vector3.RIGHT, -swing.x) * Quaternion(Vector3.BACK, -swing.y)
	for leg in _legs:
		var side: float = leg.side
		var kick := sin(t * 9.0 + (0.0 if side > 0.0 else PI)) * 0.3 * struggle
		pose[leg.hip] = lag * Quaternion(Vector3.RIGHT, -swing.x * 0.4 + kick) * Quaternion(Vector3.BACK, side * 0.12)
		pose[leg.knee] = Quaternion(Vector3.RIGHT, -0.3 - 0.25 * absf(sin(t * 9.0)) * struggle)
	for arm in _arms:
		var side: float = arm.side
		var flap := sin(t * 7.0 + side) * 0.3 * struggle
		var dir := Vector3(side * 0.9, 0.35 + flap, -0.2).normalized()
		pose[arm.shoulder] = lag * Quaternion(arm.dir as Vector3, dir)
		if arm.elbow != -1:
			pose[arm.elbow] = Quaternion(Vector3.BACK, side * (0.4 + 0.3 * sin(t * 7.0)))
	if _spine != -1:
		pose[_spine] = Quaternion(Vector3.RIGHT, -swing.x * 0.4) * Quaternion(Vector3.BACK, -swing.y * 0.4)
	if _neck != -1:
		pose[_neck] = Quaternion(Vector3.RIGHT, 0.25) * Quaternion(Vector3.BACK, -swing.y * 0.8)
	return pose


## Rotate a bone by `rot`, expressed in skeleton space, on top of its rest pose.
func _rotate_bone(bone: int, rot: Quaternion) -> void:
	var global_rest := skeleton.get_bone_global_rest(bone).basis.orthonormalized().get_rotation_quaternion()
	var local_rest := skeleton.get_bone_rest(bone).basis.orthonormalized().get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, local_rest * (global_rest.inverse() * rot * global_rest))


## +1 right, -1 left, 0 if the bone is too close to the middle to tell.
func _side_of(bone: int, height: float) -> float:
	var x := _pos(bone).x
	return 0.0 if absf(x) < height * 0.04 else signf(x)


func _pos(bone: int) -> Vector3:
	return skeleton.get_bone_global_rest(bone).origin


func _find_root() -> int:
	var best := 0
	var best_size := -1
	for b in skeleton.get_bone_count():
		if skeleton.get_bone_parent(b) == -1:
			var size := _subtree(b).size()
			if size > best_size:
				best = b
				best_size = size
	return best


func _subtree(bone: int) -> Array:
	var out: Array = []
	var stack: Array = [bone]
	while not stack.is_empty():
		var b: int = stack.pop_back()
		out.append(b)
		stack.append_array(Array(skeleton.get_bone_children(b)))
	return out


func _subtree_min_y(bone: int) -> float:
	var m := INF
	for b in _subtree(bone):
		m = minf(m, _pos(b).y)
	return m


func _subtree_max_y(bone: int) -> float:
	var m := -INF
	for b in _subtree(bone):
		m = maxf(m, _pos(b).y)
	return m


func _chain_to_lowest(bone: int) -> Array:
	var chain: Array = [bone]
	var b := bone
	while not skeleton.get_bone_children(b).is_empty():
		var next := -1
		for c in skeleton.get_bone_children(b):
			if next == -1 or _subtree_min_y(c) < _subtree_min_y(next):
				next = c
		b = next
		chain.append(b)
	return chain


## From `bone` down the child that reaches highest, to the top (spine -> head).
func _chain_to_highest(bone: int) -> Array:
	var chain: Array = [bone]
	var b := bone
	while not skeleton.get_bone_children(b).is_empty():
		var next := -1
		for c in skeleton.get_bone_children(b):
			if next == -1 or _subtree_max_y(c) > _subtree_max_y(next):
				next = c
		b = next
		chain.append(b)
	return chain


## From a leaf up to (not including) the first ancestor on `spine_path`.
## Falls back to stopping at a branch if the leaf isn't under the spine path.
func _chain_up_to_spine(leaf: int, spine_path: Array) -> Array:
	var chain: Array = [leaf]
	var b := leaf
	while true:
		var p := skeleton.get_bone_parent(b)
		if p == -1:
			return _chain_up_to_branch(leaf)
		if p in spine_path:
			break
		b = p
		chain.push_front(b)
	return chain


## From a leaf up to (not including) the nearest ancestor that branches.
func _chain_up_to_branch(leaf: int) -> Array:
	var chain: Array = [leaf]
	var b := leaf
	while true:
		var p := skeleton.get_bone_parent(b)
		if p == -1 or skeleton.get_bone_children(p).size() > 1:
			break
		b = p
		chain.push_front(b)
	return chain
