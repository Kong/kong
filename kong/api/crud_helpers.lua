local responses = require "kong.tools.responses"
local validations = require "kong.dao.schemas_validation"
local app_helpers = require "lapis.application"
local utils = require "kong.tools.utils"
local is_uuid = validations.is_valid_uuid

local _M = {}

function _M.find_api_by_name_or_id(self, dao_factory, helpers)
  local filter_keys = {
    [is_uuid(self.params.name_or_id) and "id" or "name"] = self.params.name_or_id
  }
  self.params.name_or_id = nil

  local rows, err = dao_factory.apis:find_all(filter_keys)
  if err then
    return helpers.yield_error(err)
  end

  -- We know name and id are unique for APIs, hence if we have a row, it must be the only one
  self.api = rows[1]
  if not self.api then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.find_consumer_by_username_or_id(self, dao_factory, helpers)
  local filter_keys = {
    [is_uuid(self.params.username_or_id) and "id" or "username"] = self.params.username_or_id
  }
  self.params.username_or_id = nil

  local rows, err = dao_factory.consumers:find_all(filter_keys)
  if err then
    return helpers.yield_error(err)
  end

  -- We know username and id are unique, so if we have a row, it must be the only one
  self.consumer = rows[1]
  if not self.consumer then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.paginated_set(self, dao_collection)
  local size = self.params.size and tonumber(self.params.size) or 100
  local offset = self.params.offset and ngx.decode_base64(self.params.offset) or nil

  self.params.size = nil
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
  if offset ~= nil then
    next_url = self:build_url(self.req.parsed_url.path, {
      port = self.req.parsed_url.port,
      query = ngx.encode_args {
        offset = ngx.encode_base64(offset),
        size = size
      }
    })
  end

  -- This check is required otherwise the response is going to be a
  -- JSON Object and not a JSON array. The reason is because an empty Lua array `{}`
  -- will not be translated as an empty array by cjson, but as an empty object.
  local result = #rows == 0 and "{\"data\":[],\"total\":0}" or {data = rows, ["next"] = next_url, total = total_count}

  return responses.send_HTTP_OK(result, type(result) ~= "table")
end

-- Retrieval of an entity.
-- The DAO requires to be given a table containing the full primary key of the entity
function _M.get(primary_keys, dao_collection)
  local row, err = dao_collection:find(primary_keys)
  if err then
    return app_helpers.yield_error(err)
  elseif row == nil then
    return responses.send_HTTP_NOT_FOUND()
  else
    return responses.send_HTTP_OK(row)
  end
end

--- Insertion of an entity.
function _M.post(params, dao_collection, success)
  local data, err = dao_collection:insert(params)
  if err then
    return app_helpers.yield_error(err)
  else
    if success then success(utils.deep_copy(data)) end
    return responses.send_HTTP_CREATED(data)
  end
end

--- Partial update of an entity.
-- Filter keys must be given to get the row to update.
function _M.patch(params, dao_collection, filter_keys)
  local updated_entity, err = dao_collection:update(params, filter_keys)
  if err then
    return app_helpers.yield_error(err)
  elseif updated_entity == nil then
    return responses.send_HTTP_NOT_FOUND()
  else
    return responses.send_HTTP_OK(updated_entity)
  end
end

-- Full update of an entity.
-- First, we check if the entity body has primary keys or not,
-- if it does, we are performing an update, if not, an insert.
function _M.put(params, dao_collection)
  local new_entity, err

  local model = dao_collection.model_mt(params)
  if not model:has_primary_keys() then
    -- If entity body has no primary key, deal with an insert
    new_entity, err = dao_collection:insert(params)
    if not err then
      return responses.send_HTTP_CREATED(new_entity)
    end
  else
    -- If entity body has primary key, deal with update
    new_entity, err = dao_collection:update(params, params, {full = true})
    if not err then
      return responses.send_HTTP_OK(new_entity)
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
