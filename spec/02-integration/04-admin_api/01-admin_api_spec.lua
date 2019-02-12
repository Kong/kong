local helpers = require "spec.helpers"
local utils = require "pl.utils"
local stringx = require "pl.stringx"
local http = require "resty.http"


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
    }))
    assert.equals(1, count_server_blocks(helpers.test_conf.nginx_kong_conf))
    assert.is_nil(get_listeners(helpers.test_conf.nginx_kong_conf).kong_admin)
  end)

  it("multiple", function()
    assert(helpers.start_kong({
      proxy_listen = "0.0.0.0:9000",
      admin_listen = "127.0.0.1:9001, 127.0.0.1:9002",
    }))

    assert.equals(2, count_server_blocks(helpers.test_conf.nginx_kong_conf))
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
