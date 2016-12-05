local singletons = require "kong.singletons"
local responses = require "kong.tools.responses"
local constants = require "kong.constants"
local ev = require "resty.worker.events"

local pairs = pairs
local table_insert = table.insert
local string_upper = string.upper

return {
  ["/cluster/"] = {
    GET = function(self, dao_factory, helpers)
      local members, err = singletons.serf:members()
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      local result = {data = {}}
      for _, v in pairs(members) do
        if not self.params.status or (self.params.status and v.status == self.params.status) then
          table_insert(result.data, {
            name = v.name,
            address = v.addr,
            status = v.status
          })
        end
      end

      result.total = #result.data
      return responses.send_HTTP_OK(result)
    end,

    DELETE = function(self, dao_factory)
      if not self.params.name then
        return responses.send_HTTP_BAD_REQUEST("Missing node \"name\"")
      end

      local _, err = singletons.serf:invoke_signal("force-leave", self.params.name)
      if err then
        return responses.send_HTTP_BAD_REQUEST(err)
      end

      return responses.send_HTTP_OK()
    end,

    POST = function(self, dao_factory)
      if not self.params.address then
        return responses.send_HTTP_BAD_REQUEST("Missing node \"address\"")
      end

      local _, err = singletons.serf:invoke_signal("join", self.params.address)
      if err then
        return responses.send_HTTP_BAD_REQUEST(err)
      end

      return responses.send_HTTP_OK()
    end
  },

  ["/cluster/events/"] = {
    POST = function(self, dao_factory, helpers)
      local message_t = self.params

      -- The type is always upper case
      if not message_t or not message_t.type then
        return responses.send_HTTP_BAD_REQUEST()
      end
      
      message_t.type = string_upper(message_t.type)

      -- If it's an update, load the new entity too so it's available in the hooks
      if message_t.type == singletons.events.TYPES.ENTITY_UPDATED then
        message_t.old_entity = message_t.entity

        -- The schema may have multiple primary keys
        local find_args = {}
        for _, v in ipairs(message_t.primary_key) do
          find_args[v] = message_t.old_entity[v]
        end

        local res, err = singletons.dao[message_t.collection]:find_all(find_args)
        if err then
          return helpers.yield_error(err)
        elseif #res == 1 then
          message_t.entity = res[1]
        else
          -- This means that the entity has been deleted immediately after an update in the meanwhile that
          -- the system was still processing the update. A delete invalidation will come immediately after
          -- so we can ignore this event
          return responses.send_HTTP_OK()
        end
      end

      -- Trigger event in the node
      ev.post(constants.CACHE.CLUSTER, message_t.type, message_t)

      return responses.send_HTTP_OK()
    end
  }
}