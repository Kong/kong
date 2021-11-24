-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

for _, strategy in helpers.each_strategy({"postgres"}) do

local strategy = "postgres"

describe("Admin API - sort_by", function()

  describe("/entities?sort_by= with DB: #" .. strategy, function()
    local client, bp, db

    local test_entity_count = 10

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "consumers",
        "services",
      })

      for i = 1, test_entity_count do
        local consumer = {
          username = string.format("consumer%02d", i),
          custom_id = string.format("custom_id%02d", i),
        }
        local _, err, err_t = bp.consumers:insert(consumer)
        assert.is_nil(err)
        assert.is_nil(err_t)

        local service = {
          name = string.format("service%02d", i),
          url = "http://example.com",
        }
        local _, err, err_t = bp.services:insert(service)
        assert.is_nil(err)
        assert.is_nil(err_t)
      end

      assert(helpers.start_kong {
        database = strategy,
      })
      client = assert(helpers.admin_client(10000))
    end)

    lazy_teardown(function()
      if client then client:close() end
      helpers.stop_kong()
    end)

    it("known field only", function()
      local err, _
      _, err = db.services:page(nil, nil, { sort_by = "wat" })
      assert.same(err, "[postgres] invalid option (sort_by: cannot order by unknown field 'wat')")
      _, err = db.services:page(nil, nil, { sort_by = "name;drop/**/table/**/services;/**/--/**/-" })
      assert.same(err, "[postgres] invalid option (sort_by: cannot order by unknown field 'name;drop/**/table/**/services;/**/--/**/-')")
    end)

    it("any field", function()
      local res
      res = assert(client:send {
        method = "GET",
        path = "/services?sort_by=name"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same('service01', json.data[1].name)

      res = assert(client:send {
        method = "GET",
        path = "/consumers?sort_by=custom_id"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same('custom_id01', json.data[1].custom_id)
    end)

    it("any field desc", function()
      local res
      res = assert(client:send {
        method = "GET",
        path = "/services?sort_by=name&sort_desc=1"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same('service10', json.data[1].name)

      res = assert(client:send {
        method = "GET",
        path = "/consumers?sort_by=custom_id&sort_desc=1"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same('custom_id10', json.data[1].custom_id)
    end)

    it("any field with offset and size", function()
      local res
      local offset
      for i=1, test_entity_count do
        res = assert(client:send {
          method = "GET",
          path = "/services?sort_by=name&size=1" .. (offset and ("&offset=" .. offset) or "")
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(string.format('service%02d', i), json.data[1].name)
        offset = json.offset
      end

      offset = nil
      for i=1, test_entity_count do
        res = assert(client:send {
          method = "GET",
          path = "/consumers?sort_by=custom_id&size=1" .. (offset and ("&offset=" .. offset) or "")
        })
        local body = assert.res_status(200, res)
        local json = cjson.decode(body)
        assert.same(string.format('custom_id%02d', i), json.data[1].custom_id)
        offset = json.offset
      end
    end)
  end)

end)

end -- for _, strategy in helpers.each_strategy({"postgres"}) do
