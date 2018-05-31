-- GERT v1.0.2 - DEV
local GERTi = {}
local component = require("component")
local computer = require("computer")
local event = require("event")
local serialize = require("serialization")

GERTi.interfaces = {}
GERTi.default_route = 0
GERTi.routes = {}   --address/subnet = target  Target Gateway 
GERTi.drivers = {}

local handler = {}

local isSameSubnet = function(first,second,mask)
    return (first & mask) == (second & mask)
end

local resolve = function(dest)
  for k,v in pairs(GERTi.interfaces) do
    if isSameSubnet(dest,v.addr,v.subnet) then
      return k
    end
  end
  for k,v in pairs(GERTi.routes) do
    if isSameSubnet(dest,tonumber("0x"..k:sub(1,6)),tonumber("0x"..k:sub(8,13))) then
      for l,w in pairs(GERTi.interfaces) do
        if isSameSubnet(v,w.addr,w.subnet) then
          return l, v
        end
      end
    end
  end
  for k,v in pairs(GERTi.interfaces) do
    if isSameSubnet(GERTi.default_route,v.addr,v.subnet) then
      return k, GERTi.default_route
    end
  end
  return false
end

GERTi.utils = {
  resolve = resolve,
  isSameSubnet = isSameSubnet,
  getBroadcastAddr = function(interface)
    return math.abs(interface.subnet - 0xFFFFFF) | interface.addr
  end
}

-- Basic transmit function, does some route resolution unless forced to use an interface
GERTi.send = function(source,dest,proto,data)
  if type(proto) == "string" and data == nil then 
    data = proto
    proto = dest
    dest = source
    
    local interface, via = resolve(dest)
    if GERTi.interfaces[interface] then
      if GERTi.interfaces[interface].addr == dest then
        event.push("gert_packet",dest,dest,proto,data)
      else
       GERTi.interfaces[interface]:send(dest,proto,data,via)
     end
    end
  else
  
    for k,v in pairs(GERTi.interfaces) do
      if v.addr == source then
        return v:send(dest,proto,data)
      end
    end
    
  end
end

return GERTi
