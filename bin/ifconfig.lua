local component = require("component")
local gert = require("GERTi")
local term = require("term")

local args = {...}

term.write("Welcome to the GERT interface config tool\n")

for k in pairs(gert.drivers) do
  term.write(k.." driver is loaded\n")
end

local function printMenu()
term.write("Menu:\n"
.." 1. List interfaces\n"
.." 2. Enable an interface\n"
.." 3. Disable an interface\n"
.." 4. Configure an interface\n"
.." 5. Create an interface\n"
.." 6. Save changes\n"
.." q. Quit\n  : ")
end
local running = true

local function list()
  term.write("Interfaces:\n")
  for k,v in pairs(gert.interfaces) do
    term.write("IF: "..k.. "\tstate "..tostring(v.state))
    term.write("\nAddress/Subnet: "..v.addr..'/'..v.subnet.."\tDHCP: "..tostring(v.dhcp))
    term.write("\nHardware type: "..v.hw_type.." hw address: \n")
    term.write(v.hw_addr)
    if v.hw_type == "modem" then
      term.write("\nChannel: "..v.hw_channel)
    end
    term.write("\n")
  end
end

local function enable()
  term.write("Enter the name of the interface to disable\n")
  name = term.read()
  name = name:sub(1,#name-2)
  if gert.interfaces[name] then
    gert.interfaces[name].state = true
    if gert.interfaces[name].hw_type == "modem" then
      component.invoke(gert.interfaces[name].hw_addr,"open"
end

local function disable()

end

local function saveChanges()

end

while running do
  printMenu()
  local input = term.read():sub(1,1)
  if input == 'q' or input == 'Q' then
    running = false
  elseif input == '1' then
    list() 
  end
end

