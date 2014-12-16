-- Copyright (C) Mashape, Inc.

local BaseModel = require "apenode.models.base_model"

local Api = {}
Api.__index = Api

setmetatable(Api, {
  __index = BaseModel, -- this is what makes the inheritance work
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end,
})

function Api:_init(t)
  BaseModel:_init("apis", t, {
      id = { type = "string", read_only = true },
      name = { type = "string", required = true },
      public_dns = { type = "string", required = true },
      target_url = { type = "string", required = true },
      created_at = { type = "number", read_only = true, default = os.time() }
  }) -- call the base class constructor]
end

function Api:find()

end

return Api
