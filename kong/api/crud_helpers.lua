local cjson         = require "cjson"
local utils         = require "kong.tools.utils"
local responses     = require "kong.tools.responses"
local app_helpers   = require "lapis.application"


local decode_base64 = ngx.decode_base64
local encode_base64 = ngx.encode_base64
local encode_args   = ngx.encode_args
local tonumber      = tonumber
local ipairs        = ipairs
local next          = next
local type          = type


local function post_process_row(row, post_process)
  return type(post_process) == "function" and post_process(row) or row
end


local _M = {}

--- Will look up a value in the dao.
-- Either by `id` field or by the field named by 'alternate_field'. If the value
-- is NOT a uuid, then by the 'alternate_field'. If it is a uuid then it will
-- first try the `id` field, if that doesn't yield anything it will try again
-- with the 'alternate_field'.
-- @param dao the specific dao to search
-- @param filter filter table to use, tries will add to this table
-- @param value the value to look up
-- @param alternate_field the field to use if it is not a uuid, or not found in `id`
function _M.find_by_id_or_field(dao, filter, value, alternate_field)
  filter = filter or {}
  local is_uuid = utils.is_valid_uuid(value)
  filter[is_uuid and "id" or alternate_field] = value

  local rows, err = dao:find_all(filter)
  if err then
    return nil, err
  end

  if is_uuid and not next(rows) then
    -- it's a uuid, but yielded no results, so retry with the alternate field
    filter.id = nil
    filter[alternate_field] = value
    rows, err = dao:find_all(filter)
    if err then
      return nil, err
    end
  end
  return rows
end

function _M.find_api_by_name_or_id(self, dao_factory, helpers)
  local rows, err = _M.find_by_id_or_field(dao_factory.apis, {},
                                           self.params.api_name_or_id, "name")

  if err then
    return helpers.yield_error(err)
  end
  self.params.api_name_or_id = nil

  -- We know name and id are unique for APIs, hence if we have a row, it must be the only one
  self.api = rows[1]
  if not self.api then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.find_plugin_by_filter(self, dao_factory, filter, helpers)
  local rows, err = dao_factory.plugins:find_all(filter)
  if err then
    return helpers.yield_error(err)
  end

  -- We know the id is unique, so if we have a row, it must be the only one
  self.plugin = rows[1]
  if not self.plugin then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end


function _M.find_consumer_by_username_or_id(self, dao_factory, helpers)
  local username_or_id = self.params.username_or_id
  local db = assert(dao_factory.db.new_db)
  local consumer, err
  if utils.is_valid_uuid(username_or_id) then
    consumer, err = db.consumers:select({ id = username_or_id })

    if err then
      return helpers.yield_error(err)
    end
  end

  if not consumer then
    consumer, err = db.consumers:select_by_username(username_or_id)

    if err then
      return helpers.yield_error(err)
    end
  end

  self.params.username_or_id = nil

  -- We know username and id are unique, so if we have a row, it must be the only one
  self.consumer = consumer
  if not self.consumer then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end


function _M.find_upstream_by_name_or_id(self, dao_factory, helpers)
  local rows, err = _M.find_by_id_or_field(dao_factory.upstreams, {},
                                           self.params.upstream_name_or_id, "name")

  if err then
    return helpers.yield_error(err)
  end
  self.params.upstream_name_or_id = nil

  -- We know name and id are unique, so if we have a row, it must be the only one
  self.upstream = rows[1]
  if not self.upstream then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

-- this function will return the exact target if specified by `id`, or just
-- 'any target entry' if specified by target (= 'hostname:port')
function _M.find_target_by_target_or_id(self, dao_factory, helpers)
  local rows, err = _M.find_by_id_or_field(dao_factory.targets, {},
                                           self.params.target_or_id, "target")

  if err then
    return helpers.yield_error(err)
  end
  self.params.target_or_id = nil

  -- if looked up by `target` property we can have multiple targets here, but
  -- anyone will do as they all have the same 'target' field, so just pick
  -- the first
  self.target = rows[1]
  if not self.target then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.paginated_set(self, dao_collection, post_process)
  local size   = self.params.size   and tonumber(self.params.size) or 100
  local offset = self.params.offset and decode_base64(self.params.offset)

  self.params.size   = nil
  self.params.offset = nil

  local filter_keys = next(self.params) and self.params

  local rows, err, offset = dao_collection:find_page(filter_keys, offset, size)
  if err then
    return app_helpers.yield_error(err)
  end

  local total_count, err = dao_collection:count(filter_keys)
  if err then
    return app_helpers.yield_error(err)
  end

  local next_url
  if offset then
    offset = encode_base64(offset)
    next_url = self:build_url(self.req.parsed_url.path, {
      port     = self.req.parsed_url.port,
      query    = encode_args {
        offset = offset,
        size   = size
      }
    })
  end

  local data = setmetatable(rows, cjson.empty_array_mt)

  if type(post_process) == "function" then
    for i, row in ipairs(rows) do
      data[i] = post_process(row)
    end
  end

  return responses.send_HTTP_OK {
    data     = data,
    total    = total_count,
    offset   = offset,
    ["next"] = next_url
  }
end

-- Retrieval of an entity.
-- The DAO requires to be given a table containing the full primary key of the entity
function _M.get(primary_keys, dao_collection, post_process)
  local row, err = dao_collection:find(primary_keys)
  if err then
    return app_helpers.yield_error(err)
  elseif row == nil then
    return responses.send_HTTP_NOT_FOUND()
  else
    return responses.send_HTTP_OK(post_process_row(row, post_process))
  end
end

--- Insertion of an entity.
function _M.post(params, dao_collection, post_process)
  local data, err = dao_collection:insert(params)
  if err then
    return app_helpers.yield_error(err)
  else
    return responses.send_HTTP_CREATED(post_process_row(data, post_process))
  end
end

--- Partial update of an entity.
-- Filter keys must be given to get the row to update.
function _M.patch(params, dao_collection, filter_keys, post_process)
  if not next(params) then
    return responses.send_HTTP_BAD_REQUEST("empty body")
  end
  local updated_entity, err = dao_collection:update(params, filter_keys)
  if err then
    return app_helpers.yield_error(err)
  elseif updated_entity == nil then
    return responses.send_HTTP_NOT_FOUND()
  else
    return responses.send_HTTP_OK(post_process_row(updated_entity, post_process))
  end
end

-- Full update of an entity.
-- First, we check if the entity body has primary keys or not,
-- if it does, we are performing an update, if not, an insert.
function _M.put(params, dao_collection, post_process)
  local new_entity, err

  -- If a wrapper is detected, give it the new upsert behavior
  if dao_collection.unwrapped then
    local entity = dao_collection.unwrapped
    local pk = entity.schema:extract_pk_values(params)
    local new_entity, err = entity:upsert(pk, params)
    if not err then
      return responses.send_HTTP_OK(post_process_row(new_entity, post_process))
    end
    return app_helpers.yield_error(err)
  end

  local model = dao_collection.model_mt(params)
  if not model:has_primary_keys() then
    -- If entity body has no primary key, deal with an insert
    new_entity, err = dao_collection:insert(params)
    if not err then
      return responses.send_HTTP_CREATED(post_process_row(new_entity, post_process))
    end
  else
    -- If entity body has primary key, deal with update
    new_entity, err = dao_collection:update(params, params, {full = true})
    if not err then
      if not new_entity then
        return responses.send_HTTP_NOT_FOUND()
      end

      return responses.send_HTTP_OK(post_process_row(new_entity, post_process))
    end
  end

  if err then
    return app_helpers.yield_error(err)
  end
end

--- Delete an entity.
-- The DAO requires to be given a table containing the full primary key of the entity
function _M.delete(primary_keys, dao_collection)
  local ok, err = dao_collection:delete(primary_keys)
  if not ok then
    if err then
      return app_helpers.yield_error(err)
    else
      return responses.send_HTTP_NOT_FOUND()
    end
  else
    return responses.send_HTTP_NO_CONTENT()
  end
end

return _M
