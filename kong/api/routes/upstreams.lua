local crud = require "kong.api.crud_helpers"

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
      -- cleaning up history, we do not care about errors, as another
      -- node might clean up at the same time. We're deleting by id, so that
      -- should not matter.
      local target_history, err = dao_factory.targets:find_all(
            { upstream_id = self.params.upstream_id })
      if target_history then
        -- sort the targets
        for _,target in ipairs(target_history) do
          target.order = target.created_at..":"..target.id
        end
        table.sort(target_history, function(a,b) return a.order<b.order end)
        -- do clean up
        local cleaned = {} 
        local delete = {}
        for i = #target_history, 1 , -1 do
          local entry = target_history[i]
          local delete_it
          if cleaned[entry.target] then
            -- we got a newer entry for this target than this, so this one can go
            delete_it = true
          else
            -- haven't got this one, so this is the last one for this target
            cleaned[entry.target] = true
            if entry.weight == 0 then
              delete_it = true
            end
          end
          if delete_it then
            delete[#delete+1] = entry
          end
        end
        
        -- do we need to cleanup?
        -- either nothing left, or when 10x more outdated than active entries
        if (#cleaned == 0 and #delete > 0) or
           (#delete >= (math.max(#cleaned,1)*10)) then
-- TODO: make sure we're not sending update events, one event at the end, based on the
-- post of the new entry should suffice
          for _, entry in ipairs(delete) do
            -- ignoring errors here, deleting by id, so should not matter
            local ok, err = dao_factory.targets:delete({ id = entry.id })
          end
        end
      end
      
      crud.post(self.params, dao_factory.targets)
    end,
  },
}
