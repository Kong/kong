local responses = require "kong.tools.responses"
local app_helpers = require "lapis.application"

local _M = {}

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

function _M.put(self, dao_collection)
  local new_entity, err
  if self.params.id then
    new_entity, err = dao_collection:update(self.params)
    if not err then
      return responses.send_HTTP_OK(new_entity)
    end
  else
    new_entity, err = dao_collection:insert(self.params)
    if not err then
      return responses.send_HTTP_CREATED(new_entity)
    end
  end

  if err then
    return app_helpers.yield_error(err)
  end
end

function _M.post(self, dao_collection)
  local data, err = dao_collection:insert(self.params)
  if err then
    return app_helpers.yield_error(err)
  else
    return responses.send_HTTP_CREATED(data)
  end
end

function _M.patch(params, dao_collection)
  local new_entity, err = dao_collection:update(params)
  if err then
    return app_helpers.yield_error(err)
  else
    return responses.send_HTTP_OK(new_entity)
  end
end

function _M.delete(entity_id, dao_collection)
  local ok, err = dao_collection:delete(entity_id)
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
