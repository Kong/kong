-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local jwks = require "kong.openid-connect.jwks"


return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "oic_jwks" (
        "id"    UUID    PRIMARY KEY,
        "jwks"  JSONB
      );
    ]],
    teardown = function(connector)
      local generated_jwks, err = jwks.new({ json = true })
      if not generated_jwks then
        return nil, err
      end

      local insert_query = string.format([[
        INSERT INTO "oic_jwks" ("id", "jwks")
             VALUES ('c3cfba2d-1617-453f-a416-52e6edb5f9a0', '%s')
        ON CONFLICT DO NOTHING;
      ]], generated_jwks)

      local _
      _, err = connector:query(insert_query)
      if err then
        return nil, err
      end

      return true
    end,

  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS oic_jwks (
        id   uuid  PRIMARY KEY,
        jwks text
      );
    ]],
    teardown = function(connector)
      local coordinator = assert(connector:get_stored_connection())
      local generated_jwks, err = jwks.new({ json = true })
      if not generated_jwks then
        return nil, err
      end

      local insert_query = string.format([[
        INSERT INTO oic_jwks (id, jwks)
             VALUES (c3cfba2d-1617-453f-a416-52e6edb5f9a0, '%s') IF NOT EXISTS
      ]], generated_jwks)

      local _
      _, err = coordinator:execute(insert_query)
      if err then
        return nil, err
      end

      return true
    end,
  },
}
