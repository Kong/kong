-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

require("spec.helpers") -- for kong.log
local declarative = require "kong.db.declarative"
local conf_loader = require "kong.conf_loader"

local to_hex = require("resty.string").to_hex
local resty_sha256 = require "resty.sha256"

local null = ngx.null


local function sha256(s)
  local sha = resty_sha256:new()
  sha:update(s)
  return to_hex(sha:final())
end

describe("declarative", function()
  describe("parse_string", function()
    it("converts lyaml.null to ngx.null", function()
      local dc = declarative.new_config(conf_loader())
      local entities, err = dc:parse_string [[
_format_version: "1.1"
routes:
  - name: null
    paths:
    - /
]]
      assert.equal(nil, err)
      local _, route = next(entities.routes)
      assert.equal(null,   route.name)
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

    assert.is_nil(entities.keyauth_credentials['3f9066ef-b91b-4d1d-a05a-28619401c1ad'].ttl)
  end)

  describe("unique_field_key()", function()
    local unique_field_key = declarative.unique_field_key

    it("utilizes the schema name, workspace id, field name, and checksum of the field value", function()
      local key = unique_field_key("services", "123", "fieldname", "test", false)
      assert.is_string(key)
      assert.equals("services|123|fieldname:" .. sha256("test"), key)
    end)

    it("omits the workspace id when 'unique_across_ws' is 'true'", function()
      local key = unique_field_key("services", "123", "fieldname", "test", true)
      assert.equals("services||fieldname:" .. sha256("test"), key)
    end)
  end)

  it("FTI-4808 - declarative configuration containing consumer groups should work", function ()
    local dc = declarative.new_config(conf_loader())
    local entities, err = dc:parse_string([[
_format_version: "3.0"
_transform: true
consumer_groups:
- id: 8f40dff7-8e08-4aae-9333-d88a3327bd01
  name: gold
  plugins:
  - config:
      limit:
      - 50
      retry_after_jitter_max: 0
      window_size:
      - 60
      window_type: sliding
    id: 2e8c482b-7ec6-449e-9828-9c3848698a7d
    name: rate-limiting-advanced
consumers:
- groups:
  - id: 8f40dff7-8e08-4aae-9333-d88a3327bd01
    name: gold
  id: c6cf3ff6-df61-438d-9cae-66de91d9d8f1
  keyauth_credentials:
  - id: fed23a5f-4974-4bb5-88b5-15de2432313d
    key: gold
  username: gold-user      
]])

    assert.equal(nil, err)

    local consumer_group_consumer_count = 0
    for _, consumer_group_consumer in pairs(entities.consumer_group_consumers) do
      assert.equals(consumer_group_consumer.consumer.id, "c6cf3ff6-df61-438d-9cae-66de91d9d8f1")
      assert.equals(consumer_group_consumer.consumer_group.id, "8f40dff7-8e08-4aae-9333-d88a3327bd01")
      consumer_group_consumer_count = consumer_group_consumer_count + 1
    end
    assert.equal(1, consumer_group_consumer_count)
  end)

end)
