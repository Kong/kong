-- Copyright (C) Mashape, Inc.

local utils = require "apenode.core.utils"

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
    return utils.success(dao[collection_name]:get_all())
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

return BaseController