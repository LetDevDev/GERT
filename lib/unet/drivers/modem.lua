local component = require("component")
local event = require("event")
local serial = require("serialization")
local gert = require("GERTi")

local ttl = {1,2}
local pro = {3,4}
local src = {5,10}
local dst = {11,16}


modem_driver = {}

local function readHeader(s)
   return tonumber("0x"..s:sub(ttl[1],ttl[2])), tonumber("0x"..s:sub(pro[1],pro[2])), tonumber("0x"..s:sub(src[1],src[2])),tonumber("0x"..s:sub(dst[1],dst[2]))
end

--[[ Arp resolution, given a GERT interface, will dicover the target node
interface: the GERT interface to use for resolution
addr: the GERT address to resolve
returns true and a mac address on success, false and a error string on failure
]]
local resolve = function(interface, addr)
  if not interface.hw_type == "modem" then
    return false, "interface not a modem"
  end
  
  for i = 1, #interface.arp_cache do  --First check to see if the arp cache has it
    if interface.arp_cache[i][1] == addr then
      return true, interface.arp_cache[i][2]
    end
  end
  
  component.invoke(interface.hw_addr,"broadcast",interface.hw_channel,"arp_request",addr)
  
  success,_,mac = event.pull(5,"modem_message",interface.hw_addr,nil,interface.hw_channel,nil,"arp_reply",addr)
  
  if success ~= nil then
    table.insert(interface.arp_cache,{addr,mac})
    interface.arp_cache[interface.arp_cache.max_entries + 1] = nil
    return true, mac
  end
  
  return false, "no device found"
end
modem_driver.resolve = resolve

--[[ Interface send, GERT wrapper object to transmit a packet using a modem
self: the GERT interface to use for transmission
dest: the GERT address to send too
proto: the GERT header to attach, see documentation
returns a boolean representing success
]]
local isend = function(self,dest,proto,data,via)
  if not self.state then  --If the interface is down, do not send
    return false, "interface is down"
  end
  if gert.utils.getBroadcastAddr(self) == dest then --if the target is this network's broadcast, perform hardware broadcast
    return component.invoke(self.hw_addr,"broadcast",self.hw_channel,"gert_packet",string.format("%02X%02X%06X%06X",127,proto,self.addr,dest),data)
  else
    if via then
      success,mac = resolve(self,via)
    else
      success,mac = resolve(self,dest)
    end
    if success then
      return component.invoke(self.hw_addr,"send",mac,self.hw_channel,"gert_packet",string.format("%02X%02X%06X%06X",127,proto,self.addr,dest),data)
    end
    return success
  end
end

modem_driver.isend = isend

--Promiscuous send, for spoofing source addresses.
local psend = function(self,source,dest,proto,data,via)
  if not self.state then  --If the interface is down, do not send
    return false, "interface is down"
  end
  --At this time, spoofing should not be allowed for broadcasts
  --[[if gert.utils.getBroadcastAddr(self) == dest then --if the target is this network's broadcast, perform hardware broadcast
    return component.invoke(self.hw_addr,"broadcast",self.hw_channel,"gert_packet",string.format("%02X%02X%06X%06X",127,proto,self.addr,dest),data)
  else]]
    if via then
      success,mac = resolve(self,via)
    else
      success,mac = resolve(self,dest)
    end
    if success then
      return component.invoke(self.hw_addr,"send",mac,self.hw_channel,"gert_packet",string.format("%02X%02X%06X%06X",127,proto,source,dest),data)
    end
    return success
  --end
end

modem_driver.psend = psend

--Driver receive event listener, not for application use.
modem_driver.recieve = function(name,our_mac,their_mac,channel,distance,preamble,header,data)
  if preamble == "gert_packet" then
    local _,proto,their_ip,our_ip = readHeader(header)
    for k,v in pairs(gert.interfaces) do
      if v.hw_addr == our_mac and v.hw_channel == channel and ((v.addr == our_ip or gert.utils.getBroadcastAddr(v) == our_ip) or v.is_promiscuous) then
        event.push("gert_packet",our_ip,their_ip,proto,data)
      end
    end
  elseif preamble == "arp_request" then
    for k,v in pairs(gert.interfaces) do
      if v.hw_addr == our_mac and v.addr == header then
        component.invoke(v.hw_addr,"send",their_mac,channel,"arp_reply",v.addr)
      end
    end
  end
end

event.listen("modem_message",modem_driver.recieve)

--[[create the wrapper for a new interface
name: the name to use for the interface
hw_addr: the address to use for the interface
channel: the hw channel to use for transmission, useful for vlan's
addr: the address to start the interface with
subnet: the subnet mask to start the interface with
dhcp: whether or not the interface will automatically handle addressing
for changes to persist, save should be called
]]
function modem_driver.create(name,hw_addr,channel,cache,addr,subnet,dhcp)
  if not component.slot(hw_addr) then
    return false, "no such component"
  end
  
  if not component.invoke(hw_addr,"isOpen",channel) and not component.invoke(hw_addr,"open",channel) then
    return false, "no avalable ports"
  end
  
  if gert.interfaces[name] then
    return false, "interface with name exists"
  end
  
  gert.interfaces[name] = {
    hw_type = "modem",
    hw_addr = hw_addr,
    hw_channel = channel,
    arp_cache = {max_entries = cache},
    addr = addr,
    dhcp = dhcp,
    subnet = subnet,
    state = true, 
    send = isend,
  }
  
  return true
end

--Called at startup, loads all the modem interfaces into memory and starts them
function modem_driver.load()
  modems = dofile("/etc/unet/drivers/modems.cfg")
  for k,v in pairs(modems) do
    if v.state and not component.invoke(v.hw_addr,"isOpen",v.hw_channel) 
      and not component.invoke(v.hw_addr,"open",v.hw_channel) then
      v.state = false
    end
    if v.is_promiscuous then
      v.psend = psend
    end
    v.send = isend
    gert.interfaces[k] = v
  end
end

--Called when it's time to commit changes to the drive
function modem_driver.save()
  local modems = {}
  for k,v in pairs(gert.interfaces) do
    if v.hw_type and v.hw_type == "modem" then
      modems[k] = v
      modems[k].arp_cache = {max_entries = v.arp_cache.max_entries} --Purge arp entries
      if v.dhcp then  --if the address is dhcp, then it is configured at load time
        modems[k].address = 0
        modems[k].subnet = 0
      end
      v.send = nil
      v.psend = nil
    end
  end
  io.open("/etc/unet/drivers/modems.cfg","w"):write("return "..serial.serialize(modems)):close()
end

--[[Remove a wrapper from the loaded interfaces and release the hw port
name: the interface to remove
For changes to persist, save should be called
]]
function modem_driver.remove(name)
  if gert.interfaces[name] then
    component.invoke(gert.interfaces[name].hw_addr,"close",gert.interfaces[name].hw_channel)
    gert.interfaces[name] = nil
  end
end

gert.drivers.modem = modem_driver

return modem_driver