-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

require("spec.helpers") -- for kong.log
local declarative = require("kong.db.declarative")
local conf_loader = require("kong.conf_loader")


local null = ngx.null


describe("declarative", function()
  describe("parse_string", function()
    it("converts lyaml.null to ngx.null", function()
      local dc = declarative.new_config(conf_loader())
      local entities, err = dc:parse_string([[
_format_version: "1.1"
routes:
  - name: null
    paths:
    - /
]])
      assert.equal(nil, err)
      local _, route = next(entities.routes)
      assert.equal(null, route.name)
      assert.same({ "/" }, route.paths)
    end)
  end)

  it("ttl fields are accepted in DB-less schema validation", function()
    local dc = declarative.new_config(conf_loader())
    local entities, err = dc:parse_string([[
_format_version: '2.1'
consumers:
- custom_id: ~
  id: e150d090-4d53-4e55-bff8-efaaccd34ec4
  tags: ~
  username: bar@example.com
services:
keyauth_credentials:
- created_at: 1593624542
  id: 3f9066ef-b91b-4d1d-a05a-28619401c1ad
  tags: ~
  ttl: ~
  key: test
  consumer: e150d090-4d53-4e55-bff8-efaaccd34ec4
]])
    assert.equal(nil, err)

    assert.is_nil(entities.keyauth_credentials["3f9066ef-b91b-4d1d-a05a-28619401c1ad"].ttl)
  end)

  it("accepts consumer groups", function()
    local dc = assert(declarative.new_config(conf_loader()))
    local entities, err = dc:parse_string([[
_format_version: "1.1"
consumer_groups:
  - name: test-group
]])
    assert.equal(nil, err)
    local _, cg = next(entities.consumer_groups)
    assert.equal("test-group", cg.name)
  end)

  describe("unique_field_key()", function()
    local unique_field_key = declarative.unique_field_key

    it("utilizes the schema name, workspace id, field name, and checksum of the field value", function()
      local key = unique_field_key("services", "123", "fieldname", "test", false)
      assert.is_string(key)
      assert.equals("services|123|fieldname:test", key)
    end)

    it("omits the workspace id when 'unique_across_ws' is 'true'", function()
      local key = unique_field_key("services", "123", "fieldname", "test", true)
      assert.equals("services||fieldname:test", key)
    end)
  end)
end)
