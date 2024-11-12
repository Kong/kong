-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local workspaces = require "kong.workspaces"
local to_hex      = require("resty.string").to_hex

local kong = kong
local null = ngx.null


local _M = {}


function _M.consumer_field_cache_key(key, value)
  return kong.db.consumers:cache_key(key, value, "consumers")
end


local function get_ca_id_by_digest(digest)
  local obj, err = kong.db.ca_certificates:select_by_cert_digest(digest)
  if not obj then
    if err then
      return nil, err
    end

    return nil, "CA Certificate (cert_digest: " .. digest .. ") does not exist"
  end

  return obj.id
end

local function ca_id_digest_cache_key(digest)
  return "header-cert-auth:ca:digest:" .. digest
end

function _M.get_ca_id_from_x509(x509)
  -- has to be consistent with the ca_certificates schema
  local digest, err = x509:digest("sha256")
  if not digest then
    return nil, err
  end
  local cert_digest = to_hex(digest)

  return kong.cache:get(ca_id_digest_cache_key(cert_digest), nil, get_ca_id_by_digest, cert_digest)
end


function _M.init_worker()
  if not (kong.worker_events and kong.worker_events.register) then
    return
  end

  -- dbless without rpc will not register events (incremental sync)
  if kong.configuration.database == "off" and not kong.sync then
    return
  end

  local register = kong.worker_events.register

  register(
    function(data)
      workspaces.set_workspace(data.workspace)
      local cache_key = _M.consumer_field_cache_key

      local old_entity = data.old_entity
      if old_entity then
        if old_entity.custom_id and old_entity.custom_id ~= null and old_entity.custom_id ~= "" then
          kong.cache:invalidate(cache_key("custom_id", old_entity.custom_id))
        end

        if old_entity.username and old_entity.username ~= null and old_entity.username ~= "" then
          kong.cache:invalidate(cache_key("username", old_entity.username))
        end
      end

      local entity = data.entity
      if entity then
        if entity.custom_id and entity.custom_id ~= null and entity.custom_id ~= "" then
          kong.cache:invalidate(cache_key("custom_id", entity.custom_id))
        end

        if entity.username and entity.username ~= null and entity.username ~= "" then
          kong.cache:invalidate(cache_key("username", entity.username))
        end
      end
    end, "crud", "consumers")

    register(
      function(data)
        local cache_key = ca_id_digest_cache_key
        local entity = data.entity
        local old_entity = data.old_entity
        if entity then
          kong.cache:invalidate(cache_key(entity.cert_digest))
        end

        if old_entity then
          kong.cache:invalidate(cache_key(old_entity.cert_digest))
        end
      end, "crud", "ca_certificates")
end


return _M
