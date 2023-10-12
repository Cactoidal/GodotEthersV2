extends Control

var user_address
var user_balance = "0"
var block_color

var sepolia_id = 11155111

#If the RPC is down, you can find a list at https://chainlist.org/chain/11155111
var sepolia_rpc = "https://ethereum-sepolia.publicnode.com"
#var sepolia_rpc = "https://endpoints.omniatech.io/v1/eth/sepolia/public"

var color_chain_contract = "0x7321F4C834b368b7e4eFaF5A9381F77F906AcDF1"

var confirmation_timer = 0
var tx_ongoing = false

func _ready():
	#$Send.connect("pressed", self, "send_color")
	$Send.connect("pressed", self, "new_send_color")
	$Copy.connect("pressed", self, "copy_address")
	$GetGas.connect("pressed", self, "open_faucet")
	#$Refresh.connect("pressed", self, "new_check_color")
	$Refresh.connect("pressed", self, "new_get_balance")
	#$Refresh.connect("pressed", self, "refresh_balance")
	check_keystore()
	get_address()
	new_get_balance()
	new_check_color()
	#check_color()

func _process(delta):
	if confirmation_timer > 0:
		confirmation_timer -= delta
		if confirmation_timer < 0:
			new_check_color()

func check_keystore():
	var file = File.new()
	if file.file_exists("user://keystore") != true:
		var bytekey = Crypto.new()
		var content = bytekey.generate_random_bytes(32)
		file.open("user://keystore", File.WRITE)
		file.store_buffer(content)
		file.close()

func get_address():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	user_address = ColorChain.get_address(content)
	$Address.text = user_address
	file.close()

func refresh_balance():
	ColorChain.get_balance(user_address, sepolia_rpc, self)

func copy_address():
	OS.set_clipboard(user_address)

func open_faucet():
	OS.shell_open("https://sepolia-faucet.pk910.de")
	
func send_color():
	new_get_balance()
	if tx_ongoing == false && user_balance != "0":
		var sent_color = $ColorPicker.color
		var r = int(stepify(sent_color.r,0.001) * 1000)
		var g = int(stepify(sent_color.g,0.001) * 1000)
		var b = int(stepify(sent_color.b,0.001) * 1000)
		
		if [r,g,b] != block_color:
			
			print("Sending color:")
			print([r,g,b])
		
			var file = File.new()
			file.open("user://keystore", File.READ)
			var content = file.get_buffer(32)
			file.close()
			#var success = ColorChain.new_send_color(content, sepolia_id, color_chain_contract, sepolia_rpc, r, g, b)
			var success = ColorChain.send_color(content, sepolia_id, color_chain_contract, sepolia_rpc, r, g, b)
			if success:
				tx_ongoing = true
				confirmation_timer = 8
				$Send.text = "Confirming..."
			else:
				$Send.text = "TX ERROR"
		else:
			$Send.text = "Error (Pick New Color)"
			

func check_color():
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var success = ColorChain.get_color(content, sepolia_id, color_chain_contract, sepolia_rpc, self)
	if success:
		pass
	else:
		confirmation_timer = 4



#Called from Rust	

func set_color(var chain_color):
	var new_color = parse_json(chain_color)
	print("Raw JSON:")
	print(new_color)
	
	var compare = [new_color["r"].hex_to_int(), new_color["g"].hex_to_int(), new_color["b"].hex_to_int()]
	
	if compare != block_color:
		print("New Color:")
		print(compare)
		block_color = compare.duplicate()
		var material_color = Color(float(compare[0]) / 1000, float(compare[1]) / 1000, float(compare[2]) / 1000, 1)
		$Block.get_active_material(0).albedo_color = material_color
		confirmation_timer = 0
		tx_ongoing = false
		$Send.text = "Send Color"
	else:
		confirmation_timer = 4

func set_balance(var balance):
	user_balance = balance
	$GasBalance.text = balance







# # #    N E W    # # # 

var http_request_delete_balance
var http_request_delete_tx_read
var http_request_delete_tx_write

func new_get_balance():
	var http_request = HTTPRequest.new()
	$Container.add_child(http_request)
	http_request_delete_balance = http_request
	http_request.connect("request_completed", self, "get_balance_attempted")
	
	$GasBalance.text = "Refreshing..."
	
	var tx = {"jsonrpc": "2.0", "method": "eth_getBalance", "params": [user_address, "latest"], "id": 7}
	
	var error = http_request.request(sepolia_rpc, 
	[], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))
	

func get_balance_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())
	
	if response_code == 200:
		var balance = String(get_result["result"].hex_to_int())
		user_balance = balance
		$GasBalance.text = balance
	else:
		$GasBalance.text = "CHECK RPC"
	http_request_delete_balance.queue_free()




func new_check_color():
	var http_request = HTTPRequest.new()
	$Container.add_child(http_request)
	http_request_delete_tx_read = http_request
	http_request.connect("request_completed", self, "check_color_attempted")
	
	var file = File.new()
	file.open("user://keystore", File.READ)
	var content = file.get_buffer(32)
	file.close()
	var calldata = ColorChain.new_get_color(content, sepolia_id, color_chain_contract, sepolia_rpc)
	
	var tx = {"jsonrpc": "2.0", "method": "eth_call", "params": [{"to": color_chain_contract, "input": calldata}, "latest"], "id": 7}
	
	var error = http_request.request(sepolia_rpc, 
	[], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))


func check_color_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())

	if response_code == 200:
		
		var raw_struct = get_result.duplicate()["result"]
		raw_struct.erase(0,2)

		var _r = raw_struct.substr(0,64)
		var _g = raw_struct.substr(64, 64)
		var _b = raw_struct.substr(128,64)

		var compare = []
		
		for color_value in [_r, _g, _b]:
			var padding_length = 0
			for digit in color_value:
				if digit == "0":
					padding_length += 1
				else:
					break
			color_value.erase(0,padding_length)
			compare.push_back( ("".join(["0x", color_value])).hex_to_int() )
		
		
#		for color_value in [_r, _g, _b]:
#			color_value.erase(0,61)
#			if color_value[0] == "0":
#				color_value.erase(0,1)
#			compare.push_back( ("".join(["0x", color_value])).hex_to_int() )

		if compare != block_color:
			print("New Color:")
			print(compare)
			block_color = compare.duplicate()
			var material_color = Color(float(compare[0]) / 1000, float(compare[1]) / 1000, float(compare[2]) / 1000, 1)
			$Block.get_active_material(0).albedo_color = material_color
			confirmation_timer = 0
			tx_ongoing = false
			$Send.text = "Send Color"
		else:
			confirmation_timer = 4
	
	else:
		$Send.text = "CHECK RPC"

	http_request_delete_tx_read.queue_free()




func new_send_color():
	
	new_get_balance()
	if tx_ongoing == false && user_balance != "0":
		var sent_color = $ColorPicker.color
		var r = int(stepify(sent_color.r,0.001) * 1000)
		var g = int(stepify(sent_color.g,0.001) * 1000)
		var b = int(stepify(sent_color.b,0.001) * 1000)
		
		if [r,g,b] != block_color:
			
			print("Sending color:")
			print([r,g,b])
	
	
			var file = File.new()
			file.open("user://keystore", File.READ)
			var content = file.get_buffer(32)
			file.close()
			ColorChain.new_send_color(content, sepolia_id, color_chain_contract, sepolia_rpc, r, g, b, self)
		
		else:
			$Send.text = "Error (Pick New Color)"

func set_signed_data(var signature):
	var http_request = HTTPRequest.new()
	$Container.add_child(http_request)
	http_request_delete_tx_write = http_request
	http_request.connect("request_completed", self, "send_color_attempted")
	
	var signed_data = "".join(["0x", signature])
	
	var tx = {"jsonrpc": "2.0", "method": "eth_sendRawTransaction", "params": [signed_data], "id": 7}
	print(signed_data)
	var error = http_request.request(sepolia_rpc, 
	[], 
	true, 
	HTTPClient.METHOD_POST, 
	JSON.print(tx))


func send_color_attempted(result, response_code, headers, body):
	
	var get_result = parse_json(body.get_string_from_ascii())

	print(get_result)

	if response_code == 200:
		tx_ongoing = true
		confirmation_timer = 8
		$Send.text = "Confirming..."
	else:
		$Send.text = "TX ERROR"
	
	http_request_delete_tx_write.queue_free()
