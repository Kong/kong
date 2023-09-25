local utils = require("kong.tools.utils")
local cjson = require("cjson.safe")
local isempty = require("table.isempty")


local inflate = utils.inflate_gzip
local deflate = utils.deflate_gzip
local cjson_decode = cjson.decode
local cjson_encode = cjson.encode


local get_topologically_sorted_schema_names = require("kong.db.declarative.export").get_topologically_sorted_schema_names


local error = error
local ipairs = ipairs
local assert = assert


local HASH
local META
local CONFIG
local MAX_ENTITIES = 1000


local function send_binary(wb, tbl)
  local _, err = wb:send_binary(cjson_encode(tbl))
  if err then
    return error("unable to send updated configuration to data plane: " .. err)
  end
end


local function send_configuration_payload(wb, payload)
  local timetamp = payload.timestamp
  local config = payload.config
  local hashes = payload.hashes
  local hash = hashes.config

  send_binary(wb, {
    type = "reconfigure:start",
    hash = hash,
    meta = {
      timestamp = timetamp,
      format_version = config._format_version,
      default_workspace = kong.default_workspace,
      hashes = hashes,
    }
  })

  utils.yield(false, "timer")

  local batch = kong.table.new(0, MAX_ENTITIES)
  for _, name in ipairs(get_topologically_sorted_schema_names()) do
    local entities = config[name]
    if entities and not isempty(entities) then
      local count = #entities
      if count <= MAX_ENTITIES then
        send_binary(wb, {
          type = "entities",
          hash = hash,
          name = name,
          data = assert(deflate(assert(cjson_encode(entities)))),
        })

        utils.yield(true, "timer")

      else
        local i = 0
        for j, entity in ipairs(entities) do
          i = i + 1
          batch[i] = entity
          if i == MAX_ENTITIES or j == count then
            send_binary(wb, {
              type = "entities",
              hash = hash,
              name = name,
              data = assert(deflate(assert(cjson_encode(batch)))),
            })

            utils.yield(true, "timer")
            kong.table.clear(batch)
            i = 0
          end
        end
      end
    end
  end

  send_binary(wb, {
    type = "reconfigure:end",
    hash = hash,
  })
end


local function reset_values()
  HASH = nil
  META = nil
  CONFIG = nil
end


local function reconfigure_start(msg)
  reset_values()
  HASH = msg.hash
  META = msg.meta
  CONFIG = {
    _transform = false,
    _format_version = META.format_version
  }
end


local function process_entities(msg)
  assert(HASH == msg.hash, "reconfigure hash mismatch")
  local name = msg.name
  local entities = assert(cjson_decode(inflate(msg.data)))
  if CONFIG[name] then
    local count = #CONFIG[name]
    for i, entity in ipairs(entities) do
      CONFIG[name][count + i] = entity
    end

  else
    CONFIG[name] = entities
  end
end


local function reconfigure_end(msg)
  assert(HASH == msg.hash, "reconfigure hash mismatch")
  local data = {
    config = CONFIG,
    hashes = META.hashes,
    timestamp = META.timestamp,
  }
  reset_values()
  return data
end


return {
  send_configuration_payload = send_configuration_payload,
  reconfigure_start = reconfigure_start,
  process_entities = process_entities,
  reconfigure_end = reconfigure_end,
}
