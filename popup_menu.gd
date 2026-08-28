extends PopupMenu

const SUBMENU = preload("res://popup_menu.gd")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	index_pressed.connect(_on_index_pressed)

func initialize(data) -> void:
	clear(true)
	for i in range(data.size()):
		var v = data[i]
		match v['type']:
			'submenu':
				var submenu = SUBMENU.new()
				submenu.initialize(v['list'])
				add_submenu_node_item(v['caption'], submenu)
			'item':
				add_item(v['caption'])
				set_item_metadata(i, {
					'command': v['command'],
					'args': v['args'],
				})
			'check':
				add_check_item(v['caption'])
				# TODO stub
				set_item_metadata(i, {})
			'dressup':
				var submenu = SUBMENU.new()
				add_submenu_node_item(v['caption'], submenu)
			_:
				add_separator()

func _on_index_pressed(index: int) -> void:
	var meta = get_item_metadata(index)
	if !meta or !meta.has('command') or !meta.has('args'):
		return
	var req = [
		{
			'method': 'EXECUTE',
			'event': meta['command'],
			'args': meta['args'],
		},
		]
	enqueue_sstp(req)

func enqueue_sstp(req):
	get_parent().enqueue_sstp(req)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
