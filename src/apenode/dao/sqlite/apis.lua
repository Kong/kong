local BaseDao = require "apenode.dao.sqlite.base_dao"

local Apis = {}
Apis.__index = Apis

setmetatable(Apis, {
  __index = BaseDao,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function Apis:_init(database)
  BaseDao:_init(database)

  self.insert_stmt = database:prepare [[
    INSERT INTO apis(name,
                     public_dns,
                     target_url,
                     authentication_type)
    VALUES(:name,
           :public_dns,
           :target_url,
           :authentication_type);
  ]]

  self.update_stmt = database:prepare [[
    UPDATE apis
    SET name = :name,
        public_dns = :public_dns,
        target_url = :target_url,
        authentication_type = :authentication_type
    WHERE id = :id;
  ]]

  self.delete_stmt = database:prepare [[
    DELETE FROM apis WHERE id = ?;
  ]]

  self.select_count_stmt = database:prepare [[
    SELECT COUNT(*) FROM apis;
  ]]

  self.select_all_stmt = database:prepare [[
    SELECT * FROM apis LIMIT :page, :size;
  ]]

  self.select_by_id_stmt = database:prepare [[
    SELECT * FROM apis WHERE id = ?;
  ]]

  self.select_by_host_stmt = database:prepare [[
    SELECT * FROM apis WHERE public_dns = ?;
  ]]
end

function Apis:get_by_host(public_dns)
  self.select_by_host_stmt:bind_values(public_dns)
  return self:exec_select_stmt(self.select_by_host_stmt)
end

return Apis
