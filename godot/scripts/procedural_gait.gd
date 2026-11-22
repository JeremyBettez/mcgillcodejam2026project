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
const ACTIONS := ["wave", "dance", "moonwalk", "party"]
const LIMB_SPRING := 40.0 # ragdoll limb stiffness
const LIMB_DAMP := 5.0 # ragdoll limb damping (lower = floppier)
const LIMB_KICK := 6.0 # how hard a bounce jolts the limbs

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
var tumble_rate := 0.0 # body spin (rad/s) while thrown: flings arms out, tucks legs

var _action_time := 0.0
var _action_left := 0.0
var _limbs := {} # ragdoll limb springs, created on demand
var _rng := RandomNumberGenerator.new()
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
				legs.append({"hip": chain[0], "knee": chain[1], "side": _side_of(chain[-1], height),
					"dir": (_pos(chain[-1]) - _pos(chain[0])).normalized()})
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


## Start an action (one of ACTIONS) for `duration` seconds.
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
		"moonwalk":
			act = _moonwalk_pose(_action_time)
		"party":
			act = _party_pose(_action_time)
			act_bob = 0.09 * absf(sin(_action_time * TAU * 1.25)) # little hops
	var dangle := {}
	if dangle_weight > 0.0:
		dangle = _ragdoll_pose(delta)
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


## The moonwalk: legs take turns, one knee bent with the heel up while the other
## leg slides back straight (the body glides backwards, see Resident), torso
## leaning a touch forward, arms loose and swinging, head nodding to the beat.
func _moonwalk_pose(t: float) -> Dictionary:
	var pose := {}
	var beat := t * TAU * 1.1
	for leg in _legs:
		var side: float = leg.side
		var up := maxf(0.0, sin(beat + (0.0 if side > 0.0 else PI))) # this leg's heel-up share
		pose[leg.hip] = Quaternion(Vector3.RIGHT, 0.32 * up - 0.16 * (1.0 - up))
		pose[leg.knee] = Quaternion(Vector3.RIGHT, -0.85 * up)
	if _spine != -1:
		pose[_spine] = Quaternion(Vector3.RIGHT, 0.1) * Quaternion(Vector3.BACK, 0.05 * sin(beat))
	for arm in _arms:
		var side: float = arm.side
		var swing := 0.25 * sin(beat + (PI if side > 0.0 else 0.0))
		pose[arm.shoulder] = Quaternion(Vector3.RIGHT, swing) * (arm.down as Quaternion)
		if arm.elbow != -1:
			pose[arm.elbow] = Quaternion(Vector3.BACK, side * 0.35)
	if _neck != -1:
		pose[_neck] = Quaternion(Vector3.RIGHT, 0.14 * sin(beat * 2.0))
	return pose


## Party dance: both arms up pumping in turn, hopping with deep knee bounces,
## a quick hip-and-shoulder shimmy, head bobbing.
func _party_pose(t: float) -> Dictionary:
	var pose := {}
	var beat := t * TAU * 2.5
	var bounce := (1.0 - cos(beat)) * 0.5
	for leg in _legs:
		var side: float = leg.side
		pose[leg.hip] = Quaternion(Vector3.RIGHT, 0.3 * bounce) * Quaternion(Vector3.BACK, side * 0.08)
		pose[leg.knee] = Quaternion(Vector3.RIGHT, -0.6 * bounce)
	if _spine != -1:
		pose[_spine] = Quaternion(Vector3.UP, 0.3 * sin(beat * 0.5)) * Quaternion(Vector3.BACK, 0.1 * sin(beat))
	for arm in _arms:
		var side: float = arm.side
		var pump := (sin(beat + (0.0 if side > 0.0 else PI)) + 1.0) * 0.5
		var dir := Vector3(side * lerpf(0.25, 0.5, pump), 1.0, lerpf(-0.35, 0.05, pump)).normalized()
		pose[arm.shoulder] = Quaternion(arm.dir as Vector3, dir)
		if arm.elbow != -1:
			pose[arm.elbow] = Quaternion(Vector3.BACK, side * lerpf(0.9, 0.15, pump))
	if _neck != -1:
		pose[_neck] = Quaternion(Vector3.RIGHT, 0.2 * sin(beat))
	return pose


## Jolt every limb (e.g. hitting the ground). `strength` ~ 0..1.
func impulse(strength: float) -> void:
	for key in _limbs:
		var limb: Dictionary = _limbs[key]
		limb.v += Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * strength * LIMB_KICK
		limb.bv += _rng.randf_range(0.2, 1.0) * strength * LIMB_KICK * 0.6


## One springy limb: an angle pair (a.x = swing forward/back, a.y = raise/lower)
## chasing a randomly changing target, plus a bend amount for elbow/knee.
func _limb(key: String, delta: float, amount: float, rate: float, bias := Vector2.ZERO) -> Dictionary:
	if not _limbs.has(key):
		_limbs[key] = {"a": Vector2.ZERO, "v": Vector2.ZERO, "t": Vector2.ZERO, "bend": 0.3, "bv": 0.0, "bt": 0.3, "timer": 0.0}
	var limb: Dictionary = _limbs[key]
	limb.timer -= delta
	if limb.timer <= 0.0:
		# New random flail target; faster re-targeting = more frantic flailing.
		limb.timer = _rng.randf_range(0.25, 0.6) / maxf(rate, 0.1)
		limb.t = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * amount
		limb.bt = _rng.randf_range(0.0, 1.0) * amount
	var target: Vector2 = limb.t + bias
	limb.v += ((target - limb.a) * LIMB_SPRING - limb.v * LIMB_DAMP) * delta
	limb.a = (limb.a + limb.v * delta).clamp(Vector2(-1.8, -1.8), Vector2(1.8, 1.8))
	limb.bv += ((limb.bt - limb.bend) * LIMB_SPRING * 0.8 - limb.bv * LIMB_DAMP) * delta
	limb.bend = clampf(limb.bend + limb.bv * delta, 0.0, 1.4)
	return limb


## Ragdoll while held, thrown or skidding: every limb is a damped spring that
## flails toward random targets (arms windmill, legs kick), spinning flings the
## arms out and tucks the legs/torso in, bounces jolt everything (see impulse),
## and the whole lot lags behind the body's pendulum swing.
func _ragdoll_pose(delta: float) -> Dictionary:
	var pose := {}
	var lag := Quaternion(Vector3.RIGHT, -swing.x) * Quaternion(Vector3.BACK, -swing.y)
	var fling := clampf(absf(tumble_rate) / 8.0, 0.0, 1.0) # how hard the spin throws limbs out
	var amount := clampf(struggle, 0.0, 1.0)
	var rate := 0.6 + 2.4 * amount
	for arm in _arms:
		var side: float = arm.side
		# Arms ride higher when held/struggling and fly out when spinning.
		var raise := lerpf(-0.6, 0.35, amount) + 0.7 * fling
		var limb := _limb("arm%d" % int(side), delta, 1.1 * amount + 0.25, rate, Vector2(0.0, raise))
		var a: Vector2 = limb.a
		var base := Vector3(side, 0.0, 0.0)
		var dir := Basis(Vector3.RIGHT, a.x) * Basis(Vector3.BACK, a.y * side) * base
		pose[arm.shoulder] = lag * Quaternion(arm.dir as Vector3, dir.normalized())
		if arm.elbow != -1:
			pose[arm.elbow] = Quaternion(Vector3.UP, side * 1.3 * float(limb.bend))
	for leg in _legs:
		var side: float = leg.side
		var tuck := 0.9 * fling # knees come up during flips
		var limb := _limb("leg%d" % int(side), delta, 0.8 * amount + 0.2, rate, Vector2(tuck, 0.0))
		var a: Vector2 = limb.a
		var base := Vector3(side * 0.15, -1.0, 0.0).normalized()
		var dir := Basis(Vector3.RIGHT, a.x) * Basis(Vector3.BACK, a.y * 0.5 * side) * base
		pose[leg.hip] = lag * Quaternion(leg.dir as Vector3, dir.normalized())
		pose[leg.knee] = Quaternion(Vector3.RIGHT, -(0.15 + 1.2 * float(limb.bend) + 0.6 * fling))
	var torso := _limb("torso", delta, 0.35 * amount + 0.1, rate * 0.7, Vector2(0.5 * fling, 0.0))
	var t: Vector2 = torso.a
	if _spine != -1:
		pose[_spine] = Quaternion(Vector3.RIGHT, t.x - swing.x * 0.4) * Quaternion(Vector3.BACK, t.y * 0.5 - swing.y * 0.4)
	if _neck != -1:
		var head := _limb("head", delta, 0.5 * amount + 0.2, rate, Vector2(0.25, 0.0))
		var h: Vector2 = head.a
		pose[_neck] = Quaternion(Vector3.RIGHT, h.x) * Quaternion(Vector3.BACK, h.y * 0.6 - swing.y * 0.8)
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
