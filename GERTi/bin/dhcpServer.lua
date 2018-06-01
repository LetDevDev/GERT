local event = require("event")
local gert = require("GERTi")
local serial = require("serialization")

--Usage: interface network subnet start end

local tArgs = {...}
local network, subnet, start, peak

local alloc = {}

if not type(tArgs[1]) == "string" or #tArgs ~= 5 or tArgs[1] == "--help" or tArgs[1] == '?' then
  printUsage()
  return
end

network = tonumber(tArgs[2],16)
subnet = tonumber(tArgs[3],16)
start = tonumber(tArgs[4],16)
peak = tonumber(tArgs[5],16)

local function printUsage()
  print("Usage: interface network subnet start end\nnetwork, subnet, start, and end must all be hexidecimal")
end

local function nextFree(){
  for i = start, i < end, 1 do
    if not alloc[i] then
      return i
    end
  end
  return -1
}

local function handleRequest(name,us,them,proto,data)
  if proto ~= 2 or us ~= gert.interfaces[interface].addr or data ~= "D" then
    return
  end
  
  addr = nextFree()
  
  alloc[addr] = true
  
  gert.interfaces[interface]:send(them,2,"O"..serial.serialize({addr = network | addr,subnet = subnet}))
  
  acceptance = {event.pull(5,"gert_packet",them,us,2,string.format("R%06X",network | addr))}
  if not acceptance then return end
  
  gert.interfaces[interface]:send(them,2,"A")
end

event.listen("gert_packet",handleRequest)

print("DHCP server running on ", interface," CTRL-C to quit")

event.pull("interrupted")

print("CTRL-C Pressed, Stopping Server")

event.ignore("gert_packet",handleRequest)

