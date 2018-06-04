local component = require("component")
local event = require("event")
local serial = require("serialization")
local gert = require("GERTi")

local ttl = {1,2}
local pro = {3,4}
local src = {5,10}
local dst = {11,16}


local tunnel_driver = {}
local tunnel_interfaces = {}

local function readHeader(s)
   return tonumber("0x"..s:sub(ttl[1],ttl[2])), tonumber("0x"..s:sub(pro[1],pro[2])), tonumber("0x"..s:sub(src[1],src[2])),tonumber("0x"..s:sub(dst[1],dst[2]))
end

--[[Neighbor Discovery, will determine if the neighbor is using this address
interface: the GERT interface to use for resolution
addr: the GERT address to resolve
returns true if this address is the neighbor's success, false and a error string on failure
]]
local resolve = function(interface, addr)
  component.invoke(interface.hw_addr,"send","arp_request",addr)
  
  success = event.pull(5,"modem_message",interface.hw_addr,nil,0,nil,"arp_reply",addr)
  
  if success then
    return true
  end
  
  return false, "no device found"
end

tunnel_driver.resolve = resolve

--[[ Interface send, GERT wrapper object to transmit a packet using a tunnel
self: the GERT interface to use for transmission
dest: the GERT address to send too
proto: the GERT header to attach, see documentation
returns a boolean representing success
]]
local isend = function(self,dest,proto,data,via)
  if not self.state then  --If the interface is down, do not send
    return false, "interface is down"
  end
  return component.invoke(self.hw_addr,"send","gert_packet",string.format("%02X%02X%06X%06X",127,proto,self.addr,dest),data)
end
tunnel_driver.isend = isend

--Promiscuous send, for spoofing source addresses.
local psend = function(self,source,dest,proto,data,via)
  if not self.state then  --If the interface is down, do not send
    return false, "interface is down"
  end
  return component.invoke(self.hw_addr,"send","gert_packet",string.format("%02X%02X%06X%06X",127,proto,source,dest),data)
end

tunnel_driver.psend = psend

--Driver receive event listener, not for application use.
function tunnel_driver.recieve(name,our_mac,their_mac,channel,distance,preamble,header,data)
  if preamble == "gert_packet" and channel == 0 then
    local _,proto,their_ip,our_ip = readHeader(header)
    for k,v in pairs(tunnel_interfaces) do
      if v.hw_addr == our_mac and ((v.addr == our_ip or gert.utils.getBroadcastAddr(v) == our_ip) or v.is_promiscuous) then
        event.push("gert_packet",our_ip,their_ip,proto,data)
      end
    end
  elseif preamble == "arp_request" and channel == 0 then
    for k,v in pairs(tunnel_interfaces) do
      if v.hw_addr == our_mac and v.addr == header then
        component.invoke(v.hw_addr,"send","arp_reply",v.addr)
      end
    end
  end
end

event.listen("modem_message",tunnel_driver.recieve)

--[[create the wrapper for a new interface
name: the name to use for the interface
hw_addr: the address to use for the interface
addr: the address to start the interface with
subnet: the subnet mask to start the interface with
dhcp: whether or not the interface will automatically handle addressing
for changes to persist, save should be called
]]
function tunnel_driver.create(name,hw_addr,addr,subnet,dhcp)
  if not component.slot(hw_addr) then
    return false, "no such component"
  elseif component.type(hw_addr) ~= "tunnel" then
    return false, "component not a tunnel"
  elseif gert.interfaces[name] then
    return false, "interface with name exists"
  end
  
  tunnel_interfaces[name] = {
    hw_type = "tunnel",
    hw_addr = hw_addr,
    addr = addr,
    dhcp = dhcp,
    subnet = subnet,
    state = true, 
    send = isend,
  }
  
  gert.interfaces[name] = tunnel_interfaces[name]
  
  return true
end

--Called at startup, loads all the modem interfaces into memory and starts them
function tunnel_driver.load()
  tunnels = dofile("/etc/unet/drivers/tunnels.cfg")
  for k,v in pairs(tunnels) do
    if v.state and not component.slot(v.hw_addr) then
      v.state = false
    end
    if v.is_promiscuous then
      v.psend = psend
    end
    v.send = isend
    v.resolve = resolve
    tunnel_interfaces[k] = v
    gert.interfaces[k] = v
  end
end

--Called when it's time to commit changes to the drive
function tunnel_driver.save()
  local tunnels = {}
  for k,v in pairs(tunnel_interfaces) do
    if v.hw_type and v.hw_type == "tunnel" then
      tunnels[k] = v
      if v.dhcp then  --if the address is dhcp, then it is configured at load time
        tunnels[k].address = 0
        tunnels[k].subnet = 0
      end
      v.send = nil
      v.psend = nil
      v.resolve = nil
    end
  end
  io.open("/etc/unet/drivers/tunnels.cfg","w"):write("return "..serial.serialize(tunnels)):close()
end

--[[Remove a wrapper from the loaded interfaces and release the hw port
name: the interface to remove
For changes to persist, save should be called
]]
function tunnel_driver.remove(name)
  tunnel_interfaces[name] = nil
end

gert.drivers.tunnel = tunnel_driver

return tunnel_driver
