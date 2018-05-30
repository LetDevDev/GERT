-- GERT v1.0.2 - DEV
local GERTi = {}
local component = require("component")
local computer = require("computer")
local event = require("event")
local serialize = require("serialization")

GERTi.interfaces = {}
GERTi.defualt_route = 0
GERTi.routes = {"FEFE00/FFFF00" = 0xFEFF01}	 --address/subnet = target  Target Gateway 
GERTi.drivers = {}

local handler = {}

local resolve = function(dest)
	for k,v in pairs(GERTi.interfaces) do
		if isSameSubnet(dest,v.address,v.subnet) then
      return k
    end
	end
  for k,v in pairs(GERTi.routes) do
    if isSameSubnet(dest,tonumber("0x"..k:sub(1,6)),tonumber("0x"..k:sub(8,13))) then
      for l,w in pairs(GERTi.interfaces) do
		    if isSameSubnet(v,w.address,w.subnet) then
          return l, w.address
        end
	    end
    end
  end
  for k,v in pairs(GERTi.interfaces) do
		if isSameSubnet(GERTi.default_route,v.address,v.subnet) then
      return k, v.address
    end
	end
end

local isSameSubnet = function(first,second,mask)
    return (first & mask) == (second & mask)
end

GERTi.utils = {
  resolve = resolve,
	isSameSubnet = isSameSubnet,
  getBroadcastAddr = function(interface)
    return (~interface.subnet) | interface.addr
  end
}

local function sortTable(elementOne, elementTwo)
	return (tonumber(elementOne["tier"]) < tonumber(elementTwo["tier"]))
end

-- this function adds a handler for a set time in seconds, or until that handler returns a truthful value (whichever comes first)
local function addTempHandler(timeout, code, cb, cbf)
	local disable = false
	local function cbi(...)
		if disable then return end
		local evn, rc, sd, pt, dt, code2 = ...
		if code ~= code2 then return end
		if cb(...) then
			disable = true
			return false
		end
	end
	event.listen("gert_message", cbi)
	event.timer(timeout, function ()
		event.ignore("gert_message", cbi)
		if disable then return end
		cbf()
	end)
end
-- Like a sleep, but it will exit early if a modem_message is received and then something happens.
local function waitWithCancel(timeout, cancelCheck)
	-- Wait for the response.
	local now = computer.uptime()
	local deadline = now + timeout
	while now < deadline do
		event.pull(deadline - now, "gert_message")
		-- The listeners were called, so as far as we're concerned anything cancel-worthy should have happened
		local response = cancelCheck()
		if response then return response end
		now = computer.uptime()
	end
	-- Out of time
	return cancelCheck()
end

local function storeConnection(origination, destination, doEvent, connectionID, originGAddress)
	connections[connectDex] = {}
	connections[connectDex]["destination"] = destination
	connections[connectDex]["origination"] = origination
	connections[connectDex]["originationGAddress"] = originGAddress
	connections[connectDex]["data"] = {}
	connections[connectDex]["dataDex"] = 1
	connections[connectDex]["connectionID"] = (connectionID or connectDex)
	connections[connectDex]["doEvent"] = (doEvent or false)
	connectDex = connectDex + 1
	return connectionID or (connectDex-1)
end

-- Stores data inside a connection for use by a program
local function storeData(connectionID, data, origination)
	local connectNum
	for key, value in pairs(connections) do
		if value["connectionID"] == connectionID and value["origination"] == origination then
			connectNum = key
			break
		end
	end
	local dataNum = connections[connectNum]["dataDex"]

	if dataNum >= 20 then
		table.remove(connections[connectNum]["data"], 1)
	end

	connections[connectNum]["data"][dataNum]=data
	connections[connectNum]["dataDex"] = math.min(dataNum + 1, 20)
	if connections[connectNum]["doEvent"] then
		computer.pushSignal("GERTData", connections[connectNum]["originationGAddress"], connectionID)
	end
	return true
end

-- Basic transmit function, does some route resolution unless forced to use an interface
GERTi.send = function(source,dest,proto,data)
  if type(proto) == "string" and data == nil then 
    data = proto
    proto = dest
    dest = source
    
    local interface, via = resolve(dest)
    if GERTi.interfaces[interface] then
      GERTi.interfaces[interface]:send(dest,proto,data,via)
    end
  else
  
    for k,v in pairs(GERTi.interfaces) do
      if v.addr == source then
        return v:send(dest,proto,data)
      end
    end
    
  end
end

--[[handler["CloseConnection"] = function(sendingModem, port, code, connectionID, destination, origin)
	for key, value in pairs(paths) do
		if value["destination"] == destination and value["origination"] == origin then
			if value["nextHop"] ~= .address then
				transmitInformation(value["nextHop"], value["port"], "CloseConnection", connectionID, destination, origin)
			end
			table.remove(paths, key)
			break
		end
	end
	for key, value in pairs(connections) do
		if value["connectionID"] == connectionID and value["origination"] == origin then
			table.remove(connections, key)
			break
		end
	end
end

handler["DATA"] = function (sendingModem, port, code, data, destination, origination, connectionID)
	-- Attempt to determine if host is the destination, else send it on to next hop.
	for key, value in pairs(paths) do
		if value["destination"] == destination and value["origination"] == origination then
			if value["destination"] == .address then
				return storeData(connectionID, data, origination)
			else
				return transmitInformation(value["nextHop"], value["port"], "DATA", data, destination, origination, connectionID)
			end
		end
	end
	return false
end

-- opens a route using the given information, used in handler["OPENROUTE"] and GERTi.openSocket
local function routeOpener(destination, origination, beforeHop, nextHop, receivedPort, transmitPort, outbound, connectionID, originGAddress)
	local function sendOKResponse(isDestination)
		transmitInformation(beforeHop, receivedPort, "ROUTE OPEN", destination, origination)
		if isDestination then
			storePath(origination, destination, nextHop, transmitPort)
			local newID = storeConnection(origination, destination, false, connectionID, originGAddress)
			return computer.pushSignal("GERTConnectionID", originGAddress, newID)
		else
			return storePath(origination, destination, nextHop, transmitPort)
		end
	end
	if .address ~= destination then
		local connect1 = 0
		transmitInformation(nextHop, transmitPort, "OPENROUTE", destination, nextHop, origination, outbound, connectionID, originGAddress)
		addTempHandler(3, "ROUTE OPEN", function (eventName, recv, sender, port, distance, code, pktDest, pktOrig)
			if (destination == pktDest) and (origination == pktOrig) then
				connect1 = sendOKResponse(false)
				return true -- This terminates the wait
			end
		end, function () end)
		waitWithCancel(3, function () return response end)
		return connect1
	end
	return sendOKResponse(true)
end

handler["OPENROUTE"] = function (sendingModem, port, code, destination, intermediary, origination, outbound, connectionID, originGAddress)
	-- Attempt to determine if the intended destination is this computer
	if destination == modem.address then
		return routeOpener(modem.address, origination, sendingModem, modem.address, port, port, outbound, connectionID, originGAddress)
	end

	-- attempt to check if destination is a neighbor to this computer, if so, re-transmit OPENROUTE message to the neighbor so routing can be completed
	for key, value in pairs(neighbors) do
		if value["address"] == destination then
			return routeOpener(destination, origination, sendingModem, neighbors[key]["address"], port, neighbors[key]["port"], outbound, connectionID, originGAddress)
		end
	end

	-- if it is not a neighbor, and no intermediary was found, then contact parent to forward indirect connection request
	if intermediary == modem.address then
		return routeOpener(destination, origination, sendingModem, neighbors[1]["address"], port, neighbors[1]["port"], outbound, connectionID, originGAddress)
	end

	-- If an intermediary is found (likely because MNC was already contacted), then attempt to forward request to intermediary
	for key, value in pairs(neighbors) do
		if value["address"] == intermediary then
			return routeOpener(destination, origination, sendingModem, intermediary, port, neighbors[key]["port"], outbound, connectionID, originGAddress)
		end
	end
end

handler["RemoveNeighbor"] = function (sendingModem, port, code, origination)
	removeNeighbor(origination)
	transmitInformation(neighbors[1]["address"], neighbors[1]["port"], "RemoveNeighbor", origination)
end

handler["RegisterNode"] = function (sendingModem, sendingPort, code, origination, tier, serialTable)
	transmitInformation(neighbors[1]["address"], neighbors[1]["port"], "RegisterNode", origination, tier, serialTable)
	addTempHandler(3, "RegisterComplete", function (eventName, recv, sender, port, distance, code, targetMA, iResponse)
		if targetMA == origination then
			transmitInformation(sendingModem, sendingPort, "RegisterComplete", targetMA, iResponse)
			return true
		end
	end, function () end)
end

handler["ResolveAddress"] = function (sendingModem, port, code, gAddress)
	transmitInformation(neighbors[1]["address"], neighbors[1]["port"], "ResolveAddress", gAddress)
	addTempHandler(3, "ResolveComplete", function(_, _, sender, _, _, code, realAddress)
		transmitInformation(sendingModem, port, "ResolveComplete", realAddress)
		end, function() end)
end

handler["RETURNSTART"] = function (sendingModem, port, code, tier)
	-- Store neighbor based on the returning tier
	storeNeighbors(sendingModem, port, tier)
end]]

local function receivePacket(eventName, recv, sender, protocol, data)
	-- Attempt to call a handler function to further process the packet
	if handler[protocol] ~= nil then
		handler[code](sendingModem, port, code, ...)
	end
end

-- Begin startup ---------------------------------------------------------------------------------------------------------------------------
-- transmit broadcast to check for neighboring GERTi enabled computers
--[[if tunnel then
	tunnel.send("AddNeighbor")
end
if modem then
	modem.broadcast(4378, "AddNeighbor")
end]]

-- Register event listener to receive packets from now on
event.listen("gert_message", receivePacket)

-- Wait a while to build the neighbor table.
--os.sleep(2)

-- forward neighbor table up the line
--[[local serialTable = serialize.serialize(neighbors)
local mncUnavailable = true
if serialTable ~= "{}" then
	-- Even if there is no neighbor table, still register to try and form a network regardless

	transmitInformation(neighbors[1]["address"], neighbors[1]["port"], "RegisterNode", addr, tier, serialTable)
	addTempHandler(3, "RegisterComplete", function (_, _, _, _, _, code, targetMA, iResponse)
		if targetMA == addr then
			iAddress = iResponse
			return true
		end
	end, function () end)
	if waitWithCancel(5, function () return iAddress end) then
		mncUnavailable = false
	end
end
if mncUnavailable then
	print("Unable to contact the MNC. Functionality will be impaired.")
end

-- Override computer.shutdown to allow for better network leaves
local function safedown()
	if tunnel then
		tunnel.send("RemoveNeighbor", tunnel.address)
	end
	if modem then
		modem.broadcast(4378, "RemoveNeighbor", modem.address)
	end
	for key, value in pairs(connections) do
		--handler["CloseConnection"](.address, 4378, "CloseConnection", value["connectionID"], value["destination"], value["origination"])
	end
end
event.listen("shutdown", safedown)]]

-- startup procedure is now complete ------------------------------------------------------------------------------------------------------------
-- begin procedure to allow for data transmission

-- Writes data to an opened connection
local function writeData(self, data)
	return GERTi.send(self.origination,self.destination, 127, self.ID..'\\'..data)
end

-- Reads data from an opened connection
local function readData(self)
	if self.incDex then
		local data = connections[self.incDex]["data"]
		connections[self.incDex]["data"] = {}
		connections[self.incDex]["dataDex"] = 1
		return data
	--[[else
		for key, value in pairs(connections) do
			if value["destination"] == self.origination and value["connectionID"] == self.ID and value["origination"] == self.destination then
				self.incDex = key
				if self.doEvent then
					value["doEvent"] = true
				end
				return self:read()
			end
		end
		return {}]]
	end
end

local function closeConnection(self)
	transmitInformation(self.nextHop, self.outPort, "CloseConnection", self.ID, self.destination, self.origination)
	handler["CloseConnection"](.address, 4378, "CloseConnection", self.ID, self.destination, self.origination)
end

-- This is the function that allows end-users to open sockets, which are the primary method of reading and writing data with GERT.
function GERTi.openSocket(source, dest, doEvent, provID)
  local interface, hop
	if type(dest) == "function" and type(doEvent) == "number" and not provID then
    interface, hop = resolve(dest)
    
		provID = doEvent
		doEvent = dest
		dest = source
    interface
    source = GERTi.interfaces[interface].address
	end
	
  
	local destination = dest
	local origination = source
	local outID = (provID or connectDex)
	local outDex = 0
	local incDex = nil
	local isValid = false
	local socket = {}
	if not destination then
		return nil, err
	end
	
	for key, value in pairs(neighbors) do
		if value["address"] == destination then
			outDex = storeConnection(origination, destination, false, provID, iAddress)
			nextHop = value["address"]
			routeOpener(destination, origination, origination, value["address"], value["port"], value["port"], gAddress, outID, iAddress)
			isValid = true
			break
		end
	end
	if not isValid then
		outDex = storeConnection(origination, destination, false, provID, iAddress)
		nextHop = neighbors[1]["address"]
		routeOpener(destination, origination, origination, neighbors[1]["address"], neighbors[1]["port"], neighbors[1]["port"], gAddress, outID, iAddress)
		isValid = true
	end
			
	if isValid then
		socket.origination = origination
		socket.destination = destination
		--socket.outbound = gAddress
		--socket.outPort = outgoingPort
		socket.nextHop = nextHop
		socket.ID = outID
		socket.incDex = incDex
		socket.outDex = outDex
		socket.write = writeData
		socket.read = readData
		socket.close = closeConnection
		socket.doEvent = doEvent
	else
		return nil, "Route cannot be opened, please confirm destination and that a valid path exists."
	end
	return socket
end

function GERTi.getConnections()
	local tempTable = {}
	for key, value in pairs(connections) do
		tempTable[key] = {}
		tempTable[key]["destination"] = value["destination"]
		tempTable[key]["origination"] = value["origination"]
		tempTable[key]["connectionID"] = value["connectionID"]
		tempTable[key]["doEvent"] = value["doEvent"]
	end
	return tempTable
end

--[[function GERTi.getNeighbors()
	return neighbors
end

--[[function GERTi.getPaths()
	return paths
end

function GERTi.getAddress(interface)
	if interface and GERTi.interfaces[interface] then
		return GERTi.interfaces[interface].address
	else
		
	end
end]]

return GERTi
