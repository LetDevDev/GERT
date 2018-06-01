local event = require("event")
local gert = require("GERTi")
local serial = require("serialization")

--Usage: interface network subnet start end

local tArgs = {...}
local network, subnet, start, current end

if not type(tArgs[1]) == "string" or #tArgs ~= 5 or tArgs[1] == "--help" or tArgs[1] == '?' then
  printUsage()
  return
end

network = tonumber(tArgs[2],16)
subnet = tonumber(tArgs[3],16)
start = tonumber(tArgs[4],16)
current = start
end = tonumber(tArgs[5],16)

local function printUsage()
  print("Usage: interface network subnet start end\nnetwork, subnet, start, and end must all be hexidecimal")
end

local function handleRequest(name,us,them,proto,data)
  if proto ~= 2 or us ~= gert.interfaces[interface].addr or data ~= "D" then
    return
  end
  
  gert.interfaces[interface]:send(them,2,"O"..serial.serialize({addr = current,subnet = subnet}))
  current = current + 1
  acceptance = {event.pull(5,"gert_packet",them,us,2,string.format("R%06X",current-1))}
  if not acceptance then return end
  
  gert.interfaces[interface]:send(them,2,"O"..serial.serialize({addr = current,subnet = subnet}))
end

event.listen("gert_packet",handleRequest)

print("DHCP server running on ", interface," CTRL-C to quit")

event.pull("interrupted")

print("CTRL-C Pressed, Stopping Server")

event.ignore("gert_packet",handleRequest)

