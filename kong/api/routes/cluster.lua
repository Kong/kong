local singletons = require "kong.singletons"
local responses = require "kong.tools.responses"
local cache = require "kong.tools.database_cache"
local event_types = require("kong.core.events").TYPES

local pairs = pairs
local table_insert = table.insert
local string_upper = string.upper

local OTHER = "other"

local function get_members(filters)
  local members, err = singletons.serf:members()
  if err then
    return nil, err
  end

  local result = {}
  for _, member in pairs(members) do
    local matches = true
    if filters then
      for k, v in pairs(filters) do
        matches = matches and member[k] == v
      end
    end
    if matches then
      table_insert(result, {
        name = member.name,
        address = member.addr,
        status = member.status
      })
    end
  end

  return result
end

local function increment(key, value)
  local ok, err = cache.incr(key, value)
  if not ok and err == "not found" then
    cache.rawset(key, value)
  elseif not ok then
    ngx.log(ngx.ERR, err)
  end
end

return {
  ["/cluster/"] = {
    GET = function(self, dao_factory, helpers)

      local events_stat = {
        total = cache.get(cache.event_key()),
        other = cache.get(cache.event_key(OTHER))
      }

      for _, v in pairs(event_types) do
        events_stat[v] = cache.get(cache.event_key(v))
      end

      return responses.send_HTTP_OK({
        nodes = self:build_url(self.req.parsed_url.path..
          (string.sub(self.req.parsed_url.path, string.len(self.req.parsed_url.path)) == "/" and
            "" or "/").."nodes", {
          port = self.req.parsed_url.port,
        }),
        events = events_stat
      })
    end
  },

  ["/cluster/nodes/"] = {
    GET = function(self, dao_factory, helpers)
      local members, err = get_members(self.params)
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      local result = {data = members}
      result.total = #result.data

      return responses.send_HTTP_OK(result)
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

  ["/cluster/nodes/:node_name"] = {
    before = function(self, dao_factory, helpers)
      local members, err = get_members({name = self.params.node_name})
      if err then
        return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
      end

      if #members == 1 then
        self.node = members[1]
      else
        return helpers.responses.send_HTTP_NOT_FOUND()
      end
    end,

    GET = function(self, dao_factory, helpers)
      return responses.send_HTTP_OK(self.node)
    end,

    DELETE = function(self, dao_factory)
      local _, err = singletons.serf:invoke_signal("force-leave", self.node.name)
      if err then
        return responses.send_HTTP_BAD_REQUEST(err)
      end

      return responses.send_HTTP_NO_CONTENT()
    end
  },

  ["/cluster/events/"] = {
    POST = function(self, dao_factory, helpers)
      local message_t = self.params

      -- The type is always upper case
      if message_t.type then
        message_t.type = string_upper(message_t.type)
      end

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
      singletons.events:publish(message_t.type, message_t)

      -- Increment counter
      increment(cache.event_key(), 1)
      increment(cache.event_key(message_t.type or OTHER), 1)

      return responses.send_HTTP_OK()
    end
  }
}
