extends Node
## 1v1 over a phone hotspot (or the same Wi-Fi).
## One phone HOSTS (hotspot ON), the other JOINS (connected to that hotspot).
## Transport: ENet. Discovery: UDP broadcast beacon + gateway-IP guess + manual IP.
## Each phone is authoritative for its own movement and health; hits are sent to the victim.

signal status(text: String)
signal join_failed
signal peer_lost

const PORT := 7777
const DISC_PORT := 7778
const MAGIC := "APEXARENA_V1"
const CFG_PATH := "user://net.cfg"
const SEND_RATE := 1.0 / 30.0

var game
var session := false      # a host or client session exists
var is_host := false
var peer_ready := false   # both phones are connected
var last_ip := "192.168.43.1"

var _tx: PacketPeerUDP
var _rx: PacketPeerUDP
var _beacon_t := 0.0
var _auto := false
var _auto_t := 0.0
var _joining := false
var _join_t := 0.0
var _send_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_conn_failed)
	multiplayer.server_disconnected.connect(_on_server_lost)
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		last_ip = String(cf.get_value("net", "ip", last_ip))

func _save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("net", "ip", last_ip)
	cf.save(CFG_PATH)

# ------------------------------------------------------------------ addresses
func local_ips() -> Array[String]:
	var wifi: Array[String] = []
	var other: Array[String] = []
	for a in IP.get_local_addresses():
		var s := String(a)
		if s.contains(":") or s.begins_with("127.") or s.begins_with("169.254.") or s == "0.0.0.0":
			continue
		if s.begins_with("192.168."):
			if not wifi.has(s):
				wifi.append(s)
		elif not other.has(s):
			other.append(s)
	return wifi + other

func _guess_hosts() -> Array[String]:
	var out: Array[String] = []
	for ip in local_ips():
		var p := ip.split(".")
		if p.size() == 4:
			var g := "%s.%s.%s.1" % [p[0], p[1], p[2]]
			if g != ip and not out.has(g):
				out.append(g)
	return out

# ------------------------------------------------------------------ session control
func host() -> void:
	close()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(PORT, 1)
	if err != OK:
		status.emit("Cannot start host (error %d).\nClose other games and try again." % err)
		return
	multiplayer.multiplayer_peer = p
	session = true
	is_host = true
	_tx = PacketPeerUDP.new()
	_tx.set_broadcast_enabled(true)
	_beacon_t = 1.0
	var txt := "WAITING FOR FRIEND...\nKeep your hotspot ON. Friend taps JOIN GAME."
	var ips := local_ips()
	if not ips.is_empty():
		var shown := ""
		for i in mini(ips.size(), 3):
			shown += ("   " if i > 0 else "") + ips[i]
		txt += "\nYour IP: " + shown
	status.emit(txt)

func join_auto() -> void:
	close()
	session = true
	_rx = PacketPeerUDP.new()
	if _rx.bind(DISC_PORT) != OK:
		_rx = null
	_auto = true
	_auto_t = 0.0
	status.emit("SEARCHING FOR HOST...\nHost must tap HOST GAME first.\nBoth phones: same hotspot / Wi-Fi.")

func join(ip: String) -> void:
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		status.emit("Invalid IP address.")
		return
	_close_udp()
	_auto = false
	_reset_peer()
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, PORT)
	if err != OK:
		status.emit("Cannot connect (error %d)." % err)
		close()
		join_failed.emit()
		return
	multiplayer.multiplayer_peer = p
	session = true
	is_host = false
	_joining = true
	_join_t = 0.0
	last_ip = ip
	status.emit("CONNECTING TO %s ..." % ip)

func close() -> void:
	session = false
	is_host = false
	peer_ready = false
	_auto = false
	_joining = false
	_close_udp()
	_reset_peer()

func _reset_peer() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

func _close_udp() -> void:
	if _rx != null:
		_rx.close()
		_rx = null
	if _tx != null:
		_tx.close()
		_tx = null

func _fail(msg: String) -> void:
	close()
	status.emit(msg)
	join_failed.emit()

# ------------------------------------------------------------------ connection events
func _on_peer_connected(_id: int) -> void:
	if not session or not is_host:
		return
	peer_ready = true
	_close_udp()
	status.emit("FRIEND CONNECTED! Starting...")
	if game:
		game.net_host_ready()

func _on_peer_disconnected(_id: int) -> void:
	if not session:
		return
	peer_ready = false
	peer_lost.emit()

func _on_connected() -> void:
	if not session or not _joining:
		return
	_joining = false
	peer_ready = true
	_save_cfg()
	status.emit("CONNECTED!\nWaiting for host to start...")

func _on_conn_failed() -> void:
	if not _joining:
		return
	_fail("COULD NOT CONNECT.\nCheck you are on the host's hotspot, the host tapped HOST GAME,\nor type the host IP below.")

func _on_server_lost() -> void:
	if not session:
		return
	peer_ready = false
	peer_lost.emit()

# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if _tx != null and is_host and not peer_ready:
		_beacon_t += delta
		if _beacon_t >= 1.0:
			_beacon_t = 0.0
			_send_beacon()
	if _auto:
		_auto_t += delta
		if _rx != null:
			while _rx.get_available_packet_count() > 0:
				var pkt := _rx.get_packet()
				var ip := _rx.get_packet_ip()
				if pkt.get_string_from_utf8() == MAGIC and ip != "":
					join(ip)
					return
		if _auto_t >= 3.0:
			var g := _guess_hosts()
			if g.is_empty():
				_fail("NO WI-FI FOUND.\nConnect to the host's hotspot first.")
			else:
				join(g[0])
			return
	if _joining:
		_join_t += delta
		if _join_t >= 7.0:
			_fail("COULD NOT CONNECT.\nCheck you are on the host's hotspot, the host tapped HOST GAME,\nor type the host IP below.")

func _send_beacon() -> void:
	var data := MAGIC.to_utf8_buffer()
	var dests: Array[String] = ["255.255.255.255"]
	for ip in local_ips():
		var p := ip.split(".")
		if p.size() == 4:
			dests.append("%s.%s.%s.255" % [p[0], p[1], p[2]])
	for d in dests:
		_tx.set_dest_address(d, DISC_PORT)
		_tx.put_packet(data)

func _physics_process(delta: float) -> void:
	if not _can_send() or game == null or not game.online or game.state == 0:
		return
	_send_t += delta
	if _send_t < SEND_RATE:
		return
	_send_t = 0.0
	var p = game.player
	rpc("rpc_state", p.global_position, p.rotation.y, p.head.rotation.x, p.hspeed,
		p.dead, p.sliding, p.health, p.invuln > 0.0)

func _can_send() -> bool:
	return session and peer_ready

# ------------------------------------------------------------------ outgoing
func send_start(pair: int) -> void:
	if _can_send():
		rpc("rpc_start", pair)

func send_end(h_you: int, h_foe: int) -> void:
	if _can_send():
		rpc("rpc_end", h_you, h_foe)

func send_hit(amount: float, y_off: float) -> void:
	if _can_send():
		rpc("rpc_hit", amount, y_off)

func send_scored() -> void:
	if _can_send():
		rpc("rpc_scored")

func send_tracer(a: Vector3, b: Vector3) -> void:
	if _can_send():
		rpc("rpc_tracer", a, b)

# ------------------------------------------------------------------ incoming
@rpc("authority", "call_remote", "reliable")
func rpc_start(pair: int) -> void:
	if game:
		game.on_net_start(pair)

@rpc("authority", "call_remote", "reliable")
func rpc_end(h_you: int, h_foe: int) -> void:
	if game:
		game.on_net_end(h_you, h_foe)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_state(pos: Vector3, yaw: float, pitch: float, spd: float, is_dead: bool,
		is_slide: bool, hp: float, inv: bool) -> void:
	if game and game.online and game.remote:
		game.remote.apply_state(pos, yaw, pitch, spd, is_dead, is_slide, hp, inv)

@rpc("any_peer", "call_remote", "reliable")
func rpc_hit(amount: float, y_off: float) -> void:
	if game and game.online:
		game.on_net_hit(amount, y_off)

@rpc("any_peer", "call_remote", "reliable")
func rpc_scored() -> void:
	if game and game.online:
		game.on_net_scored()

@rpc("any_peer", "call_remote", "unreliable")
func rpc_tracer(a: Vector3, b: Vector3) -> void:
	if game and game.online and game.fx:
		game.fx.tracer(a, b)
