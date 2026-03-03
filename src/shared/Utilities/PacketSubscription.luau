local PacketSubscription = {}

function PacketSubscription.listen(packet: any, callback: (...any) -> ()): () -> ()
	if type(packet) ~= "table" or type(callback) ~= "function" then
		return function() end
	end
	if type(packet.listen) ~= "function" or type(packet.getListeners) ~= "function" then
		return function() end
	end

	packet.listen(callback)

	return function()
		local listeners = packet.getListeners()
		if type(listeners) ~= "table" then
			return
		end

		local index = table.find(listeners, callback)
		if index then
			table.remove(listeners, index)
		end
	end
end

return PacketSubscription
