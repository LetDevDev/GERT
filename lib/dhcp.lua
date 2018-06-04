local event = require("event")
local gert = require("GERTi")
local serial = require("serialization")

local timeout = 5    --The number of seconds to wait for replies before giving up
local max_tries = 5  --The number of times to retry gaining a link local address

local dhcp = {}

--attempts to get an address for the given interface by grabing a random free address from link local
dhcp.link_local = function(interface)
  local tries = 0
  while tries < max_tries do --Don't try forever
    local address = math.floor(math.random(1,254)) --Generate a random link local address
    if not interface:resolve(address) then --Make sure no one is using it
      interface.addr = address --Configure the address and subnet
      interface.subnet = 0xFFFF00
      return true
    end
  end
  return false
end

--Attempts to contact a DHCP server and obtain an address from it for the given interface
dhcp.request = function(interface)
  local baddr = gert.utils.getBroadcastAddr(interface) --Get our broadcast address, this'll almost always be 255
  interface:send(baddr,2,"D") --broadcast to the network a dhcp discovery
  local offer = {event.pull(timeout,"gert_packet",interface.addr,nil,2)} --grab the first unicast gert packet that is destined for us under dhcp
  
  if not type(offer) == "table" or #offer < 5 or offer[5]:sub(1,1) ~= "O" then return false end --Sanity checks, ensure the reply was valid
  
  local offer_data = serial.unserialize(offer[5]:sub(2)) --Extract the encoded offer
  interface:send(baddr,2,"R"..string.format("0x%06X",offer_data.addr)) --Request the address offered
  local ackowledged = {event.pull(timeout,"gert_packet",interface.addr,nil,2,"A")} --Ensure our request is acknowledged
  
  if not type(ackowledged) == "table" then return false end
  
  interface.addr = offer_data.addr --Register our given interface and subnet
  interface.subnet = offer_data.subnet
  if offer_data.default_route and gert.default_route == 0 then --if the server offers a default route and we don't have one
    gert.default_route = offer_data.default_route --accept it as our default route
  end
  if offer_data.routes then --if the server offers routes
    for k,v in pairs(offer_data.routes) do
      if not gert.routes[k] then --and we don't have them already
        gert.routes[k] = v --accept the route
      end
    end
  end
  return true
end

return dhcp
