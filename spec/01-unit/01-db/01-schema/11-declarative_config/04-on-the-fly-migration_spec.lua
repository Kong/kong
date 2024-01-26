require("spec.helpers") -- for kong.log
local declarative = require "kong.db.declarative"
local conf_loader = require "kong.conf_loader"

local null = ngx.null

local helpers = require "spec.helpers"
local tablex = require "pl.tablex"
local utils = require "kong.tools.utils"

local function sort_by_key(t)
  return function(a, b)
    for _, k in ipairs({"name", "username", "host", "scope"}) do
      local ka = t[a][k] ~= null and t[a][k]
      local kb = t[b][k] ~= null and t[b][k]
      if ka and kb then
        return ka < kb
      end
    end
  end
end

local function sortedpairs(t, fn)
  local ks = tablex.keys(t)
  table.sort(ks, fn and fn(t))
  local i = 0
  return function()
    i = i + 1
    return ks[i], t[ks[i]]
  end
end


assert:set_parameter("TableFormatLevel", 10)


local function idempotent(tbl, err)
  assert.table(tbl, err)

  for entity, items in sortedpairs(tbl) do
    local new = {}
    for _, item in sortedpairs(items, sort_by_key) do
      table.insert(new, item)
    end
    tbl[entity] = new
  end

  local function recurse_fields(t)
    helpers.deep_sort(t)
    for k,v in sortedpairs(t) do
      if k == "id" and utils.is_valid_uuid(v) then
        t[k] = "UUID"
      end
      if k == "client_id" or k == "client_secret" or k == "access_token" then
        t[k] = "RANDOM"
      end
      if type(v) == "table" then
        recurse_fields(v)
      end
      if k == "created_at" or k == "updated_at" then
        t[k] = 1234567890
      end
    end
  end
  recurse_fields(tbl)

  table.sort(tbl)
  return tbl
end


describe("declarative config: on the fly migration", function()
  for _, format_version in ipairs{ "1.1", "2.1", "3.0"} do
    it("routes handling for format version " .. format_version, function()
      local dc = assert(declarative.new_config(conf_loader()))
      local configs = {
      [[
        _format_version: "]] .. format_version .. [["
        services:
        - name: foo
          host: example.com
          protocol: https
          enabled: false
          _comment: my comment
          _ignore:
          - foo: bar
        - name: bar
          host: example.test
          port: 3000
          _comment: my comment
          _ignore:
          - foo: bar
          tags: [hello, world]
        routes:
        - name: foo
          path_handling: v0
          protocols: ["https"]
          paths: ["/regex.+", "/prefix" ]
          snis:
          - "example.com"
          service: foo
      ]],
      [[
        _format_version: "]] .. format_version .. [["
        services:
        - name: foo
          host: example.com
          protocol: https
          enabled: false
          _comment: my comment
          _ignore:
          - foo: bar
          routes:
          - name: foo
            path_handling: v0
            protocols: ["https"]
            paths: ["/regex.+", "/prefix" ]
            snis:
            - "example.com"
        - name: bar
          host: example.test
          port: 3000
          _comment: my comment
          _ignore:
          - foo: bar
          tags: [hello, world]
        ]],
      }

      for _, config in ipairs(configs) do

      local config_tbl = assert(dc:parse_string(config))

      local sorted = idempotent(config_tbl)

      assert.same("bar", sorted.services[1].name)
      assert.same("example.test", sorted.services[1].host)
      assert.same("http", sorted.services[1].protocol)
      assert.same(3000, sorted.services[1].port)

      assert.same("foo", sorted.services[2].name)
      assert.same("example.com", sorted.services[2].host)
      assert.same("https", sorted.services[2].protocol)
      assert.same(false, sorted.services[2].enabled)

      assert.same("foo", sorted.routes[1].name)
      assert.same({"https"}, sorted.routes[1].protocols)
      if format_version == "3.0" then
        assert.same({ "/prefix", "/regex.+", }, sorted.routes[1].paths)
      else
        assert.same({ "/prefix", "~/regex.+", }, sorted.routes[1].paths)
      end
      end
    end)
  end
end)

it("validation should happens after migration", function ()
  local dc = assert(declarative.new_config(conf_loader()))
  local config =
    [[
      _format_version: "2.1"
      services:
      - name: foo
        host: example.com
        protocol: https
        enabled: false
        _comment: my comment
      - name: bar
        host: example.test
        port: 3000
        _comment: my comment
        routes:
        - name: foo
          path_handling: v0
          protocols: ["https"]
          paths: ["/regex.+(", "/prefix" ]
          snis:
          - "example.com"
    ]]

    local config_tbl, err = dc:parse_string(config)

    assert.falsy(config_tbl)
    assert.matches("invalid regex:", err, nil, true)
    assert.matches("/regex.+(", err, nil, true)
    assert.matches("missing closing parenthesis", err, nil, true)
end)
