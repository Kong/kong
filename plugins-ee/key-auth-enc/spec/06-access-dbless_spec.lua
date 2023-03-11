-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson = require "cjson"
local pl_path = require "pl.path"

local fixture_path
do
  -- this code will get debug info and from that determine the file
  -- location, so fixtures can be found based of this path
  local info = debug.getinfo(function()
  end)
  fixture_path = info.source
  if fixture_path:sub(1, 1) == "@" then
    fixture_path = fixture_path:sub(2, -1)
  end
  fixture_path = pl_path.splitpath(fixture_path) .. "/fixtures/"
end

-- https://konghq.atlassian.net/browse/FTI-4592
describe("Plugin: key-auth-enc (access) [#off]", function()
  local proxy_client

  lazy_setup(function()
    assert(helpers.start_kong({
      database = "off",
      declarative_config = fixture_path .. "FTI-4592.yaml",
      plugins = "key-auth-enc",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    proxy_client = helpers.proxy_client()
  end)

  lazy_teardown(function()
    if proxy_client then
      proxy_client:close()
    end

    helpers.stop_kong()
  end)

  it("should successful while using the same key across multiple workspaces in dbless mode", function()
    local apikey = "wcKDwkL3I5nOCDVd8qlMhWKSV69NE7uf"
    local consumer_1_id = "1bd69f90-741c-4e75-834e-94155d6e3f5d"
    local consumer_2_id = "8df2d29b-fb8f-45b2-b90d-4b7fdbaa92e7"

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/test1/request",
      headers = {
        ["apikey"] = apikey,
      }
    })
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equal(consumer_1_id, json.headers["x-consumer-id"])
    assert.equal("bob", json.headers["x-consumer-username"])
    assert.equal(apikey, json.headers["apikey"])

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/test2/request",
      headers = {
        ["apikey"] = apikey,
      }
    })
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equal(consumer_2_id, json.headers["x-consumer-id"])
    assert.equal("bob", json.headers["x-consumer-username"])
    assert.equal(apikey, json.headers["apikey"])

  end)
end)
