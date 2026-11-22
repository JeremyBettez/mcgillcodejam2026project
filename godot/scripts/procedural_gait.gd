class_name ProceduralGait
extends RefCounted
## Walk cycle for AniGen skeletons, which have generated bone names (joint_0...)
## that change per model. Limbs are found from the bone hierarchy and rest
## positions instead of names:
##   root = pelvis; its two lowest child chains = legs; its highest child = spine;
##   the leaf bones furthest left/right in the spine subtree = hands (arm chains).
## Model space: +Y up, faces -Z, so the swing axis is +X.
## If the skeleton can't be classified, `ok` is false and the caller uses a simple waddle.

const STEP_RATE := 1.7 # steps (full cycles) per second at full walk
const LEG_SWING := 0.45 # radians
const KNEE_BEND := 0.7
const ARM_SWING := 0.4
const ARM_OUT := 0.22 # how far the lowered arms stay away from the body (x per unit down)

var ok := false
var skeleton: Skeleton3D
var phase := 0.0
var amount := 0.0 # 0 = standing, 1 = full walk

var _legs: Array[Dictionary] = [] # {hip, knee, side}
var _arms: Array[Dictionary] = [] # {shoulder, side, down: Quaternion}


func setup(sk: Skeleton3D) -> bool:
	skeleton = sk
	ok = false
	_legs.clear()
	_arms.clear()
	if sk == null or sk.get_bone_count() < 8:
		return false

	var root := _find_root()
	var root_y := _pos(root).y
	var height := _subtree_max_y(root) - _subtree_min_y(root)
	if height <= 0.0:
		return false

	# Legs: the two root children whose chains reach lowest, well below the pelvis.
	var kids: Array = Array(sk.get_bone_children(root))
	kids.sort_custom(func(a: int, b: int) -> bool: return _subtree_min_y(a) < _subtree_min_y(b))
	var leg_roots: Array = kids.filter(func(c: int) -> bool: return _subtree_min_y(c) < root_y - height * 0.3)
	if leg_roots.size() < 2:
		return false
	for c in leg_roots.slice(0, 2):
		var chain := _chain_to_lowest(c)
		if chain.size() < 2:
			return false
		_legs.append({"hip": chain[0], "knee": chain[1], "side": signf(_pos(chain[-1]).x)})
	if _legs[0].side == _legs[1].side:
		return false

	# Spine: the root child that reaches highest.
	var spine := -1
	for c in kids:
		if spine == -1 or _subtree_max_y(c) > _subtree_max_y(spine):
			spine = c
	if spine == -1 or spine in leg_roots:
		return false

	# Arms: the leaf bones furthest to each side in the spine subtree.
	var leaves := _subtree(spine).filter(func(b: int) -> bool: return sk.get_bone_children(b).is_empty())
	var right_hand := -1
	var left_hand := -1
	for b in leaves:
		if right_hand == -1 or _pos(b).x > _pos(right_hand).x:
			right_hand = b
		if left_hand == -1 or _pos(b).x < _pos(left_hand).x:
			left_hand = b
	for hand in [right_hand, left_hand]:
		if hand == -1 or absf(_pos(hand).x) < height * 0.1:
			return false
		var chain := _chain_up_to_branch(hand)
		# chain = [clavicle, upper arm, forearm, hand...]; rotate at the upper arm if there is one.
		var shoulder: int = chain[1] if chain.size() >= 4 else chain[0]
		var arm_dir := (_pos(hand) - _pos(shoulder)).normalized()
		var side := signf(_pos(hand).x)
		var target := Vector3(side * ARM_OUT, -1.0, 0.0).normalized()
		_arms.append({"shoulder": shoulder, "side": side, "down": Quaternion(arm_dir, target)})

	ok = true
	apply(0.0, false)
	return true


## Advance the cycle. Returns a vertical bob offset for the avatar root.
func apply(delta: float, walking: bool) -> float:
	amount = move_toward(amount, 1.0 if walking else 0.0, delta * 4.0)
	phase = fmod(phase + delta * TAU * STEP_RATE * amount, TAU)
	if not ok:
		return 0.0
	var s := sin(phase)
	var c := cos(phase)
	for leg in _legs:
		var side: float = leg.side
		var swing := s * side * LEG_SWING * amount
		_rotate_bone(leg.hip, Quaternion(Vector3.RIGHT, swing))
		var bend := -KNEE_BEND * amount * maxf(0.0, c * side)
		_rotate_bone(leg.knee, Quaternion(Vector3.RIGHT, bend))
	for arm in _arms:
		# Arms swing opposite to the leg on the same side.
		var side: float = arm.side
		var swing := -s * side * ARM_SWING * amount
		_rotate_bone(arm.shoulder, Quaternion(Vector3.RIGHT, swing) * (arm.down as Quaternion))
	return 0.03 * amount * (1.0 - absf(s))


## Rotate a bone by `rot`, expressed in skeleton space, on top of its rest pose.
func _rotate_bone(bone: int, rot: Quaternion) -> void:
	var global_rest := skeleton.get_bone_global_rest(bone).basis.orthonormalized().get_rotation_quaternion()
	var local_rest := skeleton.get_bone_rest(bone).basis.orthonormalized().get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, local_rest * (global_rest.inverse() * rot * global_rest))


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
