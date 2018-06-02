local gert = require("GERTi")
local event = require("event")
local serial = require("serialization")

local routes = GERTi.routes

for k,v in pairs(GERTi.interfaces) do
  local route = string.format("%06X/%06X",(v.addr & v.subnet),v.subnet)
  routes[route] = v.addr
  if not GERTi.routes[route] then
    GERTi.routes[route] = v.addr
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

while true do
  p = {event.pull("gert_packet")}
  
  --Handle ICMP Route Discovery packets here, don't forward
  if p[4] == 1 and p[5] == "03" then
    for k,v in pairs(GERTi.interfaces) do
      if GERTi.utils.isSameSubnet(v.addr,p[2],v.subnet) then
        print("Serving route discovery request for "..p[3].." on "..v.addr)
        v:send(p[3],1,"04"..presentRoutes(v))
        print("Served route discovery request from "..p[3])
      end
    end
  else
    local interface, via = GERTi.utils.resolve(p[2])
    io.write("Forwarding packet to "..p[2].." using "..interface)
    if via then print(" via "..via) else print() end
    GERTi.interfaces[interface]:psend(p[3],p[2],p[4],p[5],via)
  end
end

