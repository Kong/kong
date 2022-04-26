-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson_decode = require("cjson").decode


return {
  _stream = function(data)
    local json = cjson_decode(data)
    local action = json.action or "echo"

    if action == "echo" then
      return json.payload, json.err

    elseif action == "rep" then
      return string.rep("1", json.rep or 0)

    elseif action == "throw" then
      error(json.err or "error!")
    end
  end,
}
