local declarative_config = require "kong.db.schema.others.declarative_config"
local helpers = require "spec.helpers"
local lyaml = require "lyaml"
local tablex = require "pl.tablex"


local null = ngx.null


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
    for k,v in sortedpairs(t) do
      if k == "id" then
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


-- To generate the expected output of a test case, use the following.
-- Verify that the output is correct, then paste it back to the test file.
local function print_assert(config) -- luacheck: ignore
  local inspect = require("inspect")
  local remove_all_metatables = function(item, path)
    if path[#path] ~= inspect.METATABLE then return item end
  end
  local opts = { process = remove_all_metatables }

  print("assert.same(", require"inspect"(idempotent(config), opts):gsub("<userdata 1>", "null"), ", idempotent(config))")
end


describe("declarative config: flatten", function()
  local DeclarativeConfig

  lazy_setup(function()
    DeclarativeConfig = assert(declarative_config.load(helpers.test_conf.loaded_plugins))
  end)

  describe("core entities", function()
    describe("services:", function()
      it("accepts an empty list", function()
        local config = lyaml.load([[
          _format_version: "1.1"
          services:
        ]])
        config = DeclarativeConfig:flatten(config)
        assert.same({}, idempotent(config))
      end)

      it("accepts entities", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          services:
          - name: foo
            host: example.com
            protocol: https
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
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({
          services = {
            {
              id = "UUID",
              created_at = 1234567890,
              updated_at = 1234567890,
              name = "bar",
              protocol = "http",
              host = "example.test",
              path = null,
              port = 3000,
              connect_timeout = 60000,
              read_timeout = 60000,
              write_timeout = 60000,
              retries = 5,
              tags = {"hello", "world"},
              client_certificate = null
            },
            {
              id = "UUID",
              created_at = 1234567890,
              updated_at = 1234567890,
              name = "foo",
              protocol = "https",
              host = "example.com",
              path = null,
              port = 80,
              connect_timeout = 60000,
              read_timeout = 60000,
              write_timeout = 60000,
              retries = 5,
              tags = null,
              client_certificate = null
            },
          }
        }, idempotent(config))
      end)

      it("accepts field names with the same name as entities", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          routes:
          - name: foo
            path_handling: v1
            protocols: ["tls"]
            snis:
            - "example.com"
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({
          routes = {
            {
              tags = null,
              created_at = 1234567890,
              destinations = null,
              hosts = null,
              headers = null,
              id = "UUID",
              methods = null,
              name = "foo",
              paths = null,
              preserve_host = false,
              https_redirect_status_code = 426,
              protocols = { "tls" },
              regex_priority = 0,
              service = null,
              snis = { "example.com" },
              sources = null,
              strip_path = true,
              path_handling = "v1",
              updated_at = 1234567890
            }
          }
        }, idempotent(config))
      end)

      it("allows url shorthand", function()
        local config = lyaml.load([[
          _format_version: "1.1"
          services:
          - name: foo
            # url shorthand also works, and expands into multiple fields
            url: https://example.com:8000/hello/world
        ]])
        config = DeclarativeConfig:flatten(config)
        assert.same({
          services = {
            {
              id = "UUID",
              created_at = 1234567890,
              updated_at = 1234567890,
              tags = null,
              name = "foo",
              protocol = "https",
              host = "example.com",
              port = 8000,
              path = "/hello/world",
              connect_timeout = 60000,
              read_timeout = 60000,
              write_timeout = 60000,
              retries = 5,
              client_certificate = null
            }
          }
        }, idempotent(config))
      end)
    end)

    describe("plugins:", function()
      it("accepts an empty list", function()
        local config = lyaml.load([[
          _format_version: "1.1"
          plugins:
        ]])
        config = DeclarativeConfig:flatten(config)
        assert.same({}, idempotent(config))
      end)

      it("accepts entities", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          plugins:
            - name: key-auth
              _comment: my comment
              _ignore:
              - foo: bar
            - name: http-log
              config:
                http_endpoint: https://example.com
              _comment: my comment
              _ignore:
              - foo: bar
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({
          plugins = {
            {
              id = "UUID",
              tags = null,
              created_at = 1234567890,
              consumer = null,
              service = null,
              route = null,
              name = "http-log",
              enabled = true,
              protocols = { "grpc", "grpcs", "http", "https" },
              config = {
                http_endpoint = "https://example.com",
                content_type = "application/json",
                flush_timeout = 2,
                keepalive = 60000,
                method = "POST",
                queue_size = 1,
                retry_count = 10,
                timeout = 10000,
              }
            },
            {
              id = "UUID",
              tags = null,
              created_at = 1234567890,
              consumer = null,
              service = null,
              route = null,
              name = "key-auth",
              enabled = true,
              protocols = { "grpc", "grpcs", "http", "https" },
              config = {
                anonymous = null,
                hide_credentials = false,
                key_in_body = false,
                key_names = { "apikey" },
                run_on_preflight = true,
              }
            },
          }
        }, idempotent(config))
      end)

      it("fails with missing foreign relationships", function()
        local config = lyaml.load([[
          _format_version: "1.1"
          plugins:
            - name: http-log
              service: svc1
              consumer: my-consumer
              config:
                http_endpoint: https://example.com
        ]])
        local _, err = DeclarativeConfig:flatten(config)
        assert.same({
          plugins = {
            [1] = {
              "invalid reference 'consumer: my-consumer' (no such entry in 'consumers')",
              "invalid reference 'service: svc1' (no such entry in 'services')",
            }
          }
        }, idempotent(err))
      end)

      it("succeeds with present foreign relationships", function()
        local config = lyaml.load([[
          _format_version: "1.1"
          services:
            - name: svc1
              host: example.com
          routes:
            - name: r1
              path_handling: v1
              paths: [/]
              service: svc1
          consumers:
            - username: my-consumer
          plugins:
            - name: key-auth
              route: r1
            - name: http-log
              service: svc1
              consumer: my-consumer
              config:
                http_endpoint: https://example.com
        ]])
        config = DeclarativeConfig:flatten(config)
        assert.same({
          consumers = {
            {
              tags = null,
              created_at = 1234567890,
              custom_id = null,
              id = "UUID",
              username = "my-consumer"
            }
          },
          plugins = {
            {
              tags = null,
              config = {
                content_type = "application/json",
                flush_timeout = 2,
                http_endpoint = "https://example.com",
                keepalive = 60000,
                method = "POST",
                queue_size = 1,
                retry_count = 10,
                timeout = 10000
              },
              consumer = {
                id = "UUID"
              },
              created_at = 1234567890,
              enabled = true,
              id = "UUID",
              name = "http-log",
              route = null,
              protocols = { "grpc", "grpcs", "http", "https" },
              service = {
                id = "UUID"
              }
            },
            {
              tags = null,
              config = {
                anonymous = null,
                hide_credentials = false,
                key_in_body = false,
                key_names = { "apikey" },
                run_on_preflight = true
              },
              consumer = null,
              created_at = 1234567890,
              enabled = true,
              id = "UUID",
              name = "key-auth",
              route = {
                id = "UUID"
              },
              protocols = { "grpc", "grpcs", "http", "https" },
              service = null
            },
          },
          routes = {
            {
              tags = null,
              created_at = 1234567890,
              destinations = null,
              hosts = null,
              headers = null,
              id = "UUID",
              methods = null,
              name = "r1",
              paths = { "/" },
              preserve_host = false,
              protocols = { "http", "https" },
              https_redirect_status_code = 426,
              regex_priority = 0,
              service = {
                id = "UUID"
              },
              snis = null,
              sources = null,
              strip_path = true,
              path_handling = "v1",
              updated_at = 1234567890
            }
          },
          services = {
            {
              tags = null,
              connect_timeout = 60000,
              created_at = 1234567890,
              host = "example.com",
              id = "UUID",
              name = "svc1",
              path = null,
              port = 80,
              protocol = "http",
              read_timeout = 60000,
              retries = 5,
              updated_at = 1234567890,
              write_timeout = 60000,
              client_certificate = null
            }
          }
        }, idempotent(config))
      end)
    end)

    describe("nested relationships:", function()
      describe("plugins in services", function()
        it("accepts an empty list", function()
          local config = lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              plugins: []
              host: example.com
          ]])
          config = DeclarativeConfig:flatten(config)
          assert.same({
            services = {
              {
                tags = null,
                connect_timeout = 60000,
                created_at = 1234567890,
                host = "example.com",
                id = "UUID",
                name = "foo",
                path = null,
                port = 80,
                protocol = "http",
                read_timeout = 60000,
                retries = 5,
                updated_at = 1234567890,
                write_timeout = 60000,
                client_certificate = null
              }
            }
          }, idempotent(config))
        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
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
                  host: 127.0.0.1
                  port: 10000
          ]]))
          config = DeclarativeConfig:flatten(config)
          assert.same({
            plugins = { {
                config = {
                  anonymous = null,
                  hide_credentials = false
                },
                consumer = null,
                created_at = 1234567890,
                enabled = true,
                id = "UUID",
                name = "basic-auth",
                protocols = { "grpc", "grpcs", "http", "https" },
                route = null,
                service = {
                  id = "UUID"
                },
                tags = null
              }, {
                config = {
                  content_type = "application/json",
                  flush_timeout = 2,
                  http_endpoint = "https://example.com",
                  keepalive = 60000,
                  method = "POST",
                  queue_size = 1,
                  retry_count = 10,
                  timeout = 10000
                },
                consumer = null,
                created_at = 1234567890,
                enabled = true,
                id = "UUID",
                name = "http-log",
                protocols = { "grpc", "grpcs", "http", "https" },
                route = null,
                service = {
                  id = "UUID"
                },
                tags = null
              }, {
                config = {
                  anonymous = null,
                  hide_credentials = false,
                  key_in_body = false,
                  key_names = { "apikey" },
                  run_on_preflight = true
                },
                consumer = null,
                created_at = 1234567890,
                enabled = true,
                id = "UUID",
                name = "key-auth",
                protocols = { "grpc", "grpcs", "http", "https" },
                route = null,
                service = {
                  id = "UUID"
                },
                tags = null
              }, {
                config = {
                  host = "127.0.0.1",
                  keepalive = 60000,
                  port = 10000,
                  timeout = 10000,
                  tls = false,
                  tls_sni = null
                },
                consumer = null,
                created_at = 1234567890,
                enabled = true,
                id = "UUID",
                name = "tcp-log",
                protocols = { "grpc", "grpcs", "http", "https" },
                route = null,
                service = {
                  id = "UUID"
                },
                tags = null
              } },
            services = { {
                connect_timeout = 60000,
                created_at = 1234567890,
                host = "example.test",
                id = "UUID",
                name = "bar",
                path = null,
                port = 3000,
                protocol = "http",
                read_timeout = 60000,
                retries = 5,
                tags = null,
                updated_at = 1234567890,
                write_timeout = 60000,
                client_certificate = null
              }, {
                connect_timeout = 60000,
                created_at = 1234567890,
                host = "example.com",
                id = "UUID",
                name = "foo",
                path = null,
                port = 80,
                protocol = "https",
                read_timeout = 60000,
                retries = 5,
                tags = null,
                updated_at = 1234567890,
                write_timeout = 60000,
                client_certificate = null
              } }
          }, idempotent(config))
        end)
      end)

      describe("routes in services", function()
        it("accepts an empty list", function()
          local config = lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              routes: []
              host: example.com
          ]])
          config = DeclarativeConfig:flatten(config)
          assert.same({
            services = {
              {
                tags = null,
                connect_timeout = 60000,
                created_at = 1234567890,
                host = "example.com",
                id = "UUID",
                name = "foo",
                path = null,
                port = 80,
                protocol = "http",
                read_timeout = 60000,
                retries = 5,
                updated_at = 1234567890,
                write_timeout = 60000,
                client_certificate = null
              }
            }
          }, idempotent(config))
        end)

        it("accepts a single entity", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              host: example.com
              protocol: https
              routes:
                - path_handling: v1
                  paths:
                  - /path
          ]]))
          config = DeclarativeConfig:flatten(config)
          assert.same({
            routes = { {
                created_at = 1234567890,
                destinations = null,
                hosts = null,
                headers = null,
                id = "UUID",
                methods = null,
                name = null,
                paths = { "/path" },
                preserve_host = false,
                protocols = { "http", "https" },
                https_redirect_status_code = 426,
                regex_priority = 0,
                service = {
                  id = "UUID"
                },
                snis = null,
                sources = null,
                strip_path = true,
                path_handling = "v1",
                tags = null,
                updated_at = 1234567890
              } },
            services = { {
                connect_timeout = 60000,
                created_at = 1234567890,
                host = "example.com",
                id = "UUID",
                name = "foo",
                path = null,
                port = 80,
                protocol = "https",
                read_timeout = 60000,
                retries = 5,
                tags = null,
                updated_at = 1234567890,
                write_timeout = 60000,
                client_certificate = null
              } }
          }, idempotent(config))
        end)

        it("accepts multiple entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              host: example.com
              protocol: https
              routes:
                - path_handling: v1
                  paths:
                  - /path
                  name: r1
                - path_handling: v1
                  hosts:
                  - example.com
                  name: r2
                - path_handling: v1
                  methods: ["GET", "POST"]
                  name: r3
            - name: bar
              host: example.test
              port: 3000
              routes:
                - path_handling: v1
                  paths:
                  - /path
                  hosts:
                  - example.com
                  methods: ["GET", "POST"]
                  name: r4
          ]]))
          config = DeclarativeConfig:flatten(config)
          assert.same({
            routes = { {
                created_at = 1234567890,
                destinations = null,
                hosts = null,
                headers = null,
                id = "UUID",
                methods = null,
                name = "r1",
                paths = { "/path" },
                preserve_host = false,
                protocols = { "http", "https" },
                https_redirect_status_code = 426,
                regex_priority = 0,
                service = {
                  id = "UUID"
                },
                snis = null,
                sources = null,
                strip_path = true,
                path_handling = "v1",
                tags = null,
                updated_at = 1234567890
              }, {
                created_at = 1234567890,
                destinations = null,
                hosts = { "example.com" },
                headers = null,
                id = "UUID",
                methods = null,
                name = "r2",
                paths = null,
                preserve_host = false,
                protocols = { "http", "https" },
                https_redirect_status_code = 426,
                regex_priority = 0,
                service = {
                  id = "UUID"
                },
                snis = null,
                sources = null,
                strip_path = true,
                path_handling = "v1",
                tags = null,
                updated_at = 1234567890
              }, {
                created_at = 1234567890,
                destinations = null,
                hosts = null,
                headers = null,
                id = "UUID",
                methods = { "GET", "POST" },
                name = "r3",
                paths = null,
                preserve_host = false,
                protocols = { "http", "https" },
                https_redirect_status_code = 426,
                regex_priority = 0,
                service = {
                  id = "UUID"
                },
                snis = null,
                sources = null,
                strip_path = true,
                path_handling = "v1",
                tags = null,
                updated_at = 1234567890
              }, {
                created_at = 1234567890,
                destinations = null,
                hosts = { "example.com" },
                headers = null,
                id = "UUID",
                methods = { "GET", "POST" },
                name = "r4",
                paths = { "/path" },
                preserve_host = false,
                protocols = { "http", "https" },
                https_redirect_status_code = 426,
                regex_priority = 0,
                service = {
                  id = "UUID"
                },
                snis = null,
                sources = null,
                strip_path = true,
                path_handling = "v1",
                tags = null,
                updated_at = 1234567890
              } },
            services = { {
                connect_timeout = 60000,
                created_at = 1234567890,
                host = "example.test",
                id = "UUID",
                name = "bar",
                path = null,
                port = 3000,
                protocol = "http",
                read_timeout = 60000,
                retries = 5,
                tags = null,
                updated_at = 1234567890,
                write_timeout = 60000,
                client_certificate = null
              }, {
                connect_timeout = 60000,
                created_at = 1234567890,
                host = "example.com",
                id = "UUID",
                name = "foo",
                path = null,
                port = 80,
                protocol = "https",
                read_timeout = 60000,
                retries = 5,
                tags = null,
                updated_at = 1234567890,
                write_timeout = 60000,
                client_certificate = null
              } }
          }, idempotent(config))
        end)
      end)

      describe("plugins in routes in services", function()
        it("accepts an empty list", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              host: example.com
              protocol: https
              routes:
              - name: foo
                path_handling: v1
                methods: ["GET"]
                plugins:
          ]]))
          config = DeclarativeConfig:flatten(config)
          assert.same({
            routes = {
              {
                tags = null,
                created_at = 1234567890,
                destinations = null,
                hosts = null,
                headers = null,
                id = "UUID",
                methods = { "GET" },
                name = "foo",
                paths = null,
                preserve_host = false,
                protocols = { "http", "https" },
                https_redirect_status_code = 426,
                regex_priority = 0,
                service = {
                  id = "UUID"
                },
                snis = null,
                sources = null,
                strip_path = true,
                path_handling = "v1",
                updated_at = 1234567890
              }
            },
            services = {
              {
                tags = null,
                connect_timeout = 60000,
                created_at = 1234567890,
                host = "example.com",
                id = "UUID",
                name = "foo",
                path = null,
                port = 80,
                protocol = "https",
                read_timeout = 60000,
                retries = 5,
                updated_at = 1234567890,
                write_timeout = 60000,
                client_certificate = null
              }
            }
          }, idempotent(config))
        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            services:
            - name: foo
              host: example.com
              protocol: https
              routes:
              - name: foo
                path_handling: v1
                methods: ["GET"]
                plugins:
                  - name: key-auth
                  - name: http-log
                    config:
                      http_endpoint: https://example.com
            - name: bar
              host: example.test
              port: 3000
              routes:
              - name: bar
                path_handling: v1
                paths:
                - /
                plugins:
                - name: basic-auth
                - name: tcp-log
                  config:
                    host: 127.0.0.1
                    port: 10000
          ]]))
          config = DeclarativeConfig:flatten(config)
          assert.same({
            plugins = { {
                config = {
                  anonymous = null,
                  hide_credentials = false
                },
                consumer = null,
                created_at = 1234567890,
                enabled = true,
                id = "UUID",
                name = "basic-auth",
                protocols = { "grpc", "grpcs", "http", "https" },
                route = {
                  id = "UUID"
                },
                service = null,
                tags = null
              }, {
                config = {
                  content_type = "application/json",
                  flush_timeout = 2,
                  http_endpoint = "https://example.com",
                  keepalive = 60000,
                  method = "POST",
                  queue_size = 1,
                  retry_count = 10,
                  timeout = 10000
                },
                consumer = null,
                created_at = 1234567890,
                enabled = true,
                id = "UUID",
                name = "http-log",
                protocols = { "grpc", "grpcs", "http", "https" },
                route = {
                  id = "UUID"
                },
                service = null,
                tags = null
              }, {
                config = {
                  anonymous = null,
                  hide_credentials = false,
                  key_in_body = false,
                  key_names = { "apikey" },
                  run_on_preflight = true
                },
                consumer = null,
                created_at = 1234567890,
                enabled = true,
                id = "UUID",
                name = "key-auth",
                protocols = { "grpc", "grpcs", "http", "https" },
                route = {
                  id = "UUID"
                },
                service = null,
                tags = null
              }, {
                config = {
                  host = "127.0.0.1",
                  keepalive = 60000,
                  port = 10000,
                  timeout = 10000,
                  tls = false,
                  tls_sni = null
                },
                consumer = null,
                created_at = 1234567890,
                enabled = true,
                id = "UUID",
                name = "tcp-log",
                protocols = { "grpc", "grpcs", "http", "https" },
                route = {
                  id = "UUID"
                },
                service = null,
                tags = null
              } },
            routes = { {
                created_at = 1234567890,
                destinations = null,
                hosts = null,
                headers = null,
                id = "UUID",
                methods = null,
                name = "bar",
                paths = { "/" },
                preserve_host = false,
                protocols = { "http", "https" },
                https_redirect_status_code = 426,
                regex_priority = 0,
                service = {
                  id = "UUID"
                },
                snis = null,
                sources = null,
                strip_path = true,
                path_handling = "v1",
                tags = null,
                updated_at = 1234567890
              }, {
                created_at = 1234567890,
                destinations = null,
                hosts = null,
                headers = null,
                id = "UUID",
                methods = { "GET" },
                name = "foo",
                paths = null,
                preserve_host = false,
                protocols = { "http", "https" },
                https_redirect_status_code = 426,
                regex_priority = 0,
                service = {
                  id = "UUID"
                },
                snis = null,
                sources = null,
                strip_path = true,
                path_handling = "v1",
                tags = null,
                updated_at = 1234567890
              } },
            services = { {
                connect_timeout = 60000,
                created_at = 1234567890,
                host = "example.test",
                id = "UUID",
                name = "bar",
                path = null,
                port = 3000,
                protocol = "http",
                read_timeout = 60000,
                retries = 5,
                tags = null,
                updated_at = 1234567890,
                write_timeout = 60000,
                client_certificate = null
              }, {
                connect_timeout = 60000,
                created_at = 1234567890,
                host = "example.com",
                id = "UUID",
                name = "foo",
                path = null,
                port = 80,
                protocol = "https",
                read_timeout = 60000,
                retries = 5,
                tags = null,
                updated_at = 1234567890,
                write_timeout = 60000,
                client_certificate = null
              } }
          }, idempotent(config))
        end)
      end)
    end)
    describe("upstream:", function()
      it("identical targets", function()
        local config = assert(lyaml.load([[
          _format_version: '1.1'
          upstreams:
          - name: first-upstream
            targets:
            - target: 127.0.0.1:6661
              weight: 1
          - name: second-upstream
            targets:
            - target: 127.0.0.1:6661
              weight: 1
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({
          targets = {
            {
              created_at = 1234567890,
              id = "UUID",
              tags = null,
              target = '127.0.0.1:6661',
              upstream = { id = 'UUID' },
              weight = 1,
            },
            {
              created_at = 1234567890,
              id = "UUID",
              tags = null,
              target = '127.0.0.1:6661',
              upstream = { id = 'UUID' },
              weight = 1,
            },
          },

        }, idempotent({targets = config.targets}))
      end)
    end)
  end)

  describe("custom entities", function()
    describe("basicauth_credentials:", function()
      it("accepts an empty list", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          basicauth_credentials:
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({}, idempotent(config))

        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          basicauth_credentials:
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({}, idempotent(config))

        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - username: consumer
            basicauth_credentials:
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({
          consumers = {
            {
              id = 'UUID',
              username = 'consumer',
              custom_id = null,
              created_at = 1234567890,
              tags = null,
            },
          },
        }, idempotent(config))
      end)

      it("accepts as a nested entity", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - username: consumer
            basicauth_credentials:
            - username: username
              password: password
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({
          consumers = {
            {
              id = 'UUID',
              username = 'consumer',
              custom_id = null,
              created_at = 1234567890,
              tags = null,
            },
          },
          basicauth_credentials = {
            {
              id = 'UUID',
              consumer = {
                id = 'UUID',
              },
              username = 'username',
              password = 'password',
              created_at = 1234567890,
              tags = null,
            },
          },
        }, idempotent(config))
      end)

      it("accepts as a nested entity by id", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - id: 0fe87b4a-ce29-515a-88ec-8547e66550b9
            username: consumer
            basicauth_credentials:
            - username: username
              password: password
              consumer: 0fe87b4a-ce29-515a-88ec-8547e66550b9
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({
          consumers = {
            {
              id = 'UUID',
              username = 'consumer',
              custom_id = null,
              created_at = 1234567890,
              tags = null,
            },
          },
          basicauth_credentials = {
            {
              id = 'UUID',
              consumer = {
                id = 'UUID',
              },
              username = 'username',
              password = 'password',
              created_at = 1234567890,
              tags = null,
            },
          },
        }, idempotent(config))
      end)

      it("fails as a nested entity by incorrect id", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - id: 0fe87b4a-ce29-515a-88ec-8547e66550b9
            username: consumer
            basicauth_credentials:
            - username: username
              password: password
              consumer: 00000000-0000-0000-0000-000000000000
        ]]))
        local config, err = DeclarativeConfig:flatten(config)

        assert.equal(nil, config)
        assert.same({
          consumers = {
            {
              basicauth_credentials = {
                {
                  ["@entity"] = {
                    "all or none of these fields must be set: 'password', 'consumer.id'",
                  },
                  consumer = 'value must be null',
                },
              },
            },
          },
        }, idempotent(err))
      end)

      it("accepts as a nested entity by username", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - username: consumer
            basicauth_credentials:
            - username: username
              password: password
              consumer: consumer
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({
          consumers = {
            {
              id = 'UUID',
              username = 'consumer',
              custom_id = null,
              created_at = 1234567890,
              tags = null,
            },
          },
          basicauth_credentials = {
            {
              id = 'UUID',
              consumer = {
                id = 'UUID',
              },
              username = 'username',
              password = 'password',
              created_at = 1234567890,
              tags = null,
            },
          },
        }, idempotent(config))
      end)

      it("fails as a nested entity by incorrect username", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - username: consumer
            basicauth_credentials:
            - username: username
              password: password
              consumer: incorrect
        ]]))
        local config, err = DeclarativeConfig:flatten(config)
        assert.equal(nil, config)
        assert.same({
          consumers = {
            {
              basicauth_credentials = {
                {
                  ["@entity"] = {
                    "all or none of these fields must be set: 'password', 'consumer.id'",
                  },
                  consumer = 'value must be null',
                },
              },
            },
          },
        }, idempotent(err))
      end)

      it("accepts as an unnested entity by id", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - id: 0fe87b4a-ce29-515a-88ec-8547e66550b9
            username: consumer
          basicauth_credentials:
          - consumer: 0fe87b4a-ce29-515a-88ec-8547e66550b9
            username: username
            password: password

        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({
          consumers = {
            {
              id = 'UUID',
              username = 'consumer',
              custom_id = null,
              created_at = 1234567890,
              tags = null,
            },
          },
          basicauth_credentials = {
            {
              id = 'UUID',
              consumer = {
                id = 'UUID',
              },
              username = 'username',
              password = 'password',
              created_at = 1234567890,
              tags = null,
            },
          },
        }, idempotent(config))
      end)

      it("fails as an unnested entity by incorrect id", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - id: 0fe87b4a-ce29-515a-88ec-8547e66550b9
            username: consumer
          basicauth_credentials:
          - consumer: 00000000-0000-0000-0000-000000000000
            username: username
            password: password

        ]]))
        local config, err = DeclarativeConfig:flatten(config)
        assert.equal(nil, config)
        assert.same({
          basicauth_credentials = {
            {
              ["@entity"] = {
                "all or none of these fields must be set: 'password', 'consumer.id'",
              },
            },
          },
        }, idempotent(err))
      end)

      it("accepts as an unnested entity by username", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - username: consumer
          basicauth_credentials:
          - consumer: consumer
            username: username
            password: password

        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({
          consumers = {
            {
              id = 'UUID',
              username = 'consumer',
              custom_id = null,
              created_at = 1234567890,
              tags = null,
            },
          },
          basicauth_credentials = {
            {
              id = 'UUID',
              consumer = {
                id = 'UUID',
              },
              username = 'username',
              password = 'password',
              created_at = 1234567890,
              tags = null,
            },
          },
        }, idempotent(config))
      end)

      it("fails as an unnested entity by incorrect username", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - username: consumer
          basicauth_credentials:
          - consumer: incorrect
            username: username
            password: password

        ]]))
        local config, err = DeclarativeConfig:flatten(config)
        assert.equal(nil, config)
        assert.same({
          basicauth_credentials = {
            {
              ["@entity"] = {
                "all or none of these fields must be set: 'password', 'consumer.id'",
              },
            },
          },
        }, idempotent(err))
      end)
    end)

    describe("oauth2_credentials:", function()
      it("accepts an empty list", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          oauth2_credentials:
        ]]))
        config = DeclarativeConfig:flatten(config)
        assert.same({}, idempotent(config))
      end)

      it("fails with invalid foreign key references", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          oauth2_credentials:
          - name: my-credential
            consumer: foo
            redirect_uris:
            - https://example.com
          - name: another-credential
            consumer: foo
            redirect_uris:
            - https://example.test
        ]]))
        local _, err = DeclarativeConfig:flatten(config)
        err = idempotent(err)
        assert.same({
          oauth2_credentials = {
            [1] = {
              [1] = "invalid reference 'consumer: foo' (no such entry in 'consumers')"
            },
            [2] = {
              [1] = "invalid reference 'consumer: foo' (no such entry in 'consumers')"
            },
          }
        }, err)
      end)

      it("accepts entities", function()
        local config = assert(lyaml.load([[
          _format_version: "1.1"
          consumers:
          - username: bob
            oauth2_credentials:
            - name: my-credential
              redirect_uris:
              - https://example.com
              tags:
              - tag1
            - name: another-credential
              redirect_uris:
              - https://example.test
              tags:
              - tag2
        ]]))
        config = DeclarativeConfig:flatten(config)
        config.consumers = nil
        assert.same({
          oauth2_credentials = { {
              client_id = "RANDOM",
              client_secret = "RANDOM",
              consumer = {
                id = "UUID"
              },
              created_at = 1234567890,
              id = "UUID",
              name = "another-credential",
              redirect_uris = { "https://example.test" },
              tags = { "tag2" },
            }, {
              client_id = "RANDOM",
              client_secret = "RANDOM",
              consumer = {
                id = "UUID",
              },
              created_at = 1234567890,
              id = "UUID",
              name = "my-credential",
              redirect_uris = { "https://example.com" },
              tags = { "tag1" },
            } }
        }, idempotent(config))
      end)
    end)

    describe("flat relationships:", function()
      describe("jwt_secrets (globally unique) to consumers", function()
        it("accepts entities", function()
          local key = "-----BEGIN PUBLIC KEY-----\\n" ..
                      "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDMYfnvWtC8Id5bPKae5yXSxQTt\\n" ..
                      "+Zpul6AnnZWfI2TtIarvjHBFUtXRo96y7hoL4VWOPKGCsRqMFDkrbeUjRrx8iL91\\n" ..
                      "4/srnyf6sh9c8Zk04xEOpK1ypvBz+Ks4uZObtjnnitf0NBGdjMKxveTq+VE7BWUI\\n" ..
                      "yQjtQ8mbDOsiLLvh7wIDAQAB\\n" ..
                      "-----END PUBLIC KEY-----"
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            consumers:
              - username: foo
            jwt_secrets:
              - consumer: foo
                key: "https://keycloak/auth/realms/foo"
                algorithm: RS256
                rsa_public_key: "]] .. key .. [["
          ]]))

          config = DeclarativeConfig:flatten(config)
          config.jwt_secrets[next(config.jwt_secrets)].secret = nil
          assert.same({
            consumers = { {
                created_at = 1234567890,
                custom_id = null,
                id = "UUID",
                tags = null,
                username = "foo"
              } },
            jwt_secrets = { {
                algorithm = "RS256",
                consumer = {
                  id = "UUID"
                },
                created_at = 1234567890,
                id = "UUID",
                key = "https://keycloak/auth/realms/foo",
                rsa_public_key = key:gsub("\\n", "\n"),
                tags = null,
              } }
          }, idempotent(config))
        end)
      end)

      describe("targets (not globally unique) to upstreams", function()
        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: '1.1'
            upstreams:
            - name: first-upstream
            - name: second-upstream
            targets:
            - upstream: first-upstream
              target: 127.0.0.1:6661
              weight: 1
            - upstream: second-upstream
              target: 127.0.0.1:6661
              weight: 1
          ]]))

          config = DeclarativeConfig:flatten(config)
          assert.same({
            targets = { {
                created_at = 1234567890,
                id = "UUID",
                tags = null,
                target = "127.0.0.1:6661",
                upstream = {
                  id = "UUID"
                },
                weight = 1
              }, {
                created_at = 1234567890,
                id = "UUID",
                tags = null,
                target = "127.0.0.1:6661",
                upstream = {
                  id = "UUID"
                },
                weight = 1
              } },
            upstreams = { {
                algorithm = "round-robin",
                created_at = 1234567890,
                hash_fallback = "none",
                hash_fallback_header = null,
                hash_on = "none",
                hash_on_cookie = null,
                hash_on_cookie_path = "/",
                hash_on_header = null,
                healthchecks = {
                  active = {
                    concurrency = 10,
                    healthy = {
                      http_statuses = { 200, 302 },
                      interval = 0,
                      successes = 0
                    },
                    http_path = "/",
                    https_sni = null,
                    https_verify_certificate = true,
                    timeout = 1,
                    type = "http",
                    unhealthy = {
                      http_failures = 0,
                      http_statuses = { 429, 404, 500, 501, 502, 503, 504, 505 },
                      interval = 0,
                      tcp_failures = 0,
                      timeouts = 0
                    }
                  },
                  passive = {
                    healthy = {
                      http_statuses = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 226, 300, 301, 302, 303, 304, 305, 306, 307, 308 },
                      successes = 0
                    },
                    type = "http",
                    unhealthy = {
                      http_failures = 0,
                      http_statuses = { 429, 500, 503 },
                      tcp_failures = 0,
                      timeouts = 0
                    }
                  },
                  threshold = 0
                },
                host_header = null,
                id = "UUID",
                name = "first-upstream",
                slots = 10000,
                tags = null
              }, {
                algorithm = "round-robin",
                created_at = 1234567890,
                hash_fallback = "none",
                hash_fallback_header = null,
                hash_on = "none",
                hash_on_cookie = null,
                hash_on_cookie_path = "/",
                hash_on_header = null,
                healthchecks = {
                  active = {
                    concurrency = 10,
                    healthy = {
                      http_statuses = { 200, 302 },
                      interval = 0,
                      successes = 0
                    },
                    http_path = "/",
                    https_sni = null,
                    https_verify_certificate = true,
                    timeout = 1,
                    type = "http",
                    unhealthy = {
                      http_failures = 0,
                      http_statuses = { 429, 404, 500, 501, 502, 503, 504, 505 },
                      interval = 0,
                      tcp_failures = 0,
                      timeouts = 0
                    }
                  },
                  passive = {
                    healthy = {
                      http_statuses = { 200, 201, 202, 203, 204, 205, 206, 207, 208, 226, 300, 301, 302, 303, 304, 305, 306, 307, 308 },
                      successes = 0
                    },
                    type = "http",
                    unhealthy = {
                      http_failures = 0,
                      http_statuses = { 429, 500, 503 },
                      tcp_failures = 0,
                      timeouts = 0
                    }
                  },
                  threshold = 0
                },
                host_header = null,
                id = "UUID",
                name = "second-upstream",
                slots = 10000,
                tags = null
              } }
          }, idempotent(config))

        end)
      end)
    end)

    describe("nested relationships:", function()
      describe("oauth2_credentials in consumers", function()
        it("accepts an empty list", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            consumers:
            - username: bob
              oauth2_credentials:
          ]]))
          config = DeclarativeConfig:flatten(config)
          assert.same({
            consumers = { {
                created_at = 1234567890,
                custom_id = null,
                id = "UUID",
                tags = null,
                username = "bob"
              } }
          }, idempotent(config))

        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            consumers:
            - username: bob
              oauth2_credentials:
              - name: my-credential
                redirect_uris:
                - https://example.com
              - name: another-credential
                redirect_uris:
                - https://example.test
          ]]))
          config = DeclarativeConfig:flatten(config)
          assert.same({
            consumers = { {
                created_at = 1234567890,
                custom_id = null,
                id = "UUID",
                tags = null,
                username = "bob"
              } },
            oauth2_credentials = { {
                client_id = "RANDOM",
                client_secret = "RANDOM",
                consumer = {
                  id = "UUID"
                },
                created_at = 1234567890,
                id = "UUID",
                name = "another-credential",
                redirect_uris = { "https://example.test" },
                tags = null,
              }, {
                client_id = "RANDOM",
                client_secret = "RANDOM",
                consumer = {
                  id = "UUID"
                },
                created_at = 1234567890,
                id = "UUID",
                name = "my-credential",
                redirect_uris = { "https://example.com" },
                tags = null,
              } }
          }, idempotent(config))
        end)
      end)

      describe("oauth2_tokens in oauth2_credentials", function()
        it("accepts an empty list", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            consumers:
            - username: bob
            oauth2_credentials:
            - name: my-credential
              consumer: bob
              redirect_uris:
              - https://example.com
              oauth2_tokens:
          ]]))
          config = DeclarativeConfig:flatten(config)
          config.consumers = nil
          assert.same({
            oauth2_credentials = { {
                client_id = "RANDOM",
                client_secret = "RANDOM",
                consumer = {
                  id = "UUID"
                },
                created_at = 1234567890,
                id = "UUID",
                name = "my-credential",
                redirect_uris = { "https://example.com" },
                tags = null
              } }
          }, idempotent(config))
        end)

        it("accepts entities", function()
          local config = assert(lyaml.load([[
            _format_version: "1.1"
            consumers:
            - username: bob
            oauth2_credentials:
            - name: my-credential
              consumer: bob
              redirect_uris:
              - https://example.com
              oauth2_tokens:
              - expires_in: 1
                scope: "bar"
              - expires_in: 10
                scope: "foo"
          ]]))
          local config = DeclarativeConfig:flatten(config)
          config.consumers = nil
          assert.same({
            oauth2_credentials = { {
                client_id = "RANDOM",
                client_secret = "RANDOM",
                consumer = {
                  id = "UUID"
                },
                created_at = 1234567890,
                id = "UUID",
                name = "my-credential",
                redirect_uris = { "https://example.com" },
                tags = null,
              } },
            oauth2_tokens = {
              {
                access_token = "RANDOM",
                authenticated_userid = null,
                created_at = 1234567890,
                credential = {
                  id = "UUID"
                },
                expires_in = 1,
                id = "UUID",
                refresh_token = null,
                scope = "bar",
                service = null,
                token_type = "bearer"
              }, {
                access_token = "RANDOM",
                authenticated_userid = null,
                created_at = 1234567890,
                credential = {
                  id = "UUID"
                },
                expires_in = 10,
                id = "UUID",
                refresh_token = null,
                scope = "foo",
                service = null,
                token_type = "bearer"
              }
            }
          }, idempotent(config))
        end)

      end)
    end)
  end)

end)
