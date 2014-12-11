local BaseDao = require "apenode.dao.sqlite.base_dao"

local Applications = {}
Applications.__index = Applications

setmetatable(Applications, {
  __index = BaseDao,
  __call = function (cls, ...)
    local self = setmetatable({}, cls)
    self:_init(...)
    return self
  end
})

function Applications:_init(database)
  BaseDao:_init(database)

  self.insert_stmt = database:prepare [[
    INSERT INTO applications(account_id,
                             public_key,
                             secret_key)
    VALUES(:account_id,
           :public_key,
           :secret_key);
  ]]

  self.update_stmt = database:prepare [[
    UPDATE applications
    SET account_id = :account_id,
        public_key = :public_key,
        secret_key = :secret_key
    WHERE id = :id;
  ]]

  self.delete_stmt = database:prepare [[
    DELETE FROM applications WHERE id = ?;
  ]]

  self.select_count_stmt = database:prepare [[
    SELECT COUNT(*) FROM applications;
  ]]

  self.select_all_stmt = database:prepare [[
    SELECT * FROM applications LIMIT :page, :size;
  ]]

  self.select_by_id_stmt = database:prepare [[
    SELECT * FROM applications WHERE id = ?;
  ]]

  self.select_by_account_id_stmt = database:prepare [[
    SELECT * FROM applications WHERE account_id = :account_id LIMIT :page, :size;
  ]]

  self.select_count_by_account_id_stmt = database:prepare [[
    SELECT COUNT(*) FROM applications WHERE account_id = ?;
  ]]

  self.select_by_keys_stmt = database:prepare [[
    SELECT * FROM applications WHERE public_key = ? AND secret_key = ?;
  ]]
end

function Applications:get_by_account_id(account_id, page, size)
  -- TODO all ine one query
  -- TODO handle errors for count request
  self.select_by_account_id_stmt:bind_names { account_id = account_id }
  local results = self:exec_paginated_stmt(self.select_by_account_id_stmt, page, size)

  self.select_count_by_account_id_stmt:bind_values(account_id)
  local count = self:exec_stmt(self.select_count_by_account_id_stmt)

  return results, count
end

function Applications:get_by_key(public_key, secret_key)
  self.select_by_keys_stmt:bind_values(public_key, secret_key)
  return self:exec_select_stmt(self.select_by_keys_stmt)
end

return Applications
