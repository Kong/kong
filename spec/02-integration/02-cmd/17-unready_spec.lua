local helpers = require "spec.helpers"
local http = require "resty.http"

local dp_status_port = 8100

local function get_status_no_ssl_verify()
  local httpc = http.new()

  local ok, err = httpc:connect({
      scheme = "https",
      host = "127.0.0.1",
      port = dp_status_port,
      ssl_verify = false,
  })
  if not ok then
      return nil, nil, err
  end

  local res, err = httpc:request({
      path = "/status/ready",
      headers = {
          ["Content-Type"] = "application/json",
      }
  })

  if not res then
    return nil, nil, err
  end

  local status = res.status

  local body, err = res:read_body()
  if not body then
    return nil, nil, err
  end

  httpc:set_keepalive()

  return body, status
end

for _, strategy in helpers.each_strategy() do
  describe("kong unready with #" .. strategy .. " backend", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {
      }) -- runs migrations

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        status_listen = "127.0.0.1:8100",
        nginx_main_worker_processes = 8,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("should set Kong to 'unready'", function()
      local client = helpers.http_client("127.0.0.1", dp_status_port, 20000)

      local res = assert(client:send {
        method = "GET",
        path = "/status/ready",
      })

      local status = res and res.status
      client:close()

      assert.equal(200, status)

      local ok, err, msg = helpers.kong_exec("unready", {
        prefix = helpers.test_conf.prefix,
      })
      assert.equal("", err)
      assert.equal("Kong's status successfully changed to 'unready'\n", msg)
      assert.equal(true, ok)

      local client = helpers.http_client("127.0.0.1", dp_status_port, 20000)

      local res = assert(client:send {
        method = "GET",
        path = "/status/ready",
      })

      local status = res and res.status
      client:close()

      assert.equal(503, status)
    end)

  end)

  describe("Kong without a status listener", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {
      }) -- runs migrations

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("should return an error when trying to set 'unready' without a status listener", function()
      local ok, err, msg = helpers.kong_exec("unready", {
        prefix = helpers.test_conf.prefix,
      })
      assert.equal("", err)
      assert.equal("No status listeners found in configuration.\n", msg)
      assert.equal(true, ok)
    end)

  end)

  describe("Kong with SSL-enabled status listener", function()
    lazy_setup(function()
      helpers.get_db_utils(strategy, {
      }) -- runs migrations

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        status_listen = "127.0.0.1:8100 ssl",
        nginx_main_worker_processes = 8,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong()
    end)

    it("should set Kong to 'unready' with SSL-enabled status listener", function()
      local body, status, err = get_status_no_ssl_verify()
      assert.equal(200, status)
      assert.equal('{"message":"ready"}', body)
      assert.is_nil(err)

      local ok, err, msg = helpers.kong_exec("unready", {
        prefix = helpers.test_conf.prefix,
      })
      assert.equal("", err)
      assert.equal("Kong's status successfully changed to 'unready'\n", msg)
      assert.equal(true, ok)

      local body, status, err = get_status_no_ssl_verify()
      assert.equal(503, status)
      assert.equal('{"message":"unready"}', body)
      assert.is_nil(err)
    end)
  end)
end
