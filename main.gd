extends Node

const SUB_SCENE = preload('res://sub_gltf.tscn')

var _alive: bool = true
var _sorakado_queue: Array
var _sstp_queue: Array
var _mutex: Mutex
var _sem: Semaphore
var _th_recv: Thread
var _th_send: Thread
var _focus_list: Array = [-1]

var _path: String
var _endpoint: String
var _uuid: String
var _config: Dictionary

var _mouse_position: Vector2
var _region: PackedVector2Array

var _windows: Dictionary

var _menu_rect: Rect2i = Rect2i(0, 0, 0, 0)
var _menu = preload("res://popup_menu.gd").new()

var _request_header: RegEx = RegEx.create_from_string(r'^(\w+) ([A-Z]+)/(\d+\.\d+)$')
var _reference_header: RegEx = RegEx.create_from_string(r'^(?:Reference|Argument)(0|[1-9]\d*)$')
var _response_header: RegEx = RegEx.create_from_string(r'^([A-Z]+)/(\d+\.\d+) (\d+) (.+)$')

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_mutex = Mutex.new()
	_sem = Semaphore.new()
	_th_recv = Thread.new()
	_th_send = Thread.new()
	
	get_window().focus_entered.connect(_on_window_focus_in)
	get_window().focus_exited.connect(_on_window_focus_out)

	_th_recv.start(_thread_recv)
	_th_send.start(_thread_send)

	if OS.get_name() != 'Linux' && !OS.get_name().ends_with('BSD'):
		_passthrough()

	add_child(_menu)

func _passthrough():
	if OS.get_name() == 'Windows':
		if Engine.has_singleton('MousePassthrough'):
			Engine.get_singleton('MousePassthrough').set_passthrough(get_window().get_window_id(), true)
	else:
		_region = [
			Vector2(0, 0),
			Vector2(1, 0),
			Vector2(1, 1),
			Vector2(0, 1),
		]
		get_window().mouse_passthrough_polygon = _region


func _on_window_focus_in():
	_focus_list.erase(-1)
	_focus_list.append(-1)

func _on_window_focus_out():
	pass

func _thread_recv() -> void:
	var stdout = GDPrintBinary.new()
	stdout.binary_mode()
	while true:
		var length = OS.read_buffer_from_stdin(4)
		if length.is_empty():
			break
		var data = OS.read_buffer_from_stdin(int(length.decode_u32(0)))
		if data.is_empty():
			break
		var req = _parse_request(data.get_string_from_utf8())
		var res: PackedByteArray = "SORAKADO/0.1 204 No Content\r\n\r\n".to_ascii_buffer()
		var bytes = PackedByteArray()
		bytes.resize(4)
		bytes.encode_u32(0, res.size())
		bytes.append_array(res)
		stdout.print_raw(bytes, bytes.size())
		_mutex.lock()
		_sorakado_queue.append(req)
		_mutex.unlock()
	_alive = false
	_sem.post()

func _thread_send():
	_sem.wait()
	var path: String
	_mutex.lock()
	path = _endpoint
	_mutex.unlock()
	if not _alive:
		get_tree().quit()
		return
	var socket = GDUnixClient.new()
	if socket.connect(path) != Error.OK:
		printerr('socket.connect failed')
		get_tree().quit()
		return
	while true:
		var empty: bool
		while true:
			_mutex.lock()
			empty = _sstp_queue.is_empty()
			_mutex.unlock()
			if empty and _alive:
				_sem.wait()
			else:
				break
		if not _alive:
			break
		var request_list: Array
		_mutex.lock()
		request_list = _sstp_queue.pop_front()
		_mutex.unlock()
		for req in request_list:
			var list = []
			list.append(req['method'] + ' SSTP/1.4')
			list.append('Charset: UTF-8')
			list.append('Connection: keep-alive')
			list.append('Ao: ' + _uuid)
			list.append('Sender: Sorakado_3D')
			if req.has('hide_on_204'):
				list.append('Option: nodescript,hideon204')
			else:
				list.append('Option: nodescript')
			if req['method'] == 'EXECUTE':
				list.append('Command: ' + req['event'])
			elif req['method'] == 'NOTIFY':
				list.append('Event: ' + req['event'])
			elif req['method'] == 'SEND':
				list.append('Script: ' + req['event'])
			for i in range(req['args'].size()):
				list.append('Reference' + str(i) + ': ' + str(req['args'][i]))
			list.append("\r\n")
			socket.wait_writable()
			socket.put_data("\r\n".join(list).to_utf8_buffer())
			var buffer: PackedByteArray = PackedByteArray()
			var res
			while true:
				socket.wait_readable()
				var ret = socket.get_data(socket.get_available_bytes())
				var success = ret[0]
				var data: PackedByteArray = ret[1]
				if (success != Error.OK):
					socket.close()
					return
				buffer.append_array(data)
				var tmp = buffer.get_string_from_utf8()
				if not tmp:
					continue
				res = _parse_response(tmp)
				if res.is_empty() or (res['proto']['code'] == 200 and !res['header'].has('Script') and res['content'].is_empty()):
					continue
				break
			if res['proto']['code'] == 204:
				continue
			break
	get_tree().quit()


func _read_config() -> void:
	var filename = _path + 'config.json'
	if not FileAccess.file_exists(filename):
		return
	var json = JSON.new()
	var err = json.parse(FileAccess.get_file_as_string(filename))
	if err != Error.OK:
		printerr(err)
		return
	_config = json.data

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	var queue = []
	_mutex.lock()
	while not _sorakado_queue.is_empty():
		queue.append(_sorakado_queue.pop_front())
	_mutex.unlock()
	for data in queue:
		if !data.is_empty():
			var command: String = data['header']['Command']
			var args: Dictionary = data['args']
			match command:
				'Initialize':
					_mutex.lock()
					_path = args[0]
					_mutex.unlock()
					_read_config()
				'Endpoint':
					_mutex.lock()
					_endpoint = args[0]
					_uuid = args[1]
					_mutex.unlock()
					_sem.post()
				'Create':
					var path: String = _config['model'][args[0]]['path']
					if path.contains('..'):
						continue
					var side: int = int(args[0])
					if _windows.has(side):
						continue
					var window: Window = SUB_SCENE.instantiate()
					window.hide()
					window.side = side
					window.own_world_3d = true
					add_child(window)
					window.create(_path + path)
					window.set_config(_config['model'][args[0]]['bone'], _config['pose'][args[0]])
					_windows[side] = window
				'SetSurfaceID':
					var side: int = int(args[0])
					if !_windows.has(side):
						continue
					_windows[side].setID(args[1])
				'Show':
					var side: int = int(args[0])
					if !_windows.has(side):
						continue
					_windows[side].show()
				'Hide':
					var side: int = int(args[0])
					if !_windows.has(side):
						continue
					_windows[side].hide()
				'NotifyMenuInfo':
					var json = JSON.new()
					var err = json.parse(args[0])
					if err != Error.OK:
						printerr('JSON Error: ', err, args[0])
						continue
					_menu.initialize(json.data)
					_menu.popup(_menu_rect)

func _unhandled_input(event: InputEvent) -> void:
	#printerr(event.as_text(), get_viewport().get_screen_transform())
	if event is InputEventMouseMotion:
		if OS.get_name() != 'Linux' && !OS.get_name().ends_with('BSD'):
			return
		var pos = get_viewport().get_screen_transform() * event.position
		var rect = get_viewport().get_screen_transform() * get_viewport().get_visible_rect()
		const size = 5
		const mergin = 0.001
		# need Wayland only
		_region = [
			Vector2(mergin, 0),
			Vector2(pos.x - size / 2.0, pos.y - size / 2.0 - mergin),
			Vector2(pos.x + size / 2.0, pos.y - size / 2.0),
			Vector2(pos.x + size / 2.0, pos.y + size / 2.0),
			Vector2(pos.x - size / 2.0, pos.y + size / 2.0),
			Vector2(pos.x - size / 2.0 - mergin, pos.y - size / 2.0),
			Vector2(0,mergin),
			Vector2(0, rect.size.y),
			Vector2(rect.size.x, rect.size.y),
			Vector2(rect.size.x, 0),
			Vector2(mergin, 0)
			]
		#print(_region)
		get_window().mouse_passthrough_polygon = _region
		_mouse_position = pos
		for child in get_children():
			if child.has_method('update_mouse_passthrough'):
				child.update_mouse_passthrough(_mouse_position)

func raise_unless_top() -> void:
	if OS.get_name() != 'Linux' && !OS.get_name().ends_with('BSD'):
		return
	if _focus_list.back() == -1:
		return
	get_window().grab_focus()

func focus_child(side: int) -> void:
	_focus_list.erase(side)
	_focus_list.append(side)

func _exit_tree() -> void:
	_th_recv.wait_to_finish()
	_th_send.wait_to_finish()
	printerr('sorakado_3d exiting')

func _parse_request(data: String) -> Dictionary:
	if not data.ends_with("\r\n\r\n"):
		return {}
	var protocol = {}
	var header = {}
	var args = {}
	var content = ''
	var once: bool = true
	var state: int = 0
	for line in data.split("\n"):
		line = line.trim_suffix("\r")
		if line.is_empty():
			state += 1
			continue
		if once:
			once = false
			var m = _request_header.search(line)
			if m:
				protocol['method'] = m.get_string(1)
				protocol['name'] = m.get_string(2)
				protocol['version'] = m.get_string(3)
			else:
				return {}
			continue
		if state == 1:
			content += line + "\n"
		var list = line.split(':', true, 1)
		if list.size() <= 1:
			continue
		var key: String = list[0]
		var value: String = list[1].trim_prefix(' ')
		var m = _reference_header.search(key)
		if m:
			var index = int(m.get_string(1))
			args[index] = value
		else:
			header[key] = value
	return {
		'proto': protocol,
		'header': header,
		'args': args,
		'content': content
		}

func _parse_response(data: String) -> Dictionary:
	if not data.ends_with("\r\n\r\n"):
		printerr('invalid suffix')
		return {}
	var protocol = {}
	var header = {}
	var args: Dictionary[int, String] = {}
	var content = ''
	var once: bool = true
	var state: int = 0
	for line in data.split("\n"):
		line = line.trim_suffix("\r")
		if line.is_empty():
			state += 1
		if once:
			once = false
			var m = _response_header.search(line)
			if m:
				protocol['name'] = m.get_string(1)
				protocol['version'] = m.get_string(2)
				protocol['code'] = int(m.get_string(3))
				protocol['message'] = m.get_string(4)
			else:
				printerr("invalid header:" + line)
				return {}
			continue
		if state == 1:
			content += line + "\n"
			continue
		var list = line.split(':', true, 1)
		if list.size() <= 1:
			continue
		var key: String = list[0]
		var value: String = list[1].trim_prefix(' ')
		var m = _reference_header.search(key)
		if m:
			var index = int(m.get_string(1))
			args[index] = value
		else:
			header[key] = value
	return {
		'proto': protocol,
		'header': header,
		'args': args,
		'content': content
		}

func enqueue_sstp(data):
	_mutex.lock()
	_sstp_queue.append(data)
	_mutex.unlock()
	_sem.post()

func get_leftmost(side):
	var rect = get_viewport().get_screen_transform() * get_viewport().get_visible_rect()
	var x = rect.size.x
	for key in _windows:
		if key == side or !_windows[key].adjusted():
			continue
		var r: Rect2 = _windows[key].get_rect()
		if x > r.position.x:
			x = r.position.x
	return x

func get_head_position(side):
	if !_windows.has(side):
		return null
	return _windows[side].get_head_position()

func reserve_menu_info(pos: Vector2) -> void:
	_menu_rect = Rect2i(pos.x, pos.y, 0, 0)
