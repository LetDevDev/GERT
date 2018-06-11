local gert = require("GERTi")
local udp = require("udp")

print("I'm: "..gert.interfaces.eth0.addr)

local sock = udp.openSocket(tonumber(io.read()),10)

while true do
  local ans = io.read()
  if ans == "read" then
    print(sock:read())
  else
    sock:write(ans)
  end
end