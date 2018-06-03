local event = require("event")
local gert = require("GERTi")
local serial = require("serialization")

local timeout = 5
local max_tries = 5

local dhcp = {}

dhcp.link_local = function(interface)
  local tries = 0
  while tries < max_tries do
    local address = math.floor(math.random(1,254))
    if not gert.drivers[interface.hw_type].resolve(interface,address) then
      interface.addr = address
      interface.subnet = 0xFFFF00
      return true
    end
  end
  return false
end

dhcp.request = function(interface)
  local baddr = gert.utils.getBroadcastAddr(interface) 
  interface:send(baddr,2,"D")
  local offer = {event.pull(timeout,"gert_packet",interface.addr,nil,2)}
  
  if not type(offer) == "table" or #offer < 5 then return false end
  
  local offer_data = serial.unserialize(offer[5]:sub(2))
  interface:send(baddr,2,"R"..string.format("0x%06X",offer_data.addr))
  local ackowledged = {event.pull(timeout,"gert_packet",interface.addr,nil,2,"A")}
  
  if not type(ackowledged) == "table" then return false end
  
  interface.addr = offer_data.addr
  interface.subnet = offer_data.subnet
  return true
end

return dhcp