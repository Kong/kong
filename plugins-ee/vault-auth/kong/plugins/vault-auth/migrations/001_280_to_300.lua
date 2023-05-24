-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- This should already been handled by core, but just for docs,
-- see: https://github.com/Kong/kong/pull/8871

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "vault_auth_vaults" (
        "id"               UUID                       PRIMARY KEY,
        "created_at"       TIMESTAMP WITH TIME ZONE,
        "updated_at"       TIMESTAMP WITH TIME ZONE,
        "name"             TEXT                       UNIQUE,
        "protocol"         TEXT,
        "host"             TEXT,
        "port"             BIGINT,
        "mount"            TEXT,
        "vault_token"      TEXT
      );
    ]],
  },
}
