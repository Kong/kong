local crud = require "kong.api.crud_helpers"
local app_helpers = require "lapis.application"
local responses = require "kong.tools.responses"

return {
  ["/upstreams/"] = {
    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.upstreams)
    end,

    PUT = function(self, dao_factory)
      crud.put(self.params, dao_factory.upstreams)
    end,

    POST = function(self, dao_factory, helpers)
      crud.post(self.params, dao_factory.upstreams)
    end
  },

  ["/upstreams/:name_or_id"] = {
    before = function(self, dao_factory, helpers)
      crud.find_upstream_by_name_or_id(self, dao_factory, helpers)
    end,

    GET = function(self, dao_factory, helpers)
      return helpers.responses.send_HTTP_OK(self.upstream)
    end,

    PATCH = function(self, dao_factory)
      crud.patch(self.params, dao_factory.upstreams, self.upstream)
    end,

    DELETE = function(self, dao_factory)
      crud.delete(self.upstream, dao_factory.upstreams)
    end
  },

  ["/upstreams/:name_or_id/targets/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_upstream_by_name_or_id(self, dao_factory, helpers)
      self.params.upstream_id = self.upstream.id
    end,

    GET = function(self, dao_factory)
      crud.paginated_set(self, dao_factory.targets)
    end,

    POST = function(self, dao_factory, helpers)
      -- when to cleanup: invalid-entries > (valid-ones * cleanup_factor)
      local cleanup_factor = 10
      
      --cleaning up history, check if it's necessary...
      local target_history = dao_factory.targets:find_all(
            { upstream_id = self.params.upstream_id })

      if target_history then --ignoring errors here, will be caught when posting below
        -- sort the targets
        for _,target in ipairs(target_history) do
          target.order = target.created_at..":"..target.id
        end

        -- sort table in reverse order
        table.sort(target_history, function(a,b) return a.order>b.order end)
        -- do clean up
        local cleaned = {} 
        local delete = {}

        for _, entry in ipairs(target_history) do
          if cleaned[entry.target] then
            -- we got a newer entry for this target than this, so this one can go
            delete[#delete+1] = entry

          else
            -- haven't got this one, so this is the last one for this target
            cleaned[entry.target] = true
            cleaned[#cleaned+1] = entry
            if entry.weight == 0 then
              delete[#delete+1] = entry
            end
          end
        end
        
        -- do we need to cleanup?
        -- either nothing left, or when 10x more outdated than active entries
        if (#cleaned == 0 and #delete > 0) or
           (#delete >= (math.max(#cleaned,1)*cleanup_factor)) then

          ngx.log(ngx.INFO, "[admin api] Starting cleanup of target table for upstream ", 
                            tostring(self.params.upstream_id))
          local cnt = 0
          for _, entry in ipairs(delete) do
            -- not sending update events, one event at the end, based on the
            -- post of the new entry should suffice to reload only once
            dao_factory.targets:delete(
              { id = entry.id }, 
              { quiet = true }
            )
            -- ignoring errors here, deleted by id, so should not matter
            -- in case another kong-node does the same cleanup simultaneously
            cnt = cnt + 1 
          end

          ngx.log(ngx.INFO, "[admin api] Finished cleanup of target table",
            " for upstream ", tostring(self.params.upstream_id),
            " removed ", tostring(cnt), " target entries")
        end
      end

      crud.post(self.params, dao_factory.targets)
    end,
  },

  ["/upstreams/:name_or_id/targets/active/"] = {
    before = function(self, dao_factory, helpers)
      crud.find_upstream_by_name_or_id(self, dao_factory, helpers)
      self.params.upstream_id = self.upstream.id
    end,

    GET = function(self, dao_factory)
      self.params.active = nil

      local target_history, err = dao_factory.targets:find_all({
        upstream_id = self.params.upstream_id,
      })
      if not target_history then
        return app_helpers.yield_error(err)
      end

      --sort and walk based on target and creation time
      for _, target in ipairs(target_history) do
        target.order = target.target .. ":" ..
          target.created_at .. ":" ..target.id
      end
      table.sort(target_history, function(a, b) return a.order > b.order end)

      local ignored = {}
      local found   = {}
      local found_n = 0

      for _, entry in ipairs(target_history) do
        if not found[entry.target] and not ignored[entry.target] then
          if entry.weight ~= 0 then
            entry.order = nil -- dont show our order key to the client
            found_n = found_n + 1
            found[found_n] = entry

          else
            ignored[entry.target] = true
          end
        end
      end

      -- for now lets not worry about rolling our own pagination
      -- we also end up returning a "backwards" list of targets because
      -- of how we sorted- do we care?
      return responses.send_HTTP_OK {
        total = found_n,
        data  = found,
      }
    end
  },

}
