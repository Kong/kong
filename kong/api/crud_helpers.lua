local responses = require "kong.tools.responses"
local validations = require "kong.dao.schemas_validation"
local app_helpers = require "lapis.application"
local utils = require "kong.tools.utils"

local _M = {}

function _M.find_api_by_name_or_id(self, dao_factory, helpers)
  local fetch_keys = {
    [validations.is_valid_uuid(self.params.name_or_id) and "id" or "name"] = self.params.name_or_id
  }
  self.params.name_or_id = nil

  local data, err = dao_factory.apis:find_by_keys(fetch_keys)
  if err then
    return helpers.yield_error(err)
  end

  self.api = data[1]
  if not self.api then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.find_consumer_by_username_or_id(self, dao_factory, helpers)
  local fetch_keys = {
    [validations.is_valid_uuid(self.params.username_or_id) and "id" or "username"] = self.params.username_or_id
  }
  self.params.username_or_id = nil

  local data, err = dao_factory.consumers:find_by_keys(fetch_keys)
  if err then
    return helpers.yield_error(err)
  end

  self.consumer = data[1]
  if not self.consumer then
    return helpers.responses.send_HTTP_NOT_FOUND()
  end
end

function _M.paginated_set(self, dao_collection)
  local size = self.params.size and tonumber(self.params.size) or 100
  local offset = self.params.offset and ngx.decode_base64(self.params.offset) or nil

  self.params.size = nil
  self.params.offset = nil

  local data, err = dao_collection:find_by_keys(self.params, size, offset)
  if err then
    return app_helpers.yield_error(err)
  end

  local next_url
  if data.next_page then
    next_url = self:build_url(self.req.parsed_url.path, {
      port = self.req.parsed_url.port,
      query = ngx.encode_args({
                offset = ngx.encode_base64(data.next_page),
                size = size
              })
    })
    data.next_page = nil
  end

  -- This check is required otherwise the response is going to be a
  -- JSON Object and not a JSON array. The reason is because an empty Lua array `{}`
  -- will not be translated as an empty array by cjson, but as an empty object.
  local result = #data == 0 and "{\"data\":[]}" or {data=data, ["next"]=next_url}

  return responses.send_HTTP_OK(result, type(result) ~= "table")
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

function _M.patch(new_entity, old_entity, dao_collection)
  for k, v in pairs(new_entity) do
    old_entity[k] = v
  end

  local updated_entity, err = dao_collection:update(old_entity)
  if err then
    return app_helpers.yield_error(err)
  else
    return responses.send_HTTP_OK(updated_entity)
  end
end

function _M.delete(where_t, dao_collection)
  local ok, err = dao_collection:delete(where_t)
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
