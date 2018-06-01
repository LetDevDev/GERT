local gert = require("GERTi")
local event = require("event")

local icmp = {}

icmp.ping_target = function(source,dest,data,timeout)
  if not data then data = "010123456789ABCDEF" else data = "01"..data end
  if not timeout then timeout = 5 end
  
  GERTi.send(source,dest,1,data)
  
  reply = event.pull(timeout,"gert_packet",source,dest,1,"02"..data:sub(3))
  if reply then return true else return false end
end

icmp.ping = function(dest,data,timeout)
  if not data then data = "010123456789ABCDEF" else data = "01"..data end
  if not timeout then timeout = 5 end
  
  GERTi.send(dest,1,data)

  reply = event.pull(timeout,"gert_packet",nil,dest,1,"02"..data:sub(3))
  if reply then return true else return false end
end

local function onPacket(name,source,dest,proto,data)
  if proto ~= 1 then return end
  
  if data:sub(1,2) == "01" then
    GERTi.send(dest,1,"02"..data:sub(3))
  end
end

event.listen("gert_packet",onPacket)

return icmp
