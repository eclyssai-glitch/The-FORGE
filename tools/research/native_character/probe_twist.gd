extends SceneTree
## SPIKE probe 5: BoneTwistDisperser3D configurations on the real rig (candy-wrapper at the wrist).
const DT := 1.0 / 30.0


func _initialize() -> void:
	_run.call_deferred()


func _twist_of(h: NCHarness, bone: String) -> float:
	var i := h.sk.find_bone(bone)
	var p := h.sk.get_bone_parent(i)
	var local := (h.snap[p].basis.inverse() * h.snap[i].basis).get_rotation_quaternion()
	var rest := h.sk.get_bone_rest(i).basis.get_rotation_quaternion()
	var d := rest.inverse() * local
	var tw := Quaternion(0, d.y, 0, d.w).normalized()
	return rad_to_deg(2.0 * atan2(tw.y, tw.w))


func _run() -> void:
	var cfgs := [
		["upper_arm.R", "hand.R", false, false, 0],
		["upper_arm.R", "hand.R", true, false, 0],
		["upper_arm.R", "hand.R", true, true, 0],
		["upper_arm.R", "middle.0.R", false, false, 0],
		["upper_arm.R", "middle.0.R", false, true, 0],
		["forearm.R", "middle.0.R", false, true, 1],
	]
	for c: Array in cfgs:
		var body := MikuRig.build()
		root.add_child(body)
		var h := NCHarness.new(body)
		var lk := LookAtModifier3D.new()  # keeps skeleton_updated firing
		h.sk.add_child(lk)
		lk.influence = 0.0
		lk.bone_name = "head"
		var tw := BoneTwistDisperser3D.new()
		h.sk.add_child(tw)
		tw.setting_count = 1
		tw.set_root_bone_name(0, c[0])
		tw.set_end_bone_name(0, c[1])
		tw.set_extend_end_bone(0, c[2])
		tw.set_twist_from_rest(0, c[3])
		tw.set_disperse_mode(0, c[4])
		var hand := h.sk.find_bone("hand.R")
		for i in range(3):
			RigData.pose_local(h.sk, hand, Vector3(0, deg_to_rad(80.0), 0))
			h.advance(DT)
			await process_frame
		print("R twist cfg root=%s end=%s extend=%s from_rest=%s mode=%d joints=%d -> upper_arm %.1f forearm %.1f hand %.1f (updates %d)" % [
				c[0], c[1], c[2], c[3], c[4], tw.get_joint_count(0), _twist_of(h, "upper_arm.R"), _twist_of(h, "forearm.R"), _twist_of(h, "hand.R"), h.updates])
		body.queue_free()
		await process_frame
	quit()
