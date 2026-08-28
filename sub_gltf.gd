extends Window

const RAY_LENGTH = 10

@onready var pivot: Marker3D = $Sub/Camera
@onready var camera: Camera3D = $Sub/Camera/Camera3D

var _chara: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _bone_config: Dictionary
var _pose_config: Dictionary
var _shape: Dictionary = {}
var _id: String
var _maximized: bool = false
var _adjust: bool

var side: int = 0
var _rect = Rect2i(0, 0, 0, 0)
var _drag: Dictionary = {
	'pressed': false,
	'valid': false,
	'position': Vector2(0, 0)
}
var _click_through = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	focus_entered.connect(_on_window_focus_in)
	focus_exited.connect(_on_window_focus_out)
	size_changed.connect(_on_window_size_changed)

func _on_window_focus_in():
	get_parent().focus_child(side)
	if mouse_passthrough_polygon.is_empty():
		return
	get_parent().raise_unless_top()

func _on_window_focus_out():
	pass

func _on_window_size_changed() -> void:
	if mode == MODE_MAXIMIZED:
		_maximized = true
		_adjust = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if !visible:
		return
	var rect = get_rect()
	if _adjust:
		_adjust = false
		_adjust_position(rect)
	if _skeleton and _pose_config[_id].has('lookAt'):
		var s: int = _pose_config[_id]['lookAt']
		var pos = get_parent().get_head_position(s)
		_look_at(pos)
	var r: Rect2i = rect
	if _rect != r:
		_rect = r
		_notify_update_rect(_rect)
	if OS.get_name() != 'Linux' && !OS.get_name().ends_with('BSD'):
		var pos = get_screen_transform() * get_mouse_position()
		update_mouse_passthrough(pos)

func _adjust_position(rect):
	var x = get_parent().get_leftmost(side)
	x = x - rect.size.x
	if x < 0:
		x = 0
	var v = get_screen_transform().inverse() * Vector2(x, 0)
	var pos: Vector3 = camera.project_ray_origin(v)
	_chara.position.x = pos.x

func _look_at(pos):
	if !pos:
		return
	var hips: int = _skeleton.find_bone(_bone_config['hips'])
	var head: int = _skeleton.find_bone(_bone_config['head'])
	if hips == -1 or head == -1:
		return
	var target_pos: Vector3 = _skeleton.global_transform.inverse() * pos

	if true:
		var hips_global_pose: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(hips)
		var target_hips_pos: Vector3 = Vector3(target_pos.x, target_pos.y, target_pos.z + 10)
		var new_transform: Transform3D = hips_global_pose.looking_at(target_hips_pos, Vector3.UP, true)
		var new_pose = _skeleton.global_transform.inverse() * new_transform
		_skeleton.set_bone_global_pose_override(hips, new_pose, 1.0)

	if true:
		var head_global_pose: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(head)
		var target_head_pos: Vector3 = Vector3(target_pos.x, target_pos.y, target_pos.z + 10)
		var new_transform: Transform3D = head_global_pose.looking_at(target_head_pos, Vector3.UP, true)
		var new_pose = _skeleton.global_transform.inverse() * new_transform
		_skeleton.set_bone_global_pose_override(head, new_pose, 1.0)

func _notify_update_rect(rect):
	var req: Array = [
		{
			'method': 'EXECUTE',
			'event': 'UpdateMonitorRect',
			'args': [side, position.x, position.y, size.x, size.y],
		},
		{
			'method': 'EXECUTE',
			'event': 'UpdateSurfaceRect',
			'args': [side, position.x + rect.position.x, position.y + rect.position.y, rect.size.x, rect.size.y]
		},
		{
			'method': 'EXECUTE',
			'event': 'ResetBalloonPosition',
			'args': [side]
		},
		]
	get_parent().enqueue_sstp(req)

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
		var pos = get_screen_transform() * event.position
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_drag['pressed'] = event.pressed
				if _drag['pressed']:
					_drag['position'] = event.position
				else:
					_drag['pressed'] = false
					_drag['valid'] = false
			MOUSE_BUTTON_RIGHT:
				if !event.pressed:
					get_parent().reserve_menu_info(pos)
		var table = {
			MOUSE_BUTTON_LEFT: '0',
			MOUSE_BUTTON_RIGHT: '1',
			MOUSE_BUTTON_MIDDLE: '2',
		}
		if table.has(event.button_index):
			if event.pressed:
				var args: Array = [str(int(pos.x)), str(int(pos.y)), '0', side, '', table[event.button_index]]
				var req: Array = [
					{
						'method': 'NOTIFY',
						'event': 'OnMouseDown',
						'args': args,
					},
					]
				get_parent().enqueue_sstp(req)
			elif event.double_click:
				var args: Array = [str(int(pos.x)), str(int(pos.y)), '0', side, '', table[event.button_index]]
				var req: Array = [
					{
						'method': 'NOTIFY',
						'event': 'OnMouseDoubleClick',
						'args': args,
					},
					]
				get_parent().enqueue_sstp(req)
			else:
				var args: Array = [str(int(pos.x)), str(int(pos.y)), '0', side, '', table[event.button_index]]
				var req: Array = [
					{
						'method': 'NOTIFY',
						'event': 'OnMouseUp',
						'args': args,
					},
					{
						'method': 'NOTIFY',
						'event': 'OnMouseClick',
						'args': args,
					},
					]
				get_parent().enqueue_sstp(req)

func update_mouse_passthrough(pos):
	var from = camera.project_ray_origin(pos)
	var to = from + camera.project_ray_normal(pos) * RAY_LENGTH
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	var result = camera.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		if _click_through:
			return
		_click_through = true
		if OS.get_name() == 'Windows':
			pass
		else:
			var polygon = [
				Vector2(0, 0),
				Vector2(1, 0),
				Vector2(1, 1),
				Vector2(0, 1)
				]
			mouse_passthrough_polygon = polygon
		get_parent().raise_unless_top()
	else:
		if not _click_through:
			return
		_click_through = false
		if OS.get_name() == 'Windows':
			pass
		else:
			mouse_passthrough_polygon = []

func create(path: String) -> void:
	var node = load_vrm(path)
	if node:
		_chara = node
		add_child(_chara)
		_print_node(_chara)
		_skeleton = _chara.find_child('Skeleton3D', true, false)
		if _skeleton:
			_skeleton.reset_bone_poses()
			for child in _skeleton.get_children():
				if child is MeshInstance3D:
					var area = Area3D.new()
					area.name = child.name + '_area'
					var shape = CollisionShape3D.new()
					shape.name = child.name + '_shape'
					shape.shape = child.mesh.create_trimesh_shape()
					_skeleton.add_child(area)
					area.owner = self
					area.add_child(shape)
					shape.owner = self
					area.global_transform = child.global_transform
					for i in child.get_blend_shape_count():
						if !_shape.has(child.name):
							_shape[child.name] = {}
						printerr("shape: ", child.mesh.get_blend_shape_name(i))
					for i in child.mesh.get_surface_count():
						var mat = child.get_active_material(i) as ShaderMaterial
						if mat:
							printerr('material: ', mat.resource_name)

		var player: AnimationPlayer = node.get_node_or_null('AnimationPlayer')
		if player:
			_player = player
			for item in _player.get_animation_list():
				printerr(item)
			setID('__default__')

func get_rect() -> Rect2:
	var rect = Rect2(Vector2.ZERO, Vector2.ZERO)
	for child in _chara.find_child('Skeleton3D', true, false).get_children():
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
	return get_viewport().get_screen_transform() * rect

func _print_node(node: Node, indent: String = "") -> void:
	for child in node.get_children():
		printerr(indent + child.name)
		if child.get_child_count() > 0:
			_print_node(child, indent + "  ")

func load_vrm(path: String) -> Node:
	if not FileAccess.file_exists(path):
		return
	var gltf: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var err = gltf.append_from_file(path, state)
	if err != OK:
		return null
	var node: Node = gltf.generate_scene(state)
	return node

func set_config(bone, pose):
	_bone_config = bone
	_pose_config = pose

func setID(id):
	if !_pose_config.has(id):
		return
	if !_player:
		return
	if !_skeleton:
		return
	_id = id
	if _id == '-1':
		_chara.hide()
		return
	else:
		_chara.show()
	_player.stop()
	_skeleton.reset_bone_poses()
	_clear_blend_shapes()
	var base = _pose_config[id]['base']
	for item in base:
		match item['type']:
			'animation':
				_player.play(item['name'])
			'shape':
				var a = item['name'].split('/', true, 1)
				if a.size() != 2:
					continue
				var node = _skeleton.find_child(a[0], true, false) as MeshInstance3D
				if !node:
					continue
				var index = node.find_blend_shape_by_name(a[1])
				if index == -1:
					continue
				node.set_blend_shape_value(index, item['factor'])

func _clear_blend_shapes():
	for child in _skeleton.get_children():
		if child is not MeshInstance3D:
			continue
		var item = child as MeshInstance3D
		for i in item.get_blend_shape_count():
			item.set_blend_shape_value(i, 0.0)

func adjusted():
	return _maximized and !_adjust

func get_head_position():
	if !_skeleton:
		return null
	var head: int = _skeleton.find_bone(_bone_config['head'])
	if head == -1:
		return null
	var pose: Transform3D = _skeleton.get_bone_global_pose(head)
	return _skeleton.to_global(pose.origin)
