-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local utils = require "pl.utils"
local stringx = require "pl.stringx"
local http = require "resty.http"
local fmt = string.format
local cjson = require "cjson"


local function count_server_blocks(filename)
  local file = assert(utils.readfile(filename))
  local _, count = file:gsub("[%\n%s]+server%s{","")
  return count
end


local function get_listeners(filename)
  local file = assert(utils.readfile(filename))
  local result = {}
  for block in file:gmatch("[%\n%s]+server%s+(%b{})") do
    local server = {}
    local server_name = stringx.strip(block:match("[%\n%s]server_name%s(.-);"))
    result[server_name] = server
    for listen in block:gmatch("[%\n%s]listen%s(.-);") do
      listen = stringx.strip(listen)
      table.insert(server, listen)
      server[listen] = #server
    end
  end
  return result
end


describe("Admin API listeners", function()
  before_each(function()
    helpers.get_db_utils(nil, {
      "routes",
      "services",
    })
  end)

  after_each(function()
    helpers.stop_kong()
  end)

  it("disabled", function()
    assert(helpers.start_kong({
      proxy_listen = "0.0.0.0:9000",
      admin_listen = "off",
      admin_gui_listen = "off",
    }))
    -- XXX EE
    -- extra listeners (portal, etc) can affect this count
    assert.equals(2, count_server_blocks(helpers.test_conf.nginx_kong_conf))
    assert.is_nil(get_listeners(helpers.test_conf.nginx_kong_conf).kong_admin)
  end)

  it("multiple", function()
    assert(helpers.start_kong({
      proxy_listen = "0.0.0.0:9000",
      admin_listen = "127.0.0.1:9001, 127.0.0.1:9002",
      admin_gui_listen = "off",
    }))

    -- XXX EE
    -- extra listeners (portal, etc) can affect this count
    assert.equals(3, count_server_blocks(helpers.test_conf.nginx_kong_conf))
    assert.same({
      ["127.0.0.1:9001"] = 1,
      ["127.0.0.1:9002"] = 2,
      [1] = "127.0.0.1:9001",
      [2] = "127.0.0.1:9002",
    }, get_listeners(helpers.test_conf.nginx_kong_conf).kong_admin)

    for i = 9001, 9002 do
      local client = assert(http.new())
      assert(client:connect("127.0.0.1", i))

      local res = assert(client:request {
        method = "GET",
        path = "/"
      })
      res:read_body()
      client:close()
      assert.equals(200, res.status)
    end
  end)
end)

for _, strategy in helpers.each_strategy() do
  describe("Admin API #" .. strategy .. " - consumers", function ()
    local client, bp, db
    local MAX_ENTITIES = 100

    lazy_setup(function ()
      bp, db = helpers.get_db_utils(strategy, {
        "consumers",
      })

      for i = 1, MAX_ENTITIES do
        local consumer = {
          type = i % 4,
          username = fmt("u-%s", i),
        }
        local _, err, err_t = bp.consumers:insert(consumer)
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

    it("pagination - page_by_type", function ()
      local rows, err = db.consumers:page_by_type(0)
      assert.is_nil(err)
      assert.same(25, #rows)

      rows, err = db.consumers:page_by_type(1)
      assert.is_nil(err)
      assert.same(25, #rows)

      rows, err = db.consumers:page_by_type(2)
      assert.is_nil(err)
      assert.same(25, #rows)

      rows, err = db.consumers:page_by_type(3)
      assert.is_nil(err)
      assert.same(25, #rows)
    end)

    it("pagination - Admin API", function ()
      local res
      res = assert(client:send {
        method = "GET",
        path = "/consumers"
      })
      local body = assert.res_status(200, res)
      local json = cjson.decode(body)
      assert.same(25, #json.data)
      for _, row in ipairs(json.data) do
        assert.same(0, row.type)
      end

      res = assert(client:send {
        method = "GET",
        path = "/consumers?size=5"
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.same(5, #json.data)
      for _, row in ipairs(json.data) do
        assert.same(0, row.type)
      end

      -- `type` is ignored from Admin API
      res = assert(client:send {
        method = "GET",
        path = "/consumers?type=1"
      })
      body = assert.res_status(200, res)
      json = cjson.decode(body)
      assert.same(25, #json.data)
      for _, row in ipairs(json.data) do
        assert.same(0, row.type)
      end
    end)
  end)
end
