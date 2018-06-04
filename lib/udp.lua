local event = require("event")
local gert = require("GERTi")

--Fixed value, the max data recieved that can be buffered in this library.
local bufferMax = 65535

local udp = {
bufferMax = bufferMax,
}

--All opened sockets are stored here, this is intentionally hidden
--Keys are arranged in a map, formatted as DDDDDDIIII where D is Dest and I is ID
local connections = {}

--[[Basic send function. useful for quick packets
dest: The destination IP Address
data: The data to send
id: If provided, will use this instead
]]
function udp.send(dest,data,id)
  if not id then id = math.floor(math.random(0,65535)) end
  gert.send(dest,8,string.format("%04X",id)..data)
end

--Write data to a socket
local function swrite(self,data)
  gert.send(self.dest,8,string.format("%04X",self.id)..data)
end

--Read data from a socket
local function sread(self)
  if #self.readBuffer == 0 then
    event.pull("udp_packet",self.dest,self.id)
  end
  returnBuffer = self.readBuffer
  self.readBuffer = ""
  return returnBuffer
end

--Remove this socket from the connections, this halts buffering of messages
local function sclose(self)
  connections[string.format("%06X%04X",self.dest,self.id)] = nil
end

--[[Open a socket
dest: The destination IP address
responder: NOT YET IMPLEMENTED
id: The id of the connection, used to open a reply socket or force an id
]]
function udp.openSocket(dest,responder,id)
  --Enforce application's right to exclusive access to a socket
  if connections[string.format("%06X%04X",dest,id] then
    return false, "Socket already opened"
  end
  
  --Avoid connection collisions
  repeat  
  id = math.floor(math.random(0,65535))      
  until not connections[string.format("%06X%04X",dest,id)]
    
  local socket = {
    dest = dest,
    id = id,
    readBuffer = "",
    bufferOverrun = false,
    read = sread,
    write = swrite,
    close = sclose,
  }
  
  connections[string.format("%06X%04X",dest,id] = socket
  
  return socket
end

--Receiver for UDP traffic, not for use 
local function udpReceive(name,receiver,sender,proto,data)
  if proto ~= 8 then return end
  
  conID = tonumber(data:sub(1,4),16)
  data = data:sub(5)
  
  --If a socket is open for this connection, buffer the packet in it
  if connections[string.format("%06X%04X",sender,conID] then
    local conn = connections[string.format("%06X%04X",sender,conID]
    if #conn.readBuffer + #data > bufferMax then
      conn.bufferOverrun = true --Buffer exceeded flag is set and data is discarded
    else
      conn.readBuffer = conn.readBuffer..data
    end
    event.push("udp_packet",sender,conID) --Data is ommited as it was buffered
    return
  end
  
  
  event.push("udp_packet",sender,conID,data) --Connection-less packets have their data in the event
end

event.listen("gert_packet",udpReceive)

return udp
