local file_helpers = require "kong.portal.file_helpers"
local event_hooks = require "kong.enterprise_edition.event_hooks"
local workspaces = require "kong.workspaces"
local singletons = require "kong.singletons"
local tracing = require "kong.tracing"
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

  -- portal router events
  worker_events.register(function(data)
    local file = data.entity
    if file_helpers.is_config_path(file.path) or
       file_helpers.is_content_path(file.path) or
       file_helpers.is_spec_path(file.path) then
      local workspace = workspaces.get_workspace()
      local cache_key = "portal_router-" .. workspace.name .. ":version"
      local cache_val = tostring(file.created_at) .. file.checksum

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
    singletons.portal_router.set_version(data.cache_key, data.cache_val)
  end, "portal", "router")

  if event_hooks.enabled() then
    worker_events.register(event_hooks.crud, "crud", "event_hooks")
  end

end


function handler.new_router(router)
  tracing.wrap_router(router)
  return router
end


return handler
