local responses = require "kong.tools.responses"
local validations = require "kong.dao.schemas_validation"
local app_helpers = require "lapis.application"
local utils = require "kong.tools.utils"
local is_uuid = validations.is_valid_uuid

local _M = {}

function _M.find_api_by_name_or_id(self, dao_factory, helpers)
  local fetch_keys = {
    [is_uuid(self.params.name_or_id) and "id" or "name"] = self.params.name_or_id
  }
  self.params.name_or_id = nil

  local rows, err = dao_factory.apis:find_by_keys(fetch_keys)
  if err then
    return helpers.yield_error(err)
  end

  self.api = rows[1]
  if not self.api then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.find_consumer_by_username_or_id(self, dao_factory, helpers)
  local fetch_keys = {
    [is_uuid(self.params.username_or_id) and "id" or "username"] = self.params.username_or_id
  }
  self.params.username_or_id = nil

  local rows, err = dao_factory.consumers:find_by_keys(fetch_keys)
  if err then
    return helpers.yield_error(err)
  end

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

  for k, _ in pairs(self.params) do
    if not dao_collection._schema.fields[k] then
      self.params[k] = nil
    end
  end

  local data, err = dao_collection:find_by_keys(self.params, size, offset)
  if err then
    return app_helpers.yield_error(err)
  end

  local total, err = dao_collection:count_by_keys(self.params)
  if err then
    return app_helpers.yield_error(err)
  end

  local next_url
  if data.next_page then
    -- Parse next URL, if there are no elements then don't append it
    local next_total, err = dao_collection:count_by_keys(self.params, data.next_page)
    if err then
      return app_helpers.yield_error(err)
    end

    if next_total > 0 then
      next_url = self:build_url(self.req.parsed_url.path, {
        port = self.req.parsed_url.port,
        query = ngx.encode_args {
          offset = ngx.encode_base64(data.next_page),
          size = size
        }
      })
    end

    data.next_page = nil
  end

  -- This check is required otherwise the response is going to be a
  -- JSON Object and not a JSON array. The reason is because an empty Lua array `{}`
  -- will not be translated as an empty array by cjson, but as an empty object.
  local result = #data == 0 and "{\"data\":[],\"total\":0}" or {data = data, ["next"] = next_url, total = total}

  return responses.send_HTTP_OK(result, type(result) ~= "table")
end

function _M.get(params, dao_collection)
  local rows, err = dao_collection:find_by_keys(params)
  if err then
    return app_helpers.yield_error(err)
  elseif rows[1] == nil then
    return responses.send_HTTP_NOT_FOUND()
  else
    return responses.send_HTTP_OK(rows[1])
  end
end

function _M.put(params, dao_collection)
  local res, new_entity, err

  res, err = dao_collection:find_by_primary_key(params)
  if err then
    return app_helpers.yield_error(err)
  end

  if res then
    new_entity, err = dao_collection:update(params, true)
    if not err then
      return responses.send_HTTP_OK(new_entity)
    end
  else
    new_entity, err = dao_collection:insert(params)
    if not err then
      return responses.send_HTTP_CREATED(new_entity)
    end
  end

  if err then
    return app_helpers.yield_error(err)
  end
end

function _M.post(params, dao_collection, success)
  local data, err = dao_collection:insert(params)
  if err then
    return app_helpers.yield_error(err)
  else
    if success then success(utils.deep_copy(data)) end
    return responses.send_HTTP_CREATED(data)
  end
end

function _M.patch(params, dao_collection, where_t)
  local updated_entity, err = dao_collection:update(params, false, where_t)
  if err then
    return app_helpers.yield_error(err)
  elseif updated_entity == nil then
    return responses.send_HTTP_NOT_FOUND()
  else
    return responses.send_HTTP_OK(updated_entity)
  end
end

function _M.delete(primary_key_t, dao_collection, where_t)
  local ok, err = dao_collection:delete(primary_key_t, where_t)
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