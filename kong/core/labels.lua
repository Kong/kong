local responses = require "kong.tools.responses"
local singletons = require "kong.singletons"

local function load_label_mappings_into_memory(api_id, consumer_id)
  local rows, err = singletons.dao.label_mappings:find_all {
    api_id = api_id,
    consumer_id = consumer_id,
  }
  if err then
    error(err)
  end

  local labels = {}

  if #rows > 0 then
    for _, row in ipairs(rows) do
        table.insert(labels,row.label_id)
    end
  end

  return labels
end

local function get_labels_for_api(api)
  local label_cache_key = singletons.dao.label_mappings:cache_key(api.id)
  local labels, err = singletons.cache:get(label_cache_key, nil,
                                           load_label_mappings_into_memory,
                                           api.id, nil)
  if err then
    responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  return labels
end

local function get_labels_for_consumer(consumer)
  local label_cache_key = singletons.dao.label_mappings:cache_key(nil,consumer.id)
  local labels, err = singletons.cache:get(label_cache_key, nil,
                                           load_label_mappings_into_memory, 
                                           nil, consumer.id)
  if err then
    responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
  end

  return labels
end

return {
  get_labels_for_api = get_labels_for_api,
  get_labels_for_consumer = get_labels_for_consumer,
}