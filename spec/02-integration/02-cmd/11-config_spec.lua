local helpers = require "spec.helpers"
local constants = require "kong.constants"
local cjson = require "cjson"


describe("kong config", function()
  local db

  lazy_setup(function()
    local _
    _, db = helpers.get_db_utils(nil, {}) -- runs migrations
  end)
  after_each(function()
    helpers.kill_all()
  end)
  lazy_teardown(function()
    helpers.clean_prefix()
  end)

  it("config help", function()
    local _, stderr = helpers.kong_exec "config --help"
    assert.not_equal("", stderr)
  end)

  it("#db config imports a yaml file", function()
    assert(db.plugins:truncate())
    assert(db.routes:truncate())
    assert(db.services:truncate())

    local dns_hostsfile = assert(os.tmpname())
    local fd = assert(io.open(dns_hostsfile, "w"))
    assert(fd:write("127.0.0.1 " .. constants.REPORTS.ADDRESS))
    assert(fd:close())

    local filename = helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: foo
        host: example.com
        protocol: https
        _comment: my comment
        _ignore:
        - foo: bar
        routes:
          - hosts: ['foo.test']
        plugins:
          - name: key-auth
            _comment: my comment
            _ignore:
            - foo: bar
          - name: http-log
            config:
              http_endpoint: https://example.com
      - name: bar
        host: example.test
        port: 3000
        routes:
          - hosts: ['bar.test']
        plugins:
        - name: basic-auth
        - name: tcp-log
          config:
            port: 10000
            host: 127.0.0.1

    ]])

    finally(function()
      os.remove(filename)
      os.remove(dns_hostsfile)
    end)

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
      dns_hostsfile = dns_hostsfile,
      anonymous_reports = "on",
    }))

    local thread = helpers.udp_server(constants.REPORTS.STATS_PORT)

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))

    local _, res = assert(thread:join())
    assert.matches("signal=config-db-import", res, nil, true)
    assert.matches("decl_fmt_version=1.1", res, nil, true)

    local client = helpers.admin_client()

    local res = client:get("/services/foo")
    assert.res_status(200, res)

    local res = client:get("/services/bar")
    assert.res_status(200, res)

    local res = client:get("/services/foo/plugins")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equals(2, #json.data)

    local res = client:get("/services/bar/plugins")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equals(2, #json.data)

    assert(helpers.stop_kong())
  end)

  it("#db config db_import does not require Kong to be running", function()
    local filename = helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: foo
        host: example.com
        protocol: https
        _comment: my comment
        _ignore:
        - foo: bar
        routes:
          - hosts: ['foo.test']
        plugins:
          - name: key-auth
            _comment: my comment
            _ignore:
            - foo: bar
          - name: http-log
            config:
              http_endpoint: https://example.com
      - name: bar
        host: example.test
        port: 3000
        routes:
          - hosts: ['bar.test']
        plugins:
        - name: basic-auth
        - name: tcp-log
          config:
            port: 10000
            host: 127.0.0.1

    ]])

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))
  end)

  it("#db config db_import is idempotent based on endpoint_key and cache_key", function()
    assert(db.plugins:truncate())
    assert(db.routes:truncate())
    assert(db.services:truncate())

    local filename = helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: foo
        url: http://example.com
        routes:
          - name: r1
            hosts: ['foo.test']
        plugins:
        - name: basic-auth
        - name: tcp-log
          config:
            port: 10000
            host: 127.0.0.1
      - name: bar
        url: https://example.org
        routes:
          - name: r2
            hosts: ['bar.test']
        plugins:
        - name: basic-auth
        - name: tcp-log
          config:
            port: 10000
            host: 127.0.0.1
    ]])

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))

    local client = helpers.admin_client()

    local res = client:get("/routes")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equals(2, #json.data)

    res = client:get("/services/foo")
    assert.res_status(200, res)

    res = client:get("/services/bar")
    assert.res_status(200, res)

    res = client:get("/services/foo/plugins")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(2, #json.data)

    res = client:get("/services/bar/plugins")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(2, #json.data)

    res = client:get("/plugins")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(4, #json.data)

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))

    client = helpers.admin_client()

    res = client:get("/routes")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(2, #json.data)

    res = client:get("/services/foo")
    assert.res_status(200, res)

    res = client:get("/services/bar")
    assert.res_status(200, res)

    res = client:get("/services/foo/plugins")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(2, #json.data)

    res = client:get("/services/bar/plugins")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(2, #json.data)

    res = client:get("/plugins")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(4, #json.data)

    assert(helpers.stop_kong())
  end)

  it("#db config db_import is not idempotent when endpoint_key is not used", function()
    assert(db.plugins:truncate())
    assert(db.routes:truncate())
    assert(db.services:truncate())

    -- note that routes have no name
    local filename = helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: foo
        url: https://example.com
        routes:
          - hosts: ['foo.test']
      - name: bar
        url: https://example.com
        routes:
          - hosts: ['bar.test']
    ]])

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))

    local client = helpers.admin_client()

    local res = client:get("/routes")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equals(2, #json.data)

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))

    client = helpers.admin_client()

    res = client:get("/routes")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(4, #json.data)

    assert(helpers.stop_kong())
  end)
end)
