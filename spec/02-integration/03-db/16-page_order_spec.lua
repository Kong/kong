-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"

local fmod    = math.fmod

for _, strategy in helpers.each_strategy({"postgres"}) do

describe("kong.db [#" .. strategy .. "]", function()
  local db, bp, _

  local test_entity_count = 10
  -- max UUID starts with "f"
  local service_uuid_min, consumer_uuid_min = "g", "g"
  local service_uuid_max, consumer_uuid_max = "0", "0"

  lazy_setup(function()
    bp, db = helpers.get_db_utils(strategy, {
      "services",
      "consumers"
    })

    for i = 1, test_entity_count do
      local service = {
        host = string.format("example-%02d.com", i),
        name = string.format("service%02d", test_entity_count-i+1),
        tags = { "team_a", "level_"..fmod(i, 5), "service"..i },
        created_at = 1136214245 + i,
      }
      local row, err, err_t = bp.services:insert(service)
      assert.is_nil(err)
      assert.is_nil(err_t)
      if row.id < service_uuid_min then
        service_uuid_min = row.id
      end
      if row.id > service_uuid_max then
        service_uuid_max = row.id
      end

      local consumer = {
        username = "consumer" .. i,
        custom_id = string.format("custom_id%02d", test_entity_count-i+1),
        tags = { "team_a", "level_"..fmod(i, 5), "consumer"..i },
        created_at = 1136214245 + i,
      }
      local row, err, err_t = bp.consumers:insert(consumer)
      assert.is_nil(err)
      assert.is_nil(err_t)
      if row.id < consumer_uuid_min then
        consumer_uuid_min = row.id
      end
      if row.id > consumer_uuid_max then
        consumer_uuid_max = row.id
      end
    end
  end)

  describe("order by", function()
    it("known field only", function()
      local err
      _, err = db.services:page(nil, nil, { sort_by = "wat" })
      assert.same(err, "[postgres] invalid option (sort_by: cannot order by unknown field 'wat')")
      _, err = db.services:page(nil, nil, { sort_by = "name;drop/**/table/**/services;/**/--/**/-" })
      assert.same(err, "[postgres] invalid option (sort_by: cannot order by unknown field 'name;drop/**/table/**/services;/**/--/**/-')")
    end)

    it("any field", function()
      local rows, err
      rows, err = db.services:page(nil, nil, { sort_by = "name" })
      assert.is_nil(err)
      assert.same("service01", rows[1].name)

      rows, err = db.services:page(nil, nil, { sort_by = "host" })
      assert.is_nil(err)
      assert.same("example-01.com", rows[1].host)

      rows, err = db.consumers:page(nil, nil, { sort_by = "custom_id" })
      assert.is_nil(err)
      assert.same("custom_id01", rows[1].custom_id)

      rows, err = db.consumers:page(nil, nil, { sort_by = "username" })
      assert.is_nil(err)
      assert.same("consumer1", rows[1].username)
    end)

    it("KAG-2865 paginate when sort_by on created_at", function()
      local rows, err, offset
      rows, err, _, offset = db.services:page(2, nil, { sort_by = "created_at" })
      assert.is_nil(err)
      assert.same("service10", rows[1].name)

      rows, err = db.services:page(2, offset, { sort_by = "created_at" })
      assert.is_nil(err)
      assert.same("service08", rows[1].name)

      rows, err, _, offset = db.consumers:page(2, nil, { sort_by = "created_at" })
      assert.is_nil(err)
      assert.same("custom_id10", rows[1].custom_id)

      rows, err = db.consumers:page(2, offset, { sort_by = "created_at" })
      assert.is_nil(err)
      assert.same("custom_id08", rows[1].custom_id)
    end)

    it("any field desc", function()
      local rows, err
      rows, err = db.services:page(nil, nil, { sort_by = "name", sort_desc = true })
      assert.is_nil(err)
      assert.same("service" .. test_entity_count, rows[1].name)

      rows, err = db.consumers:page(nil, nil, { sort_by = "custom_id", sort_desc = true })
      assert.is_nil(err)
      assert.same("custom_id" .. test_entity_count, rows[1].custom_id)
    end)

    it("field has non-unique values use pk as secondary order", function()
      local rows, err
      rows, err = db.services:page(nil, nil, { sort_by = "protocol" })
      assert.is_nil(err)
      assert.same(service_uuid_min, rows[1].id)

      local rows, err
      rows, err = db.services:page(nil, nil, { sort_by = "protocol", sort_desc = true })
      assert.is_nil(err)
      assert.same(service_uuid_max, rows[1].id)
    end)

    it("any field with offset", function()
      local rows, err, offset
      for i=1, test_entity_count do
        rows, err, _, offset = db.services:page(1, offset, { sort_by = "name" })
        assert.is_nil(err)
        assert.same(("service%02d"):format(i), rows[1].name)
      end

      offset = nil
      for i=1, test_entity_count do
        rows, err, _, offset = db.consumers:page(1, offset, { sort_by = "custom_id" })
        assert.is_nil(err)
        assert.same(("custom_id%02d"):format(i), rows[1].custom_id)
      end
    end)

    it("any field desc with offset", function()
      local rows, err, offset
      for i=1, test_entity_count do
        rows, err, _, offset = db.services:page(1, offset, { sort_by = "name", sort_desc = true })
        assert.is_nil(err)
        assert.same(("service%02d"):format(test_entity_count-i+1), rows[1].name)
      end

      offset = nil
      for i=1, test_entity_count do
        rows, err, _, offset = db.consumers:page(1, offset, { sort_by = "custom_id", sort_desc = true })
        assert.is_nil(err)
        assert.same(("custom_id%02d"):format(test_entity_count-i+1), rows[1].custom_id)
      end
    end)

    it("any field has non-unique values with offset", function()
      local rows, err, offset
      local collected = {}
      for i=1, test_entity_count do
        rows, err, _, offset = db.services:page(1, offset, { sort_by = "protocol" })
        assert.is_nil(err)
        table.insert(collected, rows[1].id)
      end
      assert.same(service_uuid_min, collected[1])
      assert.same(service_uuid_max, collected[test_entity_count])

      offset = nil
      collected = {}
      for i=1, test_entity_count do
        rows, err, _, offset = db.services:page(1, offset, { sort_by = "protocol", sort_desc = true })
        assert.is_nil(err)
        table.insert(collected, rows[1].id)
      end
      assert.same(service_uuid_max, collected[1])
      assert.same(service_uuid_min, collected[test_entity_count])
    end)

    it("sort_offset is escaped", function()
      local err, offset
      _, err, _, offset = db.services:page(1, nil, { sort_by = "name" })
      assert.is_nil(err)
      local offset_t = cjson.decode(ngx.decode_base64(offset))
      offset_t[#offset_t] = "try; to; break; it"
      offset = ngx.encode_base64(cjson.encode(offset_t))

      _, err, _, _ = db.services:page(1, offset, { sort_by = "name" })
      assert.is_nil(err)
    end)
  end)

end)

end -- for _, strategy in helpers.each_strategy({"postgres"}) do
