local _Consumers = {}

local function delete_cascade_legacy(self, table_name, fk)
  local old_dao = self.db.old_dao
  local rows, err = old_dao[table_name]:find_all(fk)
  if err then
    ngx.log(ngx.ERR, "[consumers.delete_cascade] could not gather associated ",
                     "entities for delete cascade: ", err)
    return
  end

  for _, row in pairs(rows) do
    local row_pk, _, _, err  = old_dao[table_name].model_mt(row):extract_keys()
    if err then
      ngx.log(ngx.ERR, "[consumers.delete_cascade] could not extract pk while ",
                       "delete-cascading entity: ", err)

    else
      local _, err = old_dao[table_name]:delete(row_pk)
      if err then
        ngx.log(ngx.ERR, "[consumers.delete_cascade] could not delete-cascade entity: ", err)
      end
    end
  end
end


local function delete_cascade(self, table_name, fk)
  local entity = self.db[table_name]

  for row, err in entity:each_for_consumer(fk) do
    if not row then
      ngx.log(ngx.ERR, "[consumers.delete_cascade] could not gather associated ",
                     "entities for delete cascade: ", err)
      return
    end

    local row_pk = entity.schema:extract_pk_values(row)
    local _, err = entity:delete(row_pk)
    if err then
      ngx.log(ngx.ERR, "[consumers.delete_cascade] could not delete-cascade entity: ", err)
    end
  end
end


local function delete_cascade_all(self, consumer_id)
  local fk = { consumer_id = consumer_id }

  local wrapper = self.db.old_dao.daos["consumers"]
  local constraints = wrapper.constraints

  for table_name, _ in pairs(constraints.cascade) do
    delete_cascade_legacy(self, table_name, fk)
  end

  delete_cascade(self, "plugins", { id = consumer_id })
end


function _Consumers:delete(primary_key)
  delete_cascade_all(self, primary_key.id)
  return self.super.delete(self, primary_key)
end


function _Consumers:delete_by_username(username)
  local entity, err, err_t = self:select_by_username(username)
  if err then
    return nil, err, err_t
  end
  if not entity then
    return true
  end
  delete_cascade_all(self, entity.id)
  return self.super.delete_by_username(self, username)
end


return _Consumers
