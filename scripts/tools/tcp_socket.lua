-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]
local tcp = ngx.socket.tcp()

local function connect(host, port)
  tcp:settimeout(5000)
  if host ~= nil then return tcp:connect(host, port) end
  return nil, "error connecting"
end

if args[2] == nil then
  print("Please add `host` and `port`")
  print("Usage: kong runner tcp_socket.lua <host> <port>")
end

local ok, err = connect(args[2], args[3])

if ok then
  print("Successfully connected to " .. args[2] .. ":" .. args[3] .. "!")
  tcp:close()
else
  print("Failed to connect " .. err)
end
