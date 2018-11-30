local BasePlugin = require "kong.plugins.base_plugin"
local responses = require "kong.tools.responses"
local Entity = require "kong.db.schema.entity"
local utils = require "kong.plugins.request-validator.utils"


local gen_schema = utils.gen_schema
local get_req_body_json = utils.get_req_body_json


local RequestValidator = BasePlugin:extend()
local entity_cache = setmetatable({}, {__mode = "k"})


RequestValidator.PRIORITY = 200
RequestValidator.VERSION = "0.1.0"


function RequestValidator:new()
  RequestValidator.super.new(self, "request-validator")
end


function RequestValidator:access(conf)
  RequestValidator.super.access(self)

  -- try to retrieve cached request body schema entity
  -- if it isn't in cache, create it
  local entity = entity_cache[conf]

  if not entity then
    -- prepare the schema, adding any fields that are required by Kong's schema
    -- validator, but not specified in the request schema - such as `name` and
    -- `pk`
    local schema, err = gen_schema(conf.body_schema)
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    entity, err = Entity.new(schema)
    if err then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR("failed creating entity from schema")
    end

    entity_cache[conf] = entity
  end

  local body, err = get_req_body_json()
  if err then
    return responses.send_HTTP_BAD_REQUEST(err)
  end

  -- try to validate body against schema
  local ok = entity:validate(body)
  if not ok then
    return responses.send_HTTP_BAD_REQUEST("request body doesn't conform to schema")
  end
end


return RequestValidator
