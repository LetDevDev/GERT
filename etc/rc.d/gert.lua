local dhcp = require("dhcp")
local fs = require("filesystem")
local gert = require("GERTi")
local icmp = require("icmp")

local driver_path = "/lib/unet/drivers/"

function start()
  print("Preparing to load drivers from "..driver_path)
  local iter = fs.list(driver_path)
  for driver_name in iter do 
    print("Loading driver "..driver_name)
    local success, driver = pcall(dofile,driver_path..driver_name) 
    if success then
      print("Driver loaded")
      if driver.load and pcall(driver.load) then
        print("Interface loading complete")
      else
        print("Error loading interfaces...")
      end
    else
      print("Driver not loaded: "..driver)
    end 
  end

  print("Starting DHCP client")
  print("Scanning for DHCP enabled interfaces")
  for k,v in pairs(gert.interfaces) do
    if v.dhcp then
      print(k.." is DHCP enabled, attempting allocation of link local address")
      if dhcp.link_local(v) then 
        print("Success, attempting allocation of directed address")
        dhcp.request(v)
      else
        print(k.." could not get an address, disabling")
        v.state = false
      end
    end
  end
end
