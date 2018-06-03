local event = require("event")
local gert = require("GERTi")

local bufferMax = 65535

local udp = {
bufferMax = bufferMax,
}

local connections = {}

local function swrite(self,data)
  gert.send(self.dest,8,string.format("%04X",self.id)..data)
end

local function sread(self)
  if #self.readBuffer == 0 then
    event.pull("udp_packet",self.dest,self.id)
  end
  returnBuffer = self.readBuffer
  self.readBuffer = ""
  return returnBuffer
end

local function sclose(self)
  self.closed = true
end

--Handy for cleaning up connections nobody wants
function udp.collectGarbage()
  local count = 0
  for i=1,#connections do
    if not connections[i] or connections[i].closed or not connections[i].bound then
      table.remove(connections,i)
      count = count + 1
    end
  end
  return count
end

function udp.connections()
  return #connections
end

function udp.openSocket(dest,responder,id)
  for _,v in pairs(connections) do
    if v.id == id and v.dest == dest then --If there is already a socket open
      if not v.bound then --The socket is not bound to an application, we can bind it
        v.bound = true
        return v
      else --it is already open and bound, we can't touch it
        return false, "connection open and bound"
      end
    end
  end
  
  local socket = {
    dest = dest,
    id = (id or math.floor(math.random(0,65535))),
    closed = false,
    readBuffer = "",
    bufferOverrun = false,
    bound = true, --Sockets created by an application are always bound
    read = sread,
    write = swrite,
    close = sclose,
  }
  
  table.insert(connections,socket)
  return socket
end

local function udpReceive(name,receiver,sender,proto,data)
  if proto ~= 8 then return end
  
  conID = tonumber(data:sub(1,4),16)
  data = data:sub(5)
  
  for _,v in pairs(connections) do
    if v.dest == sender and v.id == conID then
      if #v.readBuffer + #data > bufferMax then
        v.bufferOverrun = true
      else
        v.readBuffer = v.readBuffer..data
      end
      event.push("udp_packet",sender,conID)
      return
    end
  end
  
  local newConnection = {
    dest = sender,
    id = conID,
    closed = false,
    readBuffer = data,
    bufferOverrun = false,
    bound = false, --Sockets created by an application are always bound
    read = sread,
    write = swrite,
    close = sclose,
  }
  
  table.insert(connections,newConnection)
  
  event.push("udp_packet",sender,conID)
end

event.listen("gert_packet",udpReceive)

return udp
