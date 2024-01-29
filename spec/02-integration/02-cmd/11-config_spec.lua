local helpers = require "spec.helpers"
local constants = require "kong.constants"
local cjson = require "cjson"
local lyaml = require "lyaml"
local lfs = require "lfs"
local shell = require "resty.shell"


local function sort_by_name(a, b)
  return a.name < b.name
end


local function convert_yaml_nulls(tbl)
  for k,v in pairs(tbl) do
    if v == lyaml.null then
      tbl[k] = ngx.null
    elseif type(v) == "table" then
      convert_yaml_nulls(v)
    end
  end
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

    local dns_hostsfile = assert(os.tmpname() .. ".hosts")
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
        - name: rate-limiting
          config:
            minute: 200
            policy: redis
            redis:
              host: 127.0.0.1
      plugins:
      - name: correlation-id
        id: 467f719f-a544-4a8f-bc4b-7cd12913a9d4
        config:
          header_name: null
          generator: "uuid"
          echo_downstream: false
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

    local thread = helpers.tcp_server(constants.REPORTS.STATS_TLS_PORT, {tls=true})

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
      anonymous_reports = "on",
    }))

    local _, res = assert(thread:join())
    assert.matches("signal=config-db-import", res, nil, true)
    -- it will be updated on-the-fly
    assert.matches("decl_fmt_version=3.0", res, nil, true)
    assert.matches("file_ext=.yml", res, nil, true)

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
    assert.equals(3, #json.data)

    local res = client:get("/plugins/467f719f-a544-4a8f-bc4b-7cd12913a9d4")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    json.created_at = nil
    json.updated_at = nil
    json.protocols = nil
    assert.same({
      name = "correlation-id",
      instance_name = ngx.null,
      id = "467f719f-a544-4a8f-bc4b-7cd12913a9d4",
      route = ngx.null,
      service = ngx.null,
      consumer = ngx.null,
      enabled = true,
      config = {
        header_name = ngx.null,
        generator = "uuid",
        echo_downstream = false,
      },
      tags = ngx.null,
    }, json)

    assert(helpers.stop_kong())
  end)

  pending("#db config db_import does not require Kong to be running", function()
  -- this actually sends data to the telemetry endpoint. TODO: how to avoid that?
  -- in this case we do not change the DNS hostsfile..
  -- NetidState Recv-Q Send-Q  Local Address:Port   Peer Address:Port
  -- tcp  ESTAB 0      216        172.23.0.4:35578 35.169.37.138:61830
  --                                                this is the amazon splunk ip
  -- tcp  ESTAB 0      0          172.23.0.4:40746    172.23.0.3:5432
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

  -- same as with "config db_import does not require Kong to be running"
  -- when no kong is present, we can't mock a response
  pending("#db config db_import deals with repeated targets", function()
    -- Since Kong 2.2.0 there's no more target history, but we must make sure
    -- that old configs still can be imported.
    local filename = helpers.make_yaml_file([[
      _format_version: "1.1"
      _transform: false
      _format_version: '2.1'
      parameters:
      - created_at: ~
        key: cluster_id
        value: 36ad7d46-b95c-44f6-a79e-edb1f33baaf7
      upstreams:
      - hash_on_header: ~
        algorithm: round-robin
        host_header: ~
        hash_on_cookie: ~
        created_at: 1618602527
        hash_on_cookie_path: /
        hash_fallback: none
        hash_fallback_header: ~
        healthchecks:
          active:
            https_verify_certificate: true
            http_path: /
            https_sni: ~
            type: http
            concurrency: 10
            healthy:
              interval: 0
              http_statuses:
              - 200
              - 302
              successes: 0
            unhealthy:
              http_failures: 0
              http_statuses:
              - 429
              - 404
              - 500
              - 501
              - 502
              - 503
              - 504
              - 505
              interval: 0
              tcp_failures: 0
              timeouts: 0
            timeout: 1
          threshold: 0
          passive:
            healthy:
              successes: 0
              http_statuses:
              - 200
              - 201
              - 202
              - 203
              - 204
              - 205
              - 206
              - 207
              - 208
              - 226
              - 300
              - 301
              - 302
              - 303
              - 304
              - 305
              - 306
              - 307
              - 308
            unhealthy:
              http_failures: 0
              http_statuses:
              - 429
              - 500
              - 503
              tcp_failures: 0
              timeouts: 0
            type: http
        slots: 10000
        client_certificate: ~
        name: upstreama
        hash_on: none
        tags: ~
        id: ab0060c9-7830-415a-9a84-d2d5dd76a04c
      targets:
      - upstream: ab0060c9-7830-415a-9a84-d2d5dd76a04c
        target: 127.0.0.1:6664
        created_at: 1618602543.967
        weight: 50
        tags: ~
        id: d72fa60a-31d3-436a-a4cb-a35444618a7a
      - upstream: ab0060c9-7830-415a-9a84-d2d5dd76a04c
        target: 127.0.0.1:6664
        created_at: 1618602544.967
        weight: 100
        tags: ~
        id: d72fa60a-31d3-436a-a4cb-a35444618a7b
      - upstream: ab0060c9-7830-415a-9a84-d2d5dd76a04c
        target: 127.0.0.1:6661
        created_at: 1618602534.682
        weight: 100
        tags: ~
        id: fe590183-61a1-4b59-b77c-5d70835d9714
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

    assert.match("Error: Failed parsing:", err)
    assert.match("in 'host': expected a string", err)
    assert.match("in 'port': value should be between 0 and 65535", err)
    assert.match("in 'routes': expected an array", err)
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
    assert(db.certificates:truncate())
    assert(db.ca_certificates:truncate())
    assert(db.targets:truncate())
    assert(db.upstreams:truncate())
    assert(db.keys:truncate())
    assert(db.key_sets:truncate())

    local filename = os.tmpname()
    os.remove(filename)
    filename = filename .. ".yml"

    -- starting kong just so the prefix is properly initialized
    assert(helpers.start_kong())

    local service1 = bp.services:insert({ name = "service1" }, { nulls = true })
    local route1 = bp.routes:insert({ service = service1, methods = { "POST" }, name = "a" }, { nulls = true })
    local plugin1 = bp.hmac_auth_plugins:insert({
      service = service1,
    }, { nulls = true })
    local plugin2 = bp.key_auth_plugins:insert({
      service = service1,
    }, { nulls = true })

    local service2 = bp.services:insert({ name = "service2" }, { nulls = true })
    local route2 = bp.routes:insert({ service = service2, methods = { "GET" }, name = "b" }, { nulls = true })
    local plugin3 = bp.rate_limiting_plugins:insert({
      service = service2,
      config = {
        minute = 100,
        policy = "redis",
        redis = {
          host = "localhost"
        }
      }
    }, { nulls = true })
    local plugin4 = bp.tcp_log_plugins:insert({
      service = service2,
    }, { nulls = true })
    local consumer = bp.consumers:insert(nil, { nulls = true })
    local acls = bp.acls:insert({ consumer = consumer }, { nulls = true })

    local keyauth = bp.keyauth_credentials:insert({ consumer = consumer, key = "hello" }, { nulls = true })

    local keyset = db.key_sets:insert {
      name = "testing keyset"
    }

    local pem_pub, pem_priv = helpers.generate_keys("PEM")
    local pem_key = db.keys:insert {
      name = "vault references",
      set = keyset,
      kid = "1",
      pem = { private_key = pem_priv, public_key = pem_pub}
    }

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
      "_transform",
      "acls",
      "consumers",
      "key_sets",
      "keyauth_credentials",
      "keys",
      "parameters",
      "plugins",
      "routes",
      "services",
    }, toplevel_keys)

    convert_yaml_nulls(yaml)

    assert.equals("3.0", yaml._format_version)
    assert.equals(false, yaml._transform)

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

    assert.equals(4, #yaml.plugins)
    table.sort(yaml.plugins, sort_by_name)
    assert.equals(plugin1.id, yaml.plugins[1].id)
    assert.equals(plugin1.name, yaml.plugins[1].name)
    assert.equals(service1.id, yaml.plugins[1].service)

    assert.equals(plugin2.id, yaml.plugins[2].id)
    assert.equals(plugin2.name, yaml.plugins[2].name)
    assert.equals(service1.id, yaml.plugins[2].service)

    assert.equals(plugin3.id, yaml.plugins[3].id)
    assert.equals(plugin3.name, yaml.plugins[3].name)
    assert.equals(plugin4.id, yaml.plugins[4].id)
    assert.equals(plugin4.name, yaml.plugins[4].name)
    assert.equals(service2.id, yaml.plugins[3].service)

    assert.equals(1, #yaml.consumers)
    assert.same(consumer, yaml.consumers[1])

    assert.equals(1, #yaml.acls)
    assert.equals(acls.group, yaml.acls[1].group)
    assert.equals(consumer.id, yaml.acls[1].consumer)

    assert.equals(1, #yaml.keyauth_credentials)
    assert.equals(keyauth.key, yaml.keyauth_credentials[1].key)
    assert.equals(consumer.id, yaml.keyauth_credentials[1].consumer)

    assert.equals(1, #yaml.key_sets)
    assert.equals(keyset.name, yaml.key_sets[1].name)
    assert.equals(pem_key.pem.public_key, yaml.keys[1].pem.public_key)
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
      shell.run("mv kong.yml kong.yml~", nil, 0)
    end
    finally(function()
      if kong_yml_exists then
        shell.run("mv kong.yml~ kong.yml", nil, 0)
      else
        os.remove("kong.yml")
      end
    end)

    os.remove("kong.yml")
    assert.is_nil(lfs.attributes("kong.yml"))
    assert(helpers.kong_exec("config init", {
      prefix = helpers.test_conf.prefix,
    }))
    assert.not_nil(lfs.attributes("kong.yml"))
    assert(helpers.kong_exec("config parse kong.yml", {
      prefix = helpers.test_conf.prefix,
    }))
  end)

  it("config init can take an argument", function()
    local tmpname = os.tmpname() .. ".yml"
    finally(function()
      os.remove(tmpname)
    end)

    os.remove(tmpname)
    assert.is_nil(lfs.attributes(tmpname))
    assert(helpers.kong_exec("config init " .. tmpname, {
      prefix = helpers.test_conf.prefix,
    }))
    assert.not_nil(lfs.attributes(tmpname))
    assert(helpers.kong_exec("config parse " .. tmpname, {
      prefix = helpers.test_conf.prefix,
    }))
  end)
end)
