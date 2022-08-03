-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"

local uh = require "spec/upgrade_helpers"

describe("database migration", function()
    uh.old_after_up("has created the expected new columns", function()
        assert.table_has_column("targets", "cache_key", "text")
        assert.table_has_column("upstreams", "hash_on_query_arg", "text")
        assert.table_has_column("upstreams", "hash_fallback_query_arg", "text")
        assert.table_has_column("upstreams", "hash_on_uri_capture", "text")
        assert.table_has_column("upstreams", "hash_fallback_uri_capture", "text")
    end)
end)

describe("vault related data migration", function()

    lazy_setup(uh.start_kong)
    lazy_teardown(uh.stop_kong)

    local function assert_no_entities(resource)
      return function()
        local admin_client = uh.admin_client()
        local res = admin_client:get(resource)
        admin_client:close()
        assert.equal(200, res.status)
        local body = res:read_body()
        if body then
          local json = cjson.decode(body)
          assert.equal(0, #json.data)
        end
      end
    end

    uh.setup(assert_no_entities("/vaults-beta"))
    uh.new_after_finish("has no vaults", assert_no_entities("/vaults"))
end)
