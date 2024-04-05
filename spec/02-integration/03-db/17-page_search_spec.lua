-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local fmt     = string.format

for _, strategy in helpers.each_strategy({"postgres"}) do

describe("kong.db [#" .. strategy .. "]", function()
  local db, bp, _

  local test_entity_count = 100

  lazy_setup(function()
    bp, db = helpers.get_db_utils(strategy, {
      "services",
      "routes",
    })

    for i = 1, test_entity_count do
      local service = {
        name = fmt("service%s", i),
        enabled = true,
        protocol = "http",
        host = fmt("example-%s.com", i),
        path = fmt("/%s", i),
      }
      local _, err, err_t = bp.services:insert(service)
      assert.is_nil(err)
      assert.is_nil(err_t)

      local route = {
        name = fmt("route%s", i),
        hosts = { fmt("example-%s.com", i) },
        paths = { fmt("/%s", i) },
      }
      local _, err, err_t = bp.routes:insert(route)
      assert.is_nil(err)
      assert.is_nil(err_t)
    end
  end)

  describe("search fields", function()
    it("known field only", function()
      local err
      _, err = db.services:page(nil, nil, { search_fields = { wat = { eq = "wat" } } })
      assert.same(err, "[postgres] invalid option (search_fields: cannot search on unindexed field 'wat')")
      _, err = db.services:page(nil, nil, { search_fields = { ["name;drop/**/table/**/services;/**/--/**/-"] = { eq = "1" } } })
      assert.same(err, "[postgres] invalid option (search_fields: cannot search on unindexed field 'name;drop/**/table/**/services;/**/--/**/-')")
    end)

    it("common field", function()
      local rows, err
      rows, err = db.services:page(nil, nil, { search_fields = { name = { eq = "99" } } })
      assert.is_nil(err)
      assert.same("service99", rows[1].name)

      rows, err = db.services:page(nil, nil, { search_fields = { host = { eq = "99" } } })
      assert.is_nil(err)
      assert.same("example-99.com", rows[1].host)

      rows, err = db.services:page(nil, nil, { search_fields = { enabled = { eq = "false" } } })
      assert.is_nil(err)
      assert.same(0, #rows)

      rows, err = db.services:page(nil, nil, { search_fields = { path = { eq = "88" } } })
      assert.is_nil(err)
      assert.same("example-88.com", rows[1].host)

      rows, err = db.services:page(nil, nil, { search_fields = { protocol = { eq = "https" } } })
      assert.is_nil(err)
      assert.same(0, #rows)

      rows, err = db.services:page(nil, nil, { search_fields = { enabled = { eq = "false" } } })
      assert.is_nil(err)
      assert.same(0, #rows)
    end)

    it("array field", function()
      local rows, err
      rows, err = db.routes:page(nil, nil, { search_fields = { protocols = { eq = { "http" } } } })
      assert.is_nil(err)
      assert.same(100, #rows)

      rows, err = db.routes:page(nil, nil, { search_fields = { protocols = { eq = { "https" } } } })
      assert.is_nil(err)
      assert.same(100, #rows)

      rows, err = db.routes:page(nil, nil, { search_fields = { protocols = { eq = { "http", "https" } } } })
      assert.is_nil(err)
      assert.same(100, #rows)

      rows, err = db.routes:page(nil, nil, { search_fields = { protocols = { eq = { "http", "https", "grpc" } } } })
      assert.is_nil(err)
      assert.same(0, #rows)

      rows, err = db.routes:page(nil, nil, { search_fields = { protocols = { eq = { "grpc" } } } })
      assert.is_nil(err)
      assert.same(0, #rows)

      rows, err = db.routes:page(nil, nil, { search_fields = { protocols = { eq = "http" } } })
      assert.is_nil(err)
      assert.same(100, #rows)

      rows, err = db.routes:page(nil, nil, { search_fields = { protocols = { eq = "T!@$*)%!@#" } } })
      assert.is_nil(err)
      assert.same(0, #rows)
    end)

    it("array fuzzy field", function()
      local rows, err
      rows, err = db.routes:page(nil, nil, { search_fields = { paths = { eq = "100" } } })
      assert.is_nil(err)
      assert.same("route100", rows[1].name)

      local rows, err
      rows, err = db.routes:page(nil, nil, { search_fields = { paths = { eq = "/100" } } })
      assert.is_nil(err)
      assert.same("route100", rows[1].name)

      local rows, err
      rows, err = db.routes:page(nil, nil, { search_fields = { paths = { eq = "/1" } } })
      assert.is_nil(err)
      assert.same(12, #rows)

      local rows, err
      rows, err = db.routes:page(nil, nil, { search_fields = { hosts = { eq = "100" } } })
      assert.is_nil(err)
      assert.same("route100", rows[1].name)
    end)

  end)

end)

end -- for _, strategy in helpers.each_strategy({"postgres"}) do
