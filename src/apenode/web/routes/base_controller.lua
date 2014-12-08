-- Copyright (C) Mashape, Inc.

local BaseController = {}
BaseController.__index = BaseController

setmetatable(BaseController, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function BaseController:_init(collection_name)

  app:get("/" .. collection_name .. "/", function(self)
    local page = tonumber(self.params.page)
    local size = tonumber(self.params.size)

    if not page or page <= 0 then page = 1 end
    if not size or size <= 0 then size = 10 end

    local data, total = dao[collection_name]:get_all(page, size)
    return utils.success(render_list_response(self.req, data, total, page, size))
  end)

  app:get("/" .. collection_name .. "/:id", function(self)
    local entity = dao[collection_name]:get_by_id(self.params.id)
    if entity then
      return utils.success(entity)
    else
      return utils.not_found()
    end
  end)

  app:delete("/" .. collection_name .. "/:id", function(self)
    local entity = dao[collection_name]:delete(self.params.id)
    if entity then
      return utils.success(entity)
    else
      return utils.not_found()
    end
  end)

end

function render_list_response(req, data, total, page, size)
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

return BaseController