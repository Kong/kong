-- Copyright (C) Mashape, Inc.
local inspect = require "inspect"
local helpers = require "apenode.dao.sqlite.helpers"

local Apis = {}
Apis.__index = Apis

setmetatable(Apis, {
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function Apis:_init(database)
  self._db = database
end

function Apis:get_by_host(public_dns)

end

function Apis:get_all()
  local iter, a = self._db:nrows("SELECT * FROM apis")
  return helpers.iterator_to_table(iter, a)
end

function Apis:get_by_id(id)

end

function Apis:save(api)

end

function Apis:update(api)

end

function Apis:delete(id)

end

return Apis