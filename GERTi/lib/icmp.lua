local gert = require("GERTi")
local event = require("event")

local icmp = {}

--
icmp.ping_target = function(source,dest,data)
  if not data then
    data = "010123456789ABCDEF"
  else
    data = "01"..data
  end
  
end

icmp.ping = function(dest,data)
  if not data then
    data = "010123456789ABCDEF"
  else
    data = "01"..data
  end
end

local function onPacket(name,source,dest,proto,data)
  if proto ~= 1 then return end
  
  
end
