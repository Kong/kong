-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local oauth2_tokens = {}


local sha1_bin = ngx.sha1_bin
local to_hex = require "resty.string".to_hex


function oauth2_tokens:cache_key(access_token)
  return "oauth2_tokens:" .. to_hex(sha1_bin(self.super.cache_key(self, access_token)))
end


return oauth2_tokens
