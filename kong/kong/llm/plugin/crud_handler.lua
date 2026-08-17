local DEFAULT_EVENT_NAME = "managed_event"

-- crud event handler for traditional mode
local function new(handler, plugin_name, event_name)
  if type(handler) ~= "function" then
    error("handler must be a function", 2)
  end
  if type(plugin_name) ~= "string" then
    error("plugin_name must be a string", 2)
  end

  if kong.configuration.database == "off" or not (kong.worker_events and kong.worker_events.register) then
    return
  end

  event_name = event_name or DEFAULT_EVENT_NAME

  local worker_events = kong.worker_events
  local cluster_events = kong.configuration.role == "traditional" and kong.cluster_events

  worker_events.register(handler, plugin_name, event_name)

  -- event handlers to update balancer instances
  worker_events.register(function(data)
    if data.entity.name == plugin_name then
      -- remove metatables from data
      local post_data = {
        operation = data.operation,
        entity = data.entity,
      }

      -- broadcast this to all workers becasue dao events are sent using post_local
      worker_events.post(plugin_name, event_name, post_data)

      if cluster_events then
        cluster_events:broadcast(plugin_name .. ":" .. event_name, post_data)
      end
    end
  end, "crud", "plugins")

  if cluster_events then
    cluster_events:subscribe(plugin_name .. ":" .. event_name, function(data)
      -- remove metatables from data
      local post_data = {
        operation = data.operation,
        entity = data.entity,
      }
      worker_events.post(plugin_name, event_name, post_data)
    end)
  end

end

return {
  new = new,
}