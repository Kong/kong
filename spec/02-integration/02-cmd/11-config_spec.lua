local helpers = require "spec.helpers"
local cjson = require "cjson"


local function make_yaml_file(content)
  local filename = os.tmpname()
  os.rename(filename, filename .. ".yml")
  filename = filename .. ".yml"
  local fd = assert(io.open(filename, "w"))
  assert(fd:write(helpers.unindent(content)))
  assert(fd:write("\n")) -- ensure last line ends in newline
  assert(fd:close())
  return filename
end


describe("kong config", function()
  local db

  lazy_setup(function()
    local _
    _, db = helpers.get_db_utils(nil, {}) -- runs migrations
    helpers.prepare_prefix()
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

  it("config imports a yaml file", function()
    assert(db.plugins:truncate())
    assert(db.routes:truncate())
    assert(db.services:truncate())

    local filename = make_yaml_file([[
      _format_version: "1.1"
      services:
      - name: foo
        host: example.com
        protocol: https
        _comment: my comment
        _ignore:
        - foo: bar
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
        plugins:
        - name: basic-auth
        - name: tcp-log
          config:
            port: 10000
            host: 127.0.0.1

    ]])

    finally(function()
      os.remove(filename)
    end)

    helpers.start_kong({
      nginx_conf = "spec/fixtures/custom_nginx.template",
    })

    assert(helpers.kong_exec("config --vv import " .. filename, {
      prefix = helpers.test_conf.prefix,
    }))

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
  end)
end)
