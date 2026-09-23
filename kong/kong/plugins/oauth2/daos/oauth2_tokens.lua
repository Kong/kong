local oauth2_tokens = {}


local sha1_bin = ngx.sha1_bin
local to_hex = require "resty.string".to_hex


function oauth2_tokens:cache_key(access_token)
  return "oauth2_tokens:" .. to_hex(sha1_bin(self.super.cache_key(self, access_token)))
end


return oauth2_tokens
