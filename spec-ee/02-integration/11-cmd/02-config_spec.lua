-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"
local cjson   = require "cjson"

describe("kong config", function()
  local db

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

    local client = helpers.admin_client()

    local res = client:get("/workspaces/default/meta")
    local body = assert.res_status(200, res)
    local json = cjson.decode(body)
    assert.is_nil(json.counts.plugins)
    assert.is_nil(json.counts.routes)
    assert.is_nil(json.counts.services)

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
end)
