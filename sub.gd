extends Window

var vrm = preload('res://addons/vrm/vrm_extension.gd')

@onready var camera: Camera3D = $Sub/Camera/Camera3D

var _chara: Node3D
var side: int = 0
var _rect = Rect2i(0, 0, 0, 0)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	create("/home/key/tmp/chara.vrm")
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
		get_parent().enqueue_sstp(req)

func create(path: String) -> void:
	var node = load_vrm_runtime(path)
	if node:
		_print_node(node)
		var skeleton: Skeleton3D = node.find_child('GeneralSkeleton', true, false)
		if skeleton:
			skeleton.clear_bones_global_pose_override()
			skeleton.force_update_all_bone_transforms()
			skeleton.reset_bone_poses()	
		var player: AnimationPlayer = node.get_node('AnimationPlayer')
		if player:
			pass
			#player.play('happy')
		_chara = node
		add_child(_chara)

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
		#print(indent + child.name)
		if child.get_child_count() > 0:
			_print_node(child, indent + "  ")

func load_vrm_runtime(path: String) -> Node:
	if not FileAccess.file_exists(path):
		return
	var conv = GLTFDocumentExtensionConvertImporterMesh.new()
	GLTFDocument.register_gltf_document_extension(conv, true)
	var vrm_extension: GLTFDocumentExtension = vrm.new()
	GLTFDocument.register_gltf_document_extension(vrm_extension, true)
	var gltf: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var err = gltf.append_from_file(path, state)
	if err != OK:
		GLTFDocument.unregister_gltf_document_extension(vrm_extension)
		return null
	var node: Node = gltf.generate_scene(state)
	GLTFDocument.unregister_gltf_document_extension(vrm_extension)
	return node
