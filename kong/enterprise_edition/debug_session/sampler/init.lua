-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local debug_instrumentation = require "kong.enterprise_edition.debug_session.instrumentation"
local span_attributes = require "kong.enterprise_edition.debug_session.instrumentation.attributes".SAMPLER_ATTRIBUTES
local utils = require "kong.enterprise_edition.debug_session.utils"

local pl_update = require("pl.tablex").update
local schema = require("resty.router.schema")
local router = require("resty.router.router")
local context = require("resty.router.context")
local uuid = require("kong.tools.uuid")

local log = utils.log
local ngx_ERR = ngx.ERR
local ngx_DEBUG = ngx.DEBUG

local _M = {}
_M.__index = _M


local function find_in_root_span(attr, cast_to)
  local root_span = debug_instrumentation.get_root_span()
  local val = root_span and root_span.attributes and root_span.attributes[attr]
  if val and cast_to == "Int" then
    return tonumber(val)
  end
  return val
end

function _M.collect_sampler_fields_map()
  local map = {}
  for _, attr in pairs(span_attributes) do
    map[attr.name] = {
      type = attr.type,
      getter = function() return find_in_root_span(attr.name, attr.type) end
    }
    -- additionally register the alias. This is helpful to maintain
    -- a consistent API with the ATC Router
    if attr.alias then
      map[attr.alias] = {
        type = attr.type,
        -- still point to the same getter, we're only registering a alias field
        getter = function() return find_in_root_span(attr.name, attr.type) end
      }
    end
  end
  return map
end

function _M:new()
  local instance = setmetatable({}, self)
  -- will be filled by child samplers
  instance.fields = {}
  instance.router_mod = router
  instance.context_mod = context
  instance.schema_mod = schema
  instance.matcher_uuid = uuid.uuid()
  return instance
end

function _M:init_worker()
  -- Do this once at the beginning of the worker lifecycle
  log(ngx_DEBUG, "initializing worker")
  self:update_fields()
  self:load_schema()
  self:initialize_router()
end


function _M:update_fields()
  -- Receives a map of fields and their types
  -- where the key is the name of the field and the
  -- value is a map of its type and the getter function (where to load the value from )
  local sampler_fields_map = self:collect_sampler_fields_map()
  log(ngx_DEBUG, "updating fields map")
  pl_update(self.fields, sampler_fields_map)
end

function _M:load_schema()
  -- Implement load_schema
  self.schema = self.schema_mod.new()
  -- register known fields
  for field, attrs in pairs(self.fields) do
    log(ngx_DEBUG, "registering schema for field ", field)
    self.schema:add_field(field, attrs.type)
  end
  -- sets up context based on schema
  log(ngx_DEBUG, "setting up context for schema")
  self.context = self.context_mod.new(self.schema)
end

function _M:initialize_router()
  -- initialize router against schema
  log(ngx_DEBUG, "initializing router")
  self.router = self.router_mod.new(self.schema)
end

function _M:add_matcher(expr)
  self.expr = expr
  log(ngx_DEBUG, "adding matcher with expression: ", self.expr)
  local ok, err = self.router:add_matcher(0, self.matcher_uuid, self.expr) -- TODO: error handling for invalid expr?
  if not ok then
    -- For now, trust that the `expr` is validated clientsided
    log(ngx_ERR, "failed to add matcher: ", err)
  end
end

function _M:remove_matcher()
  self.expr = nil
  local ok, err = self.router:remove_matcher(self.matcher_uuid)
  if not ok then
    log(ngx_ERR, "failed to remove matcher: ", err)
  end
end

function _M:populate_context()
  self.context:reset()
  for field, attrs in pairs(self.fields) do
    local value = attrs.getter()
    if value and type(value) ~= "table" then
      log(ngx_DEBUG, "populating context for field ", field, " with value ", value)
      self.context:add_value(field, value)
    end
  end
end

function _M:sample_in()
  -- Take a shortcut here, no need to run the router
  -- when no expression is defined.
  if not self.expr or self.expr == "" then
    log(ngx_DEBUG, "no expression found, collecting sample")
    return true
  end
  log(ngx_DEBUG, "populating context")
  self:populate_context()
  log(ngx_DEBUG, "running sampler against context with expression: ", self.expr)
  local res = self.router:execute(self.context)
  log(ngx_DEBUG, "sampler returned: ", tostring(res))
  return res
end

return _M
