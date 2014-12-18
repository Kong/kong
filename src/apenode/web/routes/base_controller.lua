-- Copyright (C) Mashape, Inc.

local cjson = require "cjson"
local stringy = require "stringy"

local BaseController = {}
BaseController.__index = BaseController

setmetatable(BaseController, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

local function render_list_response(req, data, total, page, size)
  local url = req.parsed_url.scheme .. "://" .. req.parsed_url.host .. ":" .. req.parsed_url.port .. req.parsed_url.path
  local result = {
    data = data,
    total = total
  }

  if page > 1 then
    result["previous"] = url .. "?" .. ngx.encode_args({page = page -1, size = size})
  end

  if page * size < total then
     result["next"] = url .. "?" .. ngx.encode_args({page = page + 1, size = size})
  end

  return result
end

local function decode_json(json, out)
  out = cjson.decode(json)
end

local function parse_params(model, params)
  for k,v in pairs(params) do
    if model._SCHEMA[k] and model._SCHEMA[k].type == "table" then
      -- It can either be a JSON map or a string array separated by comma
      local status, res = pcall(cjson.decode, v)
      if status then
        params[k] = res
      else
        params[k] = stringy.split(v, ",")
      end
    end
  end
  return params
end

function BaseController:_init(model)
  app:post("/" .. model._COLLECTION .. "/", function(self)
    local params = parse_params(model, self.params)
    local entity, err = model(params)

    if not entity then
      return utils.show_error(400, err)
    else
      local data, err = entity:save()
      if err then
        return utils.show_error(500, err)
      else
        return utils.created(data)
      end
    end
  end)

  app:get("/" .. model._COLLECTION .. "/", function(self)
    local params = parse_params(model, self.params)

    local page = 1
    local size = 10

    if params.page and tonumber(params.page) > 0 then
      page = tonumber(params.page)
    else
      page = 1
    end
    if params.size and tonumber(params.size) > 0 then
      size = tonumber(params.size)
    else
      size = 10
    end

    params.size = nil
    params.page = nil

    local inspect = require "inspect"
    print(inspect(params))

    local data, total, err = model.find(params, page, size)
    if err then
      return utils.show_error(500, err)
    end

    return utils.success(render_list_response(self.req, data, total, page, size))
  end)

  app:get("/" .. model._COLLECTION .. "/:id", function(self)
    local data, err = model.find_one({id = self.params.id})

    if err then
      return utils.show_error(500, err)
    end

    if data then
      return utils.success(data)
    else
      return utils.not_found()
    end
  end)

  app:delete("/" .. model._COLLECTION .. "/:id", function(self)

    local data, err = model.find_one({ id = self.params.id})
    if err then
      return utils.show_error(500, err)
    end

    if data then
      data:delete()
      return utils.success(data)
    else
      return utils.not_found()
    end
  end)

end

return BaseController
