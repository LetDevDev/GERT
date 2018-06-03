local gert = require("GERTi")
local event = require("event")
local serial = require("serialization")
local icmp = require("icmp")

local routes = gert.routes

for k,v in pairs(gert.interfaces) do
  local route = string.format("%06X/%06X",(v.addr & v.subnet),v.subnet)
  routes[route] = v.addr
  if not gert.routes[route] then
    gert.routes[route] = v.addr
  end
  print("Implicit route "..route.." found via "..string.format("%06X",v.addr))
end

local function presentRoutes(interface)
  local filter = string.format("%06X/%06X",(interface.addr & interface.subnet),interface.subnet)
  local present = {}
  
  for k,v in pairs(routes) do
    if k ~= filter then
      print("Presenting "..k.." via "..interface.addr)
      present[k] = interface.addr
    else
      print("Not presenting "..k)
    end
  end
  
  return serial.serialize(present)
end

local function discovery()
  print("Running route discovery checks")
  for k,v in pairs(gert.interfaces) do
    icmp.find_routes(v)
  end
end

event.timer(60,discovery,math.huge)

while true do
  p = {event.pull("gert_packet")}
  
  --Handle ICMP Route Discovery packets here, don't forward
  if p[4] == 1 and p[5] == "03" then
    for k,v in pairs(gert.interfaces) do
      if gert.utils.isSameSubnet(v.addr,p[2],v.subnet) then
        print("Serving route discovery request for "..p[3].." on "..v.addr)
        v:send(p[3],1,"04"..presentRoutes(v))
        print("Served route discovery request from "..p[3])
      end
    end
  else
    print("Packet from "..p[3].." destined for "..p[2].." recieved")
    local interface, via = gert.utils.resolve(p[2])
    io.write("Forwarding packet to "..p[2].." using "..interface)
    if via then print(" via "..via) else print() end
    gert.interfaces[interface]:psend(p[3],p[2],p[4],p[5],via)
  end
end


