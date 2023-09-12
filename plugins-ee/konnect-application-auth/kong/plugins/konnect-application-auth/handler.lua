-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local resty_sha256 = require "resty.sha256"
local resty_str = require "resty.string"
local meta = require "kong.meta"
local helpers = require "kong.enterprise_edition.consumer_groups_helpers"


local tostring = tostring


local ngx = ngx
local kong = kong


local EMPTY = {}


local KonnectApplicationAuthHandler = {
  PRIORITY = 950,
  VERSION = meta.core_version,
}


local function hash_key(key)
  local sha256 = resty_sha256:new()
  sha256:update(key)
  return resty_str.to_hex(sha256:final())
end


local function get_api_key(plugin_conf)
  local apikey
  local headers = kong.request.get_headers()
  local query = kong.request.get_query()

  for i = 1, #plugin_conf.key_names do
    local name = plugin_conf.key_names[i]

    -- search in headers
    apikey = headers[name]
    if not apikey then
      -- search in querystring
      apikey = query[name]
    end

    if type(apikey) == "string" then
        query[name] = nil
        kong.service.request.set_query(query)
        kong.service.request.clear_header(name)
      break

    elseif type(apikey) == "table" then
      -- duplicate API key
      return nil, { status = 401, message = "Duplicate API key found" }
    end
  end

  if apikey and apikey ~= "" then
    return hash_key(apikey)
  end
end


local function get_identifier(plugin_conf)
  local identifier

  if plugin_conf.auth_type == "openid-connect" then
    -- get the client_id from authenticated credential
    identifier = (kong.client.get_credential() or EMPTY).id
  elseif plugin_conf.auth_type == "key-auth" then
    identifier = get_api_key(plugin_conf)

    kong.client.authenticate(nil, {
      id = tostring(identifier or "")
    })
  end

  local ctx = ngx.ctx
  ctx.auth_type = plugin_conf.auth_type

  if not identifier or identifier == "" then
    return nil, { status = 401, message = "Unauthorized" }
  end

  return identifier
end


local function load_application(client_id)
  local application, err = kong.db.konnect_applications:select_by_client_id(client_id)
  if not application then
    return nil, err
  end

  return application
end


local function is_authorized(application, scope)
  local scopes = application and application.scopes or {}
  local scopes_len = #scopes
  if scopes_len > 0 then
    for i = 1, #scopes do
      if scope == scopes[i] then
        return true
      end
    end
  end

  return false
end

--- map_consumer_groups makes the mapping of the consumer groups attached to the
--- application. If the consumer_group is not found in the kong instance it skips
--- the mapping.
local function map_consumer_groups(application)
  if #application.consumer_groups > 0 then
    local cg_to_map = {}
    for i = 1, #application.consumer_groups do
      if application.consumer_groups[i] ~= '' then
        local consumer_group = helpers.get_consumer_group(application.consumer_groups[i])
        if consumer_group then
          table.insert(cg_to_map, consumer_group)
        end
      end
    end
    if #cg_to_map > 0 then
      kong.client.set_authenticated_consumer_groups(cg_to_map)
    end
  end
end

function KonnectApplicationAuthHandler:access(plugin_conf)
  local identifier, err = get_identifier(plugin_conf)
  if err then
    return kong.response.error(err.status, err.message)
  end

  local cache = kong.cache

  local application_cache_key = kong.db.konnect_applications:cache_key(identifier)
  local application, err = cache:get(application_cache_key, nil,
                                     load_application, identifier)
  if err then
    return error(err)
  end

  if not application and plugin_conf.auth_type == "key-auth" then
    return kong.response.error(401, "Unauthorized")
  end

  if not is_authorized(application, plugin_conf.scope) then
    return kong.response.error(403, "You cannot consume this service")
  end

  map_consumer_groups(application)

end


return KonnectApplicationAuthHandler
