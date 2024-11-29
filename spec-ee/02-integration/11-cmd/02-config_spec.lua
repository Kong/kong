-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson   = require "cjson"

describe("kong config", function()
  local _, db

  lazy_setup(function()
    _, db = helpers.get_db_utils(nil, {}) -- runs migrations
  end)
  after_each(function()
    helpers.kill_all()
  end)
  lazy_teardown(function()
    helpers.clean_prefix()
  end)

  it("#db config imports a yaml with custom workspace", function()
    local filename = helpers.make_yaml_file([[
      _format_version: "1.1"
      _workspace: foo
    ]])

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
      database = helpers.test_conf.database,
      pg_database = helpers.test_conf.pg_database,
    }))

  end)

  it("#db config db_import can reinitialize the workspace entity counters automatically", function()
    assert(db.plugins:truncate())
    assert(db.routes:truncate())
    assert(db.services:truncate())
    assert(db.workspace_entity_counters:truncate())

    -- note that routes have no name
    local filename = helpers.make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: foo
        url: http://example.test
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
        url: https://example.test
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

    local client = helpers.admin_client()

    local res = client:get("/workspaces/default/meta")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equals(0, json.counts.plugins)
    assert.equals(0, json.counts.routes)
    assert.equals(0, json.counts.services)

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))

    res = client:get("/workspaces/default/meta")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(4, json.counts.plugins)
    assert.equals(2, json.counts.routes)
    assert.equals(2, json.counts.services)

    assert(helpers.stop_kong())
  end)

  it("#db config db_import can import licenses", function()
    assert(db.licenses:truncate())
    assert(db.routes:truncate())
    assert(db.services:truncate())

    -- note that routes have no name
    local filename = helpers.make_yaml_file([[
      _format_version: "3.0"
      _transform: true

      licenses:
      - updated_at: 1668152723
        id: c2f25974-d669-46e3-b7a7-36991735a018
        created_at: 1668152723
        payload: '{"license":{"payload":{"customer":"<Account Name (Account) field in Salesforce>","product_subscription":"Enterprise","support_plan":"Silver","admin_seats":"5","license_creation_date":"2018-01-01","license_expiration_date":"2099-12-31","license_key":"0014100000LyLlf_00641000008di8T"},"signature":"LS0tLS1CRUdJTiBQR1AgTUVTU0FHRS0tLS0tCgpvd0did012TXdDVjJyL3J6aHlkL2I4OWdQTzJXeEJDNXc3Zk15TlFpMFRnbEtkWFFJTm5Dd3NMY3dNdzh6Y0xTCnhNelV4TUxjMGpMWjBDakpNdEU0emRna05jblEwdExJd2lBcE9TMHQwU3paMk5BbzBUVEoxQ3pOcktPVWhVR00KaTBGV1RKRkZhSjd2SWUrNVA0cDIzRzZUZ05uRHlnU3loSUdMVXdBbXNzYVo0Wi9HalhZRmhXTEhlNnZhOXlabgp1OWJVeVRaT3kxOGI3WDFyMXFrVlltRzdObnN3L05OZjBLK2xYc3BaYXhjNldhSi9hdUw1aElaTEowdVk1dDZkCmI3cW9VUEQrVm5ZQQo9ZnV1cgotLS0tLUVORCBQR1AgTUVTU0FHRS0tLS0tCg=="}}'
      services:
      - host: example.test
        name: example
        port: 80
        protocol: http
        routes:
        - name: headers
          paths:
          - /headers
          strip_path: false
    ]])

    assert(helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }))

    local client = helpers.admin_client()

    local res = client:get("/services")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.equals(0, #json.data)

    res = client:get("/routes")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(0, #json.data)

    res = client:get("/licenses")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(0, #json.data)

    assert(helpers.kong_exec("config db_import " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))

    res = client:get("/services")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(1, #json.data)

    res = client:get("/routes")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(1, #json.data)

    res = client:get("/licenses")
    body = assert.res_status(200, res)
    json = cjson.decode(body)
    assert.equals(1, #json.data)

    assert(helpers.stop_kong())
  end)
end)
