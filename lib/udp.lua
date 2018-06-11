local event = require("event")
local gert = require("GERTi")

--Fixed value, the max data recieved that can be buffered in this library.
local bufferMax = 65535

local udp = {
  bufferMax = bufferMax,
}

--All opened sockets are stored here, this is intentionally hidden
--Keys are arranged in a map, formatted as DDDDDDIIII where D is Dest and I is ID
connections = {}

--Given 2 ints between 0 and 65535, returns a string that can be converted back
local function buildHeader(id,length)
  return string.format("%04X%04X",id,length)
end

--Given a string in which the first 4 characters represent 2 ints, returns the ints themselves
local function breakHeader(header)
  return tonumber("0x"..header:sub(1,4)), tonumber("0x"..header:sub(5,8))
end

--[[Basic send function. useful for quick packets
dest: The destination IP Address
data: The data to send
id: If provided, will use this instead
]]
function udp.send(dest,data,id)
  if not id then id = math.floor(math.random(0,65535)) end
  gert.send(dest,8,buildHeader(id,#data)..data)
end

--Write data to a socket, wrapper for basic send function
local function swrite(self,data)
  udp.send(self.dest,data,self.id)
end

--Read data from a socket
local function sread(self)
  if #self.readBuffer == 0 then
    event.pull("udp_packet",self.dest,self.id)
  end
  local length = tonumber("0x"..self.readBuffer:sub(1,4))
  returnBuffer = self.readBuffer:sub(5,length+4)
  self.readBuffer = self.readBuffer:sub(length + 5, #self.readBuffer)
  return returnBuffer
end

--Remove this socket from the connections, this halts buffering of messages
local function sclose(self)
  self = nil
end

--[[Open a socket
dest: The destination IP address
responder: NOT YET IMPLEMENTED
id: The id of the connection, used to open a reply socket or force an id
]]
function udp.openSocket(dest,id,responder)
  --Enforce application's right to exclusive access to a socket
  if connections[string.format("%06X%04X",dest,id)] then
    return false, "Socket already opened"
  end
  
  local connKey
  
  --Since uniqueness was enforced above, if we were provided an ID, generate the Connection Key
  if id then
    connKey = string.format("%06X%04X",dest,id)
  else
    --Avoid connection collisions
    repeat  
      id = math.floor(math.random(0,65535))
      connKey = string.format("%06X%04X",dest,id)
    until not connections[connKey]
  end
    
  local socket = {
    dest = dest,
    id = id,
    readBuffer = "",
    bufferOverrun = false,
    read = sread,
    write = swrite,
    close = sclose,
  }
  
  connections[connKey] = socket
  
  return socket
end

--Receiver for UDP traffic, not for use 
local function udpReceive(name,receiver,sender,proto,data)
  if proto ~= 8 then return end
  
  
  connID, length = breakHeader(data) --Extract the Connection ID, length, and data from the packet
  data = data:sub(5,#data) --We leave the length header on for now though, we may need it later.
  
  --If a socket is open for this connection, buffer the packet in it
  if connections[string.format("%06X%04X",sender,connID)] then
    local conn = connections[string.format("%06X%04X",sender,connID)]
    if #conn.readBuffer + #data > bufferMax then
      conn.bufferOverrun = true --Buffer exceeded flag is set and data is discarded
    else
      conn.readBuffer = conn.readBuffer..data
    end
    event.push("udp_packet",sender,connID) --Data is ommited as it was buffered
    return
  end
  
  
  event.push("udp_packet",sender,connID,data:sub(5,#data)) --Connection-less packets have their data in the event
  --we also strip the length header
end

event.listen("gert_packet",udpReceive)

return udp
