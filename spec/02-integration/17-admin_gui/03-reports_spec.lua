local cjson = require "cjson"
local lfs = require "lfs"
local pl_path = require "pl.path"
local shell = require "resty.shell"

local helpers = require "spec.helpers"
local constants = require "kong.constants"

describe("anonymous reports for kong manager", function ()
  local reports_send_ping = function()
    ngx.sleep(0.2) -- hand over the CPU so other threads can do work (processing the sent data)
    local admin_client = helpers.admin_client()
    local res = admin_client:post("/reports/send-ping?port=" .. constants.REPORTS.STATS_TLS_PORT)
    assert.response(res).has_status(200)
    admin_client:close()
  end

  local assert_report = function (value)
    local reports_server = helpers.tcp_server(constants.REPORTS.STATS_TLS_PORT, {tls=true})
    reports_send_ping()
    local _, reports_data = assert(reports_server:join())
    reports_data = cjson.encode(reports_data)

    assert.match(value, reports_data)
  end

  local prepare_gui_dir = function ()
    local err, gui_dir_path
    gui_dir_path = pl_path.join(helpers.test_conf.prefix, "gui")
    shell.run("rm -rf " .. gui_dir_path, nil, 0)
    err = select(2, lfs.mkdir(gui_dir_path))
    assert.is_nil(err)
    return gui_dir_path
  end

  local create_gui_file = function (path)
    local fd = assert(io.open(path, "w"))
    assert.is_not_nil(fd)
    assert(fd:write("TEST"))
    assert(fd:close())
  end

  local dns_hostsfile
  local bp, db

  lazy_setup(function ()
    dns_hostsfile = assert(os.tmpname() .. ".hosts")
    local fd = assert(io.open(dns_hostsfile, "w"))
    assert(fd:write("127.0.0.1 " .. constants.REPORTS.ADDRESS))
    assert(fd:close())

    bp, db = assert(helpers.get_db_utils(nil, {}, { "reports-api" }))

    bp.plugins:insert({
      name = "reports-api",
      config = {}
    })
  end)

  lazy_teardown(function ()
    os.remove(dns_hostsfile)
    db:truncate("plugins")
  end)

  describe("availability status", function ()
    it("should be correct when admin_gui_listen is set", function ()
      assert(helpers.start_kong({
        admin_gui_listen = "127.0.0.1:9012",
        anonymous_reports = true,
        plugins = "bundled,reports-api",
        dns_hostsfile = dns_hostsfile,
      }))

      finally(function()
        helpers.stop_kong()
      end)

      assert_report("_admin_gui=1")
    end)

    it("should be correct when admin_gui_listen is off", function ()
      assert(helpers.start_kong({
        admin_gui_listen = "off",
        anonymous_reports = true,
        plugins = "bundled,reports-api",
        dns_hostsfile = dns_hostsfile,
      }))

      finally(function()
        helpers.stop_kong()
      end)

      assert_report("_admin_gui=0")
    end)
  end)

  describe("visit", function()
    lazy_setup(function()
      assert(helpers.start_kong({
        admin_gui_listen = "127.0.0.1:9012",
        anonymous_reports = true,
        plugins = "bundled,reports-api",
        dns_hostsfile = dns_hostsfile,
      }))

      local gui_dir_path = prepare_gui_dir()
      create_gui_file(pl_path.join(gui_dir_path, "index.html"))
      create_gui_file(pl_path.join(gui_dir_path, "robots.txt"))
      create_gui_file(pl_path.join(gui_dir_path, "favicon.ico"))
      create_gui_file(pl_path.join(gui_dir_path, "test.js"))
      create_gui_file(pl_path.join(gui_dir_path, "test.css"))
      create_gui_file(pl_path.join(gui_dir_path, "test.png"))
    end)

    lazy_teardown(function()
      os.remove(dns_hostsfile)

      helpers.stop_kong()
    end)

    it("should have value 0 when no kong mananger visit occurs", function ()
      assert_report("km_visits=0")
    end)

    it("should increase counter by 1 for each kong mananger visit", function ()
      local admin_gui_client = helpers.admin_gui_client(nil, 9012)
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/" }))
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/services" }))
      admin_gui_client:close()
      assert_report("km_visits=2")
    end)

    it("should reset the counter after report", function ()
      local admin_gui_client = helpers.admin_gui_client(nil, 9012)
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/" }))
      admin_gui_client:close()
      assert_report("km_visits=1")

      admin_gui_client = helpers.admin_gui_client(nil, 9012)
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/" }))
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/" }))
      assert_report("km_visits=2")
      admin_gui_client:close()
    end)

    it("should not increase the counter for GUI assets", function ()
      local admin_gui_client = helpers.admin_gui_client(nil, 9012)
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/kconfig.js" }))
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/robots.txt" }))
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/favicon.ico" }))
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/test.js" }))
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/test.css" }))
      assert.res_status(200, admin_gui_client:send({ method = "GET", path = "/test.png" }))
      assert.res_status(404, admin_gui_client:send({ method = "GET", path = "/not-exist.png" }))
      admin_gui_client:close()

      assert_report("km_visits=0")
    end)
  end)
end)
