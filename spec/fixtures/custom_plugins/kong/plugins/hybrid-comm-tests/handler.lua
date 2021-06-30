-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local ngx = ngx
local kong = kong
local assert = assert
local math = math
local message = require("kong.hybrid.message")


local HybridCommTests = {
  PRIORITY = math.huge,
}


local function print_log(m)
  ngx.log(ngx.DEBUG, "[hybrid-comm-tests] src = ", m.src, ", dest = ", m.dest, ", topic = ", m.topic, ", message = ", m.message)
end


function HybridCommTests:init_worker()
  kong.hybrid:register_callback("hybrid_comm_test", function(m)
    print_log(m)
    local resp = message.new(nil, m.src, "hybrid_comm_test_resp", m.message)
    assert(kong.hybrid:send(resp))
  end)

  kong.hybrid:register_callback("hybrid_comm_test_resp", print_log)
end


function HybridCommTests:access(config)
  local m = message.new(nil, "control_plane", "hybrid_comm_test", "hello world!")
  assert(kong.hybrid:send(m))
  kong.response.exit(200, { node_id = kong.node.get_id(), })
end


return HybridCommTests
