local SKey_Meta = {}


function SKey_Meta:select_existing_active()
  local query = "SELECT " ..
                self.statements.select.expr ..
                " FROM keyring_meta WHERE state = 'active'"

  return self.connector:query(query)
end


function SKey_Meta:activate(id)
  local txn = [[
    BEGIN;
      UPDATE keyring_meta SET state = 'alive' WHERE id =
        (SELECT id FROM keyring_meta WHERE state = 'active');
      UPDATE keyring_meta SET state = 'active' WHERE id = '%s';
    COMMIT;
  ]]

  return self.connector:query(string.format(txn, id))
end


return SKey_Meta
