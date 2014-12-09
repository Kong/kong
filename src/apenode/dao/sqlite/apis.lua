local utils = require "apenode.dao.sqlite.utils"

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

  self.save_stmt = database:prepare("")
  self.update_stmt = database:prepare("")
  self.delete_stmt = database:prepare("")
  self.select_all_stmt = database:prepare("SELECT * FROM apis LIMIT :page, :size")
  self.select_by_id_stmt = database:prepare("SELECT * FROM apis WHERE id = ?")
  self.select_by_host_stmt = database:prepare("SELECT * FROM apis WHERE public_dns = ?")
end

function Apis:save(api)

end

function Apis:update(api)

end

function Apis:delete(id)

end

function Apis:get_all(page, size)
  return utils.select_paginated(self.select_all_stmt, page, size)
end

function Apis:get_by_id(id)
  return utils.select_by_key(self.select_by_id_stmt, id)
end

function Apis:get_by_host(public_dns)
  return utils.select_by_key(self.select_by_host_stmt, public_dns)
end

return Apis
