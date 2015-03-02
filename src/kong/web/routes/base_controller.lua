-- Copyright (C) Mashape, Inc.

local stringy = require "stringy"
local Object = require "classic"
local cjson = require "cjson"
local json_params = require("lapis.application").json_params

local BaseController = Object:extend()

local function render_list_response(req, data, size)
  local next_url

  if data.next_page then
    local url = req.parsed_url.scheme.."://"..req.parsed_url.host..":"..req.parsed_url.port..req.parsed_url.path
    next_url = url.."?"..ngx.encode_args({offset = ngx.encode_base64(data.next_page), size = size})
    data.next_page = nil
  end

  -- This check is required otherwise the response is going to be a
  -- JSON Object and not a JSON array.
  if #data == 0 then
    return "{\"data\":[]}"
  else
    return { data = data, ["next"] = next_url }
  end
end

local function parse_params(dao_collection, params)
  for k,v in pairs(params) do
    if not dao_collection._schema[k] then
      params[k] = nil
    elseif dao_collection._schema[k].type == "table" and type(v) ~= "table" then
      if v == nil or stringy.strip(v) == "" then
        params[k] = nil
      else
        -- It can either be a JSON map or a string array separated by comma
        local status, res = pcall(cjson.decode, v)
        if status then
          params[k] = res
        else
          params[k] = stringy.split(v, ",")
        end
      end
    end
  end
  return params
end

local function parse_dao_error(err)
  local status
  if err.database then
    status = 500
    ngx.log(ngx.ERR, err.message)
  elseif err.unique then
    status = 409
  elseif err.foreign then
    status = 404
  elseif err.invalid_type and err.message.id then
    status = 404
  else
    status = 400
  end
  return utils.show_error(status, err.message)
end

function BaseController:new(dao_collection, collection)
  app:post("/"..collection.."/", function(self)
    local params = parse_params(dao_collection, self.params)
    local data, err = dao_collection:insert(params)
    if err then
      return parse_dao_error(err)
    else
      return utils.created(data)
    end
  end)

  app:get("/"..collection.."/", function(self)
    local size = self.params.size
    if size then
      size = tonumber(size)
    else
      size = 100
    end

    local offset = self.params.offset
    if offset then
      offset = ngx.decode_base64(offset)
    end

    local params = parse_params(dao_collection, self.params)
    local data, err = dao_collection:find_by_keys(params, size, offset)
    if err then
      return parse_dao_error(err)
    end

    local result = render_list_response(self.req, data, size)
    return utils.show_response(200, result, type(result) ~= "table")
  end)

  app:get("/"..collection.."/:id", function(self)
    local data, err = dao_collection:find_one(self.params.id)
    if err then
      return parse_dao_error(err)
    end
    if data then
      return utils.success(data)
    else
      return utils.not_found()
    end
  end)

  app:delete("/"..collection.."/:id", function(self)
    local ok, err = dao_collection:delete(self.params.id)
    if not ok then
      return parse_dao_error(err)
    else
      return utils.no_content()
    end
  end)

  app:put("/"..collection.."/:id", json_params(function(self)
    local params = parse_params(dao_collection, self.params)
    if self.params.id then
      params.id = self.params.id
    else
      utils.not_found()
    end

    local data, err = dao_collection:update(params)
    if err then
      return parse_dao_error(err)
    else
      return utils.success(data)
    end
  end))

end

return BaseController
