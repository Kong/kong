-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local SKey_Meta = {}


function SKey_Meta:select_existing_active()
  local query = "SELECT " ..
                self.statements.select.expr ..
                " FROM keyring_meta WHERE state = 'active'"

  return self.connector:query(query, "read")
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
