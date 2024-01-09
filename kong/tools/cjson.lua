-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson.safe".new()
local constants = require "kong.constants"

cjson.decode_array_with_array_mt(true)
cjson.encode_sparse_array(nil, nil, 2^15)
cjson.encode_number_precision(constants.CJSON_MAX_PRECISION)

local _M = {}


function _M.encode(json_text)
  return cjson.encode(json_text)
end

function _M.decode_with_array_mt(json_text)
  return cjson.decode(json_text)
end

_M.array_mt = cjson.array_mt

return _M
