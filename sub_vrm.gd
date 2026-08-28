extends Window

const RAY_LENGTH = 10
var vrm = preload('res://addons/vrm/vrm_extension.gd')
var vrm_inst: GLTFDocumentExtension = vrm.new()
const VRMC_node_constraint = preload('res://addons/vrm/1.0/VRMC_node_constraint.gd')
var VRMC_node_constraint_inst := VRMC_node_constraint.new()
const VRMC_springBone = preload('res://addons/vrm/1.0/VRMC_springBone.gd')
var VRMC_springBone_inst := VRMC_springBone.new()
const VRMC_materials_mtoon = preload('res://addons/vrm/1.0/VRMC_materials_mtoon.gd')
var VRMC_materials_mtoon_inst := VRMC_materials_mtoon.new()
const VRMC_materials_hdr_emissiveMultiplier = preload('res://addons/vrm/1.0/VRMC_materials_hdr_emissiveMultiplier.gd')
var VRMC_materials_hdr_emissiveMultiplier_inst := VRMC_materials_hdr_emissiveMultiplier.new()
const VRMC_vrm = preload('res://addons/vrm/1.0/VRMC_vrm.gd')
var VRMC_vrm_inst := VRMC_vrm.new()
const VRMC_vrm_animation = preload('res://addons/vrm/1.0/VRMC_vrm_animation.gd')
var VRMC_vrm_animation_inst := VRMC_vrm_animation.new()

@onready var pivot: Marker3D = $Sub/Camera
@onready var camera: Camera3D = $Sub/Camera/Camera3D

var _chara: Node3D
var side: int = 0
var _rect = Rect2i(0, 0, 0, 0)
var _drag: Dictionary = {
	'pressed': false,
	'valid': false,
	'position': Vector2(0, 0)
}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_window().focus_entered.connect(_on_window_focus_in)
	get_window().focus_exited.connect(_on_window_focus_out)

func _on_window_focus_in():
	get_parent().focus_child(side)
	if not mouse_passthrough_polygon.is_empty():
		return
	get_parent().raise_unless_top()

func _on_window_focus_out():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	var rect = _get_rect()
	var r: Rect2i = get_viewport().get_screen_transform() * rect
	if _rect != r:
		_rect = r
		var req: Array
		req = [
			{
				'method': 'EXECUTE',
				'event': 'UpdateMonitorRect',
				'args': [side, position.x, position.y, size.x, size.y],
			},
			{
				'method': 'EXECUTE',
				'event': 'UpdateSurfaceRect',
				'args': [side, position.x + _rect.position.x, position.y + _rect.position.y, _rect.size.x, _rect.size.y]
			},
			{
				'method': 'EXECUTE',
				'event': 'ResetBalloonPosition',
				'args': [side]
			},
			]
		if not get_tree().edited_scene_root:
			get_parent().enqueue_sstp(req)
	pivot.rotate_y(_delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag['pressed'] and _chara:
			_drag['valid'] = true
			var diff = camera.project_ray_origin(event.position) - camera.project_ray_origin(_drag['position'])
			_drag['position'] = event.position
			_chara.position.x += diff.x
			_chara.position.y += diff.y
		update_mouse_passthrough(event.position)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_drag['pressed'] = event.pressed
			if _drag['pressed']:
				_drag['position'] = event.position
			else:
				_drag['pressed'] = false
				_drag['valid'] = false

func update_mouse_passthrough(pos):
	var from = camera.project_ray_origin(pos)
	var to = from + camera.project_ray_normal(pos) * RAY_LENGTH
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	var result = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		var polygon = [
			Vector2(0, 0),
			Vector2(1, 0),
			Vector2(1, 1),
			Vector2(0, 1)
			]
		mouse_passthrough_polygon = polygon
		get_parent().raise_unless_top()
		return
	mouse_passthrough_polygon = []

func create(path: String) -> void:
	var node = load_vrm(path)
	if node:
		_chara = node
		add_child(_chara)
		_print_node(_chara)
		var skeleton: Skeleton3D = _chara.find_child('GeneralSkeleton', true, false)
		if skeleton:
			skeleton.reset_bone_poses()
			for child in skeleton.get_children():
				if child is MeshInstance3D:
					var area = Area3D.new()
					area.name = child.name + '_area'
					var shape = CollisionShape3D.new()
					shape.name = child.name + '_shape'
					shape.shape = child.mesh.create_trimesh_shape()
					skeleton.add_child(area)
					area.owner = self
					area.add_child(shape)
					shape.owner = self
					area.global_transform = child.global_transform

		#var test = load_vrm("/home/key/tmp/unyu2/unyu.glb")
		var test = false
		if test:
			var p: AnimationPlayer = test.get_node('AnimationPlayer')
			var lib = p.get_animation_library("")
			var player: AnimationPlayer = node.get_node('AnimationPlayer')
			if player:
				#player.play('RESET')
				#player.advance(0)
				player.add_animation_library("test", lib)
				player.play('test/A-Pose')
				pass

func _get_rect() -> Rect2:
	var rect = Rect2(Vector2.ZERO, Vector2.ZERO)
	for child in _chara.find_child('GeneralSkeleton', true, false).get_children():
		if child is MeshInstance3D:
			var aabb: AABB = child.get_aabb()
			for i in range(8):
				var point = aabb.get_endpoint(i)
				var pos = child.global_transform * point
				if camera.is_position_behind(pos):
					continue
				var p = camera.unproject_position(pos)
				if rect.position == Vector2.ZERO:
					rect.position = p
				else:
					rect = rect.expand(p)
	return rect

func _print_node(node: Node, indent: String = "") -> void:
	for child in node.get_children():
		printerr(indent + child.name)
		if child.get_child_count() > 0:
			_print_node(child, indent + "  ")

func load_vrm(path: String) -> Node:
	if not FileAccess.file_exists(path):
		return
	GLTFDocument.register_gltf_document_extension(VRMC_vrm_inst)
	GLTFDocument.register_gltf_document_extension(VRMC_node_constraint_inst)
	GLTFDocument.register_gltf_document_extension(VRMC_springBone_inst)
	GLTFDocument.register_gltf_document_extension(VRMC_materials_hdr_emissiveMultiplier_inst)
	GLTFDocument.register_gltf_document_extension(VRMC_materials_mtoon_inst)
	GLTFDocument.register_gltf_document_extension(VRMC_vrm_animation_inst)
	GLTFDocument.register_gltf_document_extension(vrm_inst, true)
	var gltf: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var err = gltf.append_from_file(path, state)
	if err != OK:
		GLTFDocument.unregister_gltf_document_extension(VRMC_vrm_inst)
		GLTFDocument.unregister_gltf_document_extension(VRMC_node_constraint_inst)
		GLTFDocument.unregister_gltf_document_extension(VRMC_springBone_inst)
		GLTFDocument.unregister_gltf_document_extension(VRMC_materials_hdr_emissiveMultiplier_inst)
		GLTFDocument.unregister_gltf_document_extension(VRMC_materials_mtoon_inst)
		GLTFDocument.unregister_gltf_document_extension(VRMC_vrm_animation_inst)
		GLTFDocument.unregister_gltf_document_extension(vrm_inst)
		return null
	var node: Node = gltf.generate_scene(state)
	GLTFDocument.unregister_gltf_document_extension(VRMC_vrm_inst)
	GLTFDocument.unregister_gltf_document_extension(VRMC_node_constraint_inst)
	GLTFDocument.unregister_gltf_document_extension(VRMC_springBone_inst)
	GLTFDocument.unregister_gltf_document_extension(VRMC_materials_hdr_emissiveMultiplier_inst)
	GLTFDocument.unregister_gltf_document_extension(VRMC_materials_mtoon_inst)
	GLTFDocument.unregister_gltf_document_extension(VRMC_vrm_animation_inst)
	GLTFDocument.unregister_gltf_document_extension(vrm_inst)
	return node
