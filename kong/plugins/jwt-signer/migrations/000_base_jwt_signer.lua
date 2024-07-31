-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS jwt_signer_jwks (
        id          UUID                      PRIMARY KEY,
        name        TEXT                      NOT NULL      UNIQUE,
        keys        JSONB                     NOT NULL,
        previous    JSONB,
        created_at  TIMESTAMP WITH TIME ZONE,
        updated_at  TIMESTAMP WITH TIME ZONE
      );
    ]],
  },
}
