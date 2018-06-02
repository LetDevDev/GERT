local gert = require("GERTi")
local event = require("event")
local serial = require("serialization")

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

--replies should be formatted as "04{"XXXXXX/XXXXXX"=XXXXXX
icmp.find_routes = function(interface)
  interface:send(GERTi.utils.getBroadcastAddr(interface),1,"03")

  local scanning = true
  event.timer(5,function() event.push("gert_scan_end") end)

  while scanning do
    local t = {event.pull("gert")}
    if t[1] == "gert_scan_end" then
      scanning = false
    elseif t[1] == "gert_packet" and t[2] == interface.addr and t[4] == 1 and t[5]:sub(1,2) == "04" then
      r = serial.unserialize(t[5]:sub(3))
      for k,v in pairs(r) do
        if not GERTi.routes[k] then
          GERTi.routes[k] = v
        end
      end
    end
  end
end

local function onPacket(name,source,dest,proto,data)
  if proto ~= 1 then return end
  
  if data:sub(1,2) == "01" then
    GERTi.send(dest,1,"02"..data:sub(3))
  end
end

event.listen("gert_packet",onPacket)

return icmp
