local access = require "kong.plugins.oauth2.access"


local kong = kong
local type = type
local sha1_bin = ngx.sha1_bin
local to_hex = require "resty.string".to_hex


local function invalidate(entity)
  if not entity or type(entity.access_token) ~= "string" then
    return
  end

  local token_hash = to_hex(sha1_bin(entity.access_token))
  local cache_key = kong.db.oauth2_tokens:cache_key(token_hash)
  kong.cache:invalidate_local(cache_key)
end


local OAuthHandler = {
  PRIORITY = 1004,
  VERSION = "2.0.1",
}


function OAuthHandler:init_worker()
  kong.worker_events.register(function(data)
    invalidate(data.old_entity)
  end, "crud", "oauth2_tokens:update")

  kong.worker_events.register(function(data)
    invalidate(data.entity)
  end, "crud", "oauth2_tokens:delete")
end


function OAuthHandler:access(conf)
  access.execute(conf)
end


return OAuthHandler
