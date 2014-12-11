local BaseDao = require "apenode.dao.sqlite.base_dao"

local Accounts = {}
Accounts.__index = Accounts

setmetatable(Accounts, {
  __index = BaseDao,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function Accounts:_init(database)
  BaseDao:_init(database)

  self.insert_stmt = database:prepare [[
    INSERT INTO accounts(provider_id) VALUES(:provider_id);
  ]]

  self.update_stmt = database:prepare [[
    UPDATE accounts SET provider_id = :provider_id WHERE id = :id;
  ]]

  self.delete_stmt = database:prepare [[
    DELETE FROM accounts WHERE id = ?;
  ]]

  self.select_count_stmt = database:prepare [[
    SELECT COUNT(*) FROM accounts;
  ]]

  self.select_all_stmt = database:prepare [[
    SELECT * FROM accounts LIMIT :page, :size;
  ]]

  self.select_by_id_stmt = database:prepare [[
    SELECT * FROM accounts WHERE id = ?;
  ]]

  self.select_by_provider_id_stmt = database:prepare [[
    SELECT * FROM accounts WHERE provider_id = ?;
  ]]
end

function Accounts:get_by_provider_id(provider_id)
  self.select_by_provider_id_stmt:bind_values(provider_id)
  return self:exec_select_stmt(self.select_by_provider_id_stmt)
end

return Accounts
