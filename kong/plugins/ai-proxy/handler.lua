-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local kong_meta = require("kong.meta")
local deep_copy = require "kong.tools.table".deep_copy


local _M = deep_copy(require("kong.llm.proxy.handler"))
_M.init_worker = function()
    _M:build_http2_alpn_filter("ai-proxy")
end

_M.PRIORITY = 770
_M.VERSION = kong_meta.core_version


return _M
