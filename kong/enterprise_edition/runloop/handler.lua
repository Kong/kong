-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local file_helpers = require "kong.portal.file_helpers"
local workspaces = require "kong.workspaces"
local utils = require "kong.tools.utils"


local handler = {}


local log = ngx.log
local ERR = ngx.ERR
local DEBUG = ngx.DEBUG
local unpack = unpack


function handler.register_events()
  local kong = kong
  local worker_events = kong.worker_events
  local cluster_events = kong.cluster_events

  if kong.configuration.audit_log then
    log(DEBUG, "register audit log events handler")
    local audit_log = require "kong.enterprise_edition.audit_log"
    worker_events.register(audit_log.dao_audit_handler, "dao:crud")
  end

  -- rbac token ident cache handling
  worker_events.register(function(data)
    kong.cache:invalidate("rbac_user_token_ident:" ..
                          data.entity.user_token_ident)

    -- clear a patched ident range cache, if appropriate
    -- this might be nil if we in-place upgrade a pt token
    if data.old_entity and data.old_entity.user_token_ident then
      kong.cache:invalidate("rbac_user_token_ident:" ..
                            data.old_entity.user_token_ident)
    end
  end, "crud", "rbac_users")

  local invalidate_cache = function(entity_name, id)
    local cache_key = kong.db[entity_name]:cache_key(id)
    kong.cache:invalidate(cache_key)
  end

  -- rbac role entities/endpoints cache handling
  worker_events.register(function(data)
    workspaces.set_workspace(data.workspace)
    invalidate_cache("rbac_role_endpoints", data.entity.id)
    invalidate_cache("rbac_role_entities", data.entity.id)
  end, "crud", "rbac_roles:delete")

  local rbac_role_relations_invalidate = function (data)
    workspaces.set_workspace(data.workspace)
    invalidate_cache(data.schema.name, data.entity.role.id)

    if data.old_entity then
      invalidate_cache(data.schema.name, data.old_entity.role.id)
    end
  end

  worker_events.register(rbac_role_relations_invalidate, "crud", "rbac_role_endpoints")
  worker_events.register(rbac_role_relations_invalidate, "crud", "rbac_role_entities")

  -- workspace update and delete events
  worker_events.register(function(data)
    -- INTF-2967: invalidate workspace cache
    invalidate_cache("workspaces", data.entity.id)
  end, "crud", "workspaces:update", "workspaces:delete")

  -- portal router events
  worker_events.register(function(data)
    workspaces.set_workspace(data.workspace)

    local file = data.entity
    if file_helpers.is_config_path(file.path) or
       file_helpers.is_content_path(file.path) or
       file_helpers.is_spec_path(file.path) then
      local workspace = workspaces.get_workspace()
      local cache_key = "portal_router-" .. workspace.name .. ":version"
      local cache_val = tostring(ngx.now()) .. file.checksum

      -- to node worker event
      local ok, err = worker_events.post("portal", "router", {
        cache_key = cache_key,
        cache_val = cache_val,
      })
      if not ok then
        log(ERR, "failed broadcasting portal:router event to workers: ", err)
      end

      -- to cluster worker event
      local cluster_key = cache_key .. "|" .. cache_val
      ok, err = cluster_events:broadcast("portal:router", cluster_key)
      if not ok then
        log(ERR, "failed broadcasting portal:router event to cluster: ", err)
      end
    end
  end, "crud", "files")


  cluster_events:subscribe("portal:router", function(data)
    local cache_key, cache_val = unpack(utils.split(data, "|"))
    local ok, err = worker_events.post("portal", "router", {
      cache_key = cache_key,
      cache_val = cache_val,
    })
    if not ok then
      log(ERR, "failed broadcasting portal:router event to workers: ", err)
    end
  end)


  worker_events.register(function(data)
    kong.portal_router.set_version(data.cache_key, data.cache_val)
  end, "portal", "router")

end

return handler
