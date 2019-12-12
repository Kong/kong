local helpers = require "spec.helpers"
local constants = require "kong.constants"
local cjson = require "cjson"
local lyaml = require "lyaml"
local lfs = require "lfs"


local function trim(s)
  return s:gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
end


local function sort_by_name(a, b)
  return a.name < b.name
end

describe("kong config", function()
  local bp, db

  lazy_setup(function()
    bp, db = helpers.get_db_utils(nil, {}) -- runs migrations
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

    local thread = helpers.tcp_server(constants.REPORTS.STATS_PORT)

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
      - name: foobar
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

  it("#db config db_import catches errors in input", function()
    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    finally(function()
      helpers.stop_kong()
    end)

    local filename = helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: foobar
        host: []
        port: -23
        protocol: https
        _comment: my comment
        _ignore:
        - foo: bar
        routes: 123
    ]])

    local ok, err = helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
    })
    assert.falsy(ok)

    assert.same(trim([[
      Error: Failed parsing:
      in 'services':
      - in entry 1 of 'services':
        in 'host': expected a string
        in 'port': value should be between 0 and 65535
        in 'routes': expected an array
      Run with --v (verbose) or --vv (debug) for more details
    ]]), trim(err))
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

  it("#db config db_export exports a yaml file", function()
    assert(db.plugins:truncate())
    assert(db.routes:truncate())
    assert(db.services:truncate())
    assert(db.consumers:truncate())
    assert(db.acls:truncate())

    local filename = os.tmpname()
    os.remove(filename)
    filename = filename .. ".yml"

    -- starting kong just so the prefix is properly initialized
    assert(helpers.start_kong())

    local service1 = bp.services:insert({ name = "service1" })
    local route1 = bp.routes:insert({ service = service1, methods = { "POST" }, name = "a" })
    local plugin1 = bp.hmac_auth_plugins:insert({
      service = service1,
    })
    local plugin2 = bp.key_auth_plugins:insert({
      service = service1,
    })

    local service2 = bp.services:insert({ name = "service2" })
    local route2 = bp.routes:insert({ service = service2, methods = { "GET" }, name = "b" })
    local plugin3 = bp.tcp_log_plugins:insert({
      service = service2,
    })
    local consumer = bp.consumers:insert()
    local acls = bp.acls:insert({ consumer = consumer })

    local keyauth = bp.keyauth_credentials:insert({ consumer = consumer, key = "hello" })

    assert(helpers.kong_exec("config db_export " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))

    finally(function()
      os.remove(filename)
    end)

    local f = assert(io.open(filename, "rb"))
    local content = f:read("*all")
    f:close()
    local yaml = assert(lyaml.load(content))

    local toplevel_keys = {}
    for k in pairs(yaml) do
      toplevel_keys[#toplevel_keys + 1] = k
    end
    table.sort(toplevel_keys)
    assert.same({
      "_format_version",
      "acls",
      "consumers",
      "keyauth_credentials",
      "plugins",
      "routes",
      "services",
    }, toplevel_keys)

    assert.equals("1.1", yaml._format_version)

    assert.equals(2, #yaml.services)
    table.sort(yaml.services, sort_by_name)
    assert.same(service1, yaml.services[1])
    assert.same(service2, yaml.services[2])

    assert.equals(2, #yaml.routes)
    table.sort(yaml.routes, sort_by_name)
    assert.equals(route1.id, yaml.routes[1].id)
    assert.equals(route1.name, yaml.routes[1].name)
    assert.equals(service1.id, yaml.routes[1].service)
    assert.equals(route2.id, yaml.routes[2].id)
    assert.equals(route2.name, yaml.routes[2].name)
    assert.equals(service2.id, yaml.routes[2].service)

    assert.equals(3, #yaml.plugins)
    table.sort(yaml.plugins, sort_by_name)
    assert.equals(plugin1.id, yaml.plugins[1].id)
    assert.equals(plugin1.name, yaml.plugins[1].name)
    assert.equals(service1.id, yaml.plugins[1].service)

    assert.equals(plugin2.id, yaml.plugins[2].id)
    assert.equals(plugin2.name, yaml.plugins[2].name)
    assert.equals(service1.id, yaml.plugins[2].service)

    assert.equals(plugin3.id, yaml.plugins[3].id)
    assert.equals(plugin3.name, yaml.plugins[3].name)
    assert.equals(service2.id, yaml.plugins[3].service)

    assert.equals(1, #yaml.consumers)
    assert.same(consumer, yaml.consumers[1])

    assert.equals(1, #yaml.acls)
    assert.equals(acls.group, yaml.acls[1].group)
    assert.equals(consumer.id, yaml.acls[1].consumer)

    assert.equals(1, #yaml.keyauth_credentials)
    assert.equals(keyauth.key, yaml.keyauth_credentials[1].key)
    assert.equals(consumer.id, yaml.keyauth_credentials[1].consumer)
  end)

  it("#db config db_import works when foreign keys need to be resolved", function()
    assert(db.consumers:truncate())
    assert(db.basicauth_credentials:truncate())

    -- note that routes have no name
    local filename = helpers.make_yaml_file([[
      _format_version: "1.1"
      consumers:
      - username: consumer
        basicauth_credentials:
        - username: username
          password: password
    ]])

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))

    local client = helpers.admin_client()

    local res = client:get("/consumers")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equals(1, #json.data)

    local res = client:get("/basic-auths")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equals(1, #json.data)

    assert(helpers.stop_kong())

    assert(db.consumers:truncate())
    assert(db.basicauth_credentials:truncate())
  end)

  it("#db config parse works when foreign keys need to be resolved", function()
    -- note that routes have no name
    local filename = helpers.make_yaml_file([[
      _format_version: "1.1"
      consumers:
      - username: consumer
        basicauth_credentials:
        - username: username
          password: password
    ]])

    assert(helpers.kong_exec("config parse " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))
  end)

  it("config init creates kong.yml by default", function()
    local kong_yml_exists = false
    if lfs.attributes("kong.yml") then
      kong_yml_exists = true
      os.execute("mv kong.yml kong.yml~")
    end
    finally(function()
      if kong_yml_exists then
        os.execute("mv kong.yml~ kong.yml")
      else
        os.remove("kong.yml")
      end
    end)

    os.remove("kong.yml")
    assert.is_nil(lfs.attributes("kong.yml"))
    assert(helpers.kong_exec("config init"))
    assert.not_nil(lfs.attributes("kong.yml"))
    assert(helpers.kong_exec("config parse kong.yml"))
  end)

  it("config init can take an argument", function()
    local tmpname = os.tmpname() .. ".yml"
    finally(function()
      os.remove(tmpname)
    end)

    os.remove(tmpname)
    assert.is_nil(lfs.attributes(tmpname))
    assert(helpers.kong_exec("config init " .. tmpname))
    assert.not_nil(lfs.attributes(tmpname))
    assert(helpers.kong_exec("config parse " .. tmpname))
  end)
end)
