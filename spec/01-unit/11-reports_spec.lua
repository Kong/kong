local meta = require "kong.meta"
local helpers = require "spec.helpers"
local cjson = require "cjson"

describe("reports", function()
  local reports, bytes, err
  local expected_data = "version"
  local port = 8189

  lazy_setup(function()
    -- start the echo server
    assert(helpers.start_kong({
               nginx_conf = "spec/fixtures/custom_nginx.template",
               -- we don't actually use any stream proxy features in tcp_server,
               -- but this is needed in order to load the echo server defined at
               -- nginx_kong_test_tcp_echo_server_custom_inject_stream.lua
               stream_listen = helpers.get_proxy_ip(false) .. ":19000",
               -- to fix "Database needs bootstrapping or is older than Kong 1.0" in CI.
               database = "off",
               log_level = "info",
                      }))

    assert(helpers.is_echo_server_ready())
  end)

  lazy_teardown(function()
    helpers.stop_kong()
    helpers.echo_server_reset()
  end)

  before_each(function()
    package.loaded["kong.reports"] = nil
    reports = require "kong.reports"
  end)

  it("don't send report when anonymous_reports = false", function ()
    bytes, err = reports.send()
    assert.is_nil(bytes)
    assert.equal(err, "disabled")
  end)

  describe("when anonymous_reports = true, ", function ()
    lazy_setup(function()
      _G.kong = _G.kong or {}
      _G.kong.configuration = _G.kong.configuration or {}
      if not _G.kong.configuration.anonymous_reports then
        _G.kong.configuration = { anonymous_reports = true }
      end
    end)

    lazy_teardown(function()
      _G.kong.configuration.anonymous_reports = nil
    end)

    it("send reports", function()
      bytes, err = reports.send()
      assert.is_nil(bytes)
      assert.equal(err, "disabled")
    end)
  end)

  describe("toggle", function()
    before_each(function()
      reports.toggle(true)
    end)

    it("sends report over TCP[TLS]", function()
      bytes, err = reports.send("stub", {
        hello = "world",
        foo = "bar",
        baz = function() return "bat" end,
        foobar = function() return { foo = "bar" } end,
        bazbat = { baz = "bat" },
        nilval = function() return nil end,
      }, "127.0.0.1", port)

      assert.truthy(bytes>0)
      assert.is_nil(err)

      local res = helpers.get_echo_server_received_data(expected_data)

      assert.matches("^<14>", res)
      res = res:sub(5)
      assert.matches("cores=%d+", res)
      assert.matches("uname=[%w]+", res)
      assert.matches("version=" .. meta._VERSION, res, nil, true)
      assert.matches("hostname=[%w]+", res)
      assert.matches("foo=bar", res, nil, true)
      assert.matches("hello=world", res, nil, true)
      assert.matches("signal=stub", res, nil, true)
      assert.matches("baz=bat", res, nil, true)
      assert.not_matches("nilval", res, nil, true)
      assert.matches("foobar=" .. cjson.encode({ foo = "bar" }), res, nil, true)
      assert.matches("bazbat=" .. cjson.encode({ baz = "bat" }), res, nil, true)
    end)

    it("doesn't send if not enabled", function()
      reports.toggle(false)

      bytes, err = reports.send({
        foo = "bar"
      }, "127.0.0.1", port)
      assert.is_nil(bytes)
      assert.equal(err, "disabled")

      local res = helpers.get_echo_server_received_data(expected_data, 0.1)
      assert.equal("timeout", res)
    end)

    it("accepts custom immutable items", function()
      reports.toggle(true)

      reports.add_immutable_value("imm1", "fooval")
      reports.add_immutable_value("imm2", "barval")

      bytes, err = reports.send("stub", {k1 = "bazval"}, "127.0.0.1", port)
      assert.truthy(bytes > 0)
      assert.is_nil(err)

      local res = helpers.get_echo_server_received_data(expected_data)

      assert.matches("imm1=fooval", res)
      assert.matches("imm2=barval", res)
      assert.matches("k1=bazval", res)
    end)
  end)

  describe("configure_ping()", function()
    local conf_loader = require "kong.conf_loader"
    local function send_reports_and_check_result(reports, conf, port, matches)
      reports.configure_ping(conf)
      reports.send_ping("127.0.0.1", port)
      local res = helpers.get_echo_server_received_data(expected_data)

      for _,m in ipairs(matches) do
        assert.matches(m, res, nil, true)
      end
    end

    before_each(function()
      reports.toggle(true)
      reports._create_counter()
    end)

    describe("sends 'cluster_id'", function()
      it("uses mock value 123e4567-e89b-12d3-a456-426655440000", function()
        local conf = assert(conf_loader(nil, {
          database = "postgres",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"cluster_id=123e4567-e89b-12d3-a456-426655440000"})
      end)
    end)

    describe("sends 'database'", function()
      it("postgres", function()
        local conf = assert(conf_loader(nil, {
          database = "postgres",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"database=postgres"})
      end)

      it("off", function()
        local conf = assert(conf_loader(nil, {
          database = "off",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"database=off"})
      end)
    end)

    describe("sends 'role'", function()
               it("traditional", function()
        local conf = assert(conf_loader(nil))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"cluster_id=123e4567-e89b-12d3-a456-426655440000"})
      end)

      it("control_plane", function()
        local conf = assert(conf_loader(nil, {
          role = "control_plane",
          cluster_cert = "spec/fixtures/kong_spec.crt",
          cluster_cert_key = "spec/fixtures/kong_spec.key",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"role=control_plane"})
      end)

      it("data_plane", function()
        local conf = assert(conf_loader(nil, {
          role = "data_plane",
          database = "off",
          cluster_cert = "spec/fixtures/kong_spec.crt",
          cluster_cert_key = "spec/fixtures/kong_spec.key",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"role=data_plane"})
      end)
    end)

    describe("sends 'kic'", function()
      it("default (off)", function()
        local conf = assert(conf_loader(nil))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"kic=false"})
      end)

      it("enabled", function()
        local conf = assert(conf_loader(nil, {
          kic = "on",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"kic=true"})
      end)
    end)

    describe("sends '_admin' for 'admin_listen'", function()
      it("off", function()
        local conf = assert(conf_loader(nil, {
          admin_listen = "off",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"_admin=0"})
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          admin_listen = "127.0.0.1:8001",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"_admin=1"})
      end)
    end)

    describe("sends '_admin_gui' for 'admin_gui_listen'", function()
      it("off", function()
        local conf = assert(conf_loader(nil, {
          admin_gui_listen = "off",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"_admin_gui=0"})
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          admin_gui_listen = "127.0.0.1:8001",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"_admin_gui=1"})
      end)
    end)

    describe("sends '_proxy' for 'proxy_listen'", function()
      it("off", function()
        local conf = assert(conf_loader(nil, {
          proxy_listen = "off",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"_proxy=0"})
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          proxy_listen = "127.0.0.1:8000",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"_proxy=1"})
      end)
    end)

    describe("sends '_stream' for 'stream_listen'", function()
      it("off", function()
        local conf = assert(conf_loader(nil, {
          stream_listen = "off",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"_stream=0"})
      end)

      it("on", function()
        local conf = assert(conf_loader(nil, {
          stream_listen = "127.0.0.1:8000",
        }))
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"_stream=1"})
      end)
    end)

    it("default configuration ping contents", function()
        local conf = assert(conf_loader())
        send_reports_and_check_result(
          reports,
          conf,
          port,
          {"database=" .. helpers.test_conf.database,
           "_admin=1",
           "_proxy=1",
           "_stream=0"
        })
    end)
  end)

  describe("retrieve_redis_version()", function()
    lazy_setup(function()
      stub(ngx, "log")
    end)

    lazy_teardown(function()
      ngx.log:revert() -- luacheck: ignore
    end)

    before_each(function()
      reports.toggle(true)
      reports._create_counter()
    end)

    it("does not query Redis if not enabled", function()
      reports.toggle(false)

      local red_mock = {
        info = function() end,
      }

      local s = spy.on(red_mock, "info")

      reports.retrieve_redis_version(red_mock)
      assert.spy(s).was_not_called()
    end)

    it("queries Redis if enabled", function()
      local red_mock = {
        info = function()
          return "redis_version:2.4.5\r\nredis_git_sha1:e09e31b1"
        end,
      }

      local s = spy.on(red_mock, "info")

      reports.retrieve_redis_version(red_mock)
      assert.spy(s).was_called_with(red_mock, "server")
    end)

    it("queries Redis only once", function()
      local red_mock = {
        info = function()
          return "redis_version:2.4.5\r\nredis_git_sha1:e09e31b1"
        end,
      }

      local s = spy.on(red_mock, "info")

      reports.retrieve_redis_version(red_mock)
      reports.retrieve_redis_version(red_mock)
      reports.retrieve_redis_version(red_mock)
      assert.spy(s).was_called(1)
    end)

    it("retrieves major.minor version", function()
      local red_mock = {
        info = function()
          return "redis_version:2.4.5\r\nredis_git_sha1:e09e31b1"
        end,
      }

      reports.retrieve_redis_version(red_mock)
      assert.equal("2.4", reports.get_ping_value("redis_version"))
    end)

    it("retrieves 'unknown' when the version could not be retrieved (1/3)", function()
      local red_mock = {
        info = function()
          return nil
        end,
      }

      reports.retrieve_redis_version(red_mock)
      assert.equal("unknown", reports.get_ping_value("redis_version"))
    end)

    it("retrieves 'unknown' when the version could not be retrieved (2/3)", function()
      local red_mock = {
        info = function()
          return ngx.null
        end,
      }

      reports.retrieve_redis_version(red_mock)
      assert.equal("unknown", reports.get_ping_value("redis_version"))
    end)

    it("retrieves 'unknown' when the version could not be retrieved (3/3)", function()
      local red_mock = {
        info = function()
          return "hello world"
        end,
      }

      reports.retrieve_redis_version(red_mock)
      assert.equal("unknown", reports.get_ping_value("redis_version"))
    end)
  end)
end)
