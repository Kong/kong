local helpers = require "spec.helpers"
local ssl_fixtures     = require "spec.fixtures.ssl"

local ca_cert2 = [[
-----BEGIN CERTIFICATE-----
MIIEvjCCAqagAwIBAgIJALabx/Nup200MA0GCSqGSIb3DQEBCwUAMBMxETAPBgNV
BAMMCFlvbG80Mi4xMCAXDTE5MDkxNTE2Mjc1M1oYDzIxMTkwODIyMTYyNzUzWjAT
MREwDwYDVQQDDAhZb2xvNDIuMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoC
ggIBANIW67Ay0AtTeBY2mORaGet/VPL5jnBRz0zkZ4Jt7fEq3lbxYaJBnFI8wtz3
bHLtLsxkvOFujEMY7HVd+iTqbJ7hLBtK0AdgXDjf+HMmoWM7x0PkZO+3XSqyRBbI
YNoEaQvYBNIXrKKJbXIU6higQaXYszeN8r3+RIbcTIlZxy28msivEGfGTrNujQFc
r/eyf+TLHbRqh0yg4Dy/U/T6fqamGhFrjupRmOMugwF/BHMH2JHhBYkkzuZLgV2u
7Yh1S5FRlh11am5vWuRSbarnx72hkJ99rUb6szOWnJKKew8RSn3CyhXbS5cb0QRc
ugRc33p/fMucJ4mtCJ2Om1QQe83G1iV2IBn6XJuCvYlyWH8XU0gkRxWD7ZQsl0bB
8AFTkVsdzb94OM8Y6tWI5ybS8rwl8b3r3fjyToIWrwK4WDJQuIUx4nUHObDyw+KK
+MmqwpAXQWbNeuAc27FjuJm90yr/163aGuInNY5Wiz6CM8WhFNAi/nkEY2vcxKKx
irSdSTkbnrmLFAYrThaq0BWTbW2mwkOatzv4R2kZzBUOiSjRLPnbyiPhI8dHLeGs
wMxiTXwyPi8iQvaIGyN4DPaSEiZ1GbexyYFdP7sJJD8tG8iccbtJYquq3cDaPTf+
qv5M6R/JuMqtUDheLSpBNK+8vIe5e3MtGFyrKqFXdynJtfHVAgMBAAGjEzARMA8G
A1UdEwQIMAYBAf8CAQAwDQYJKoZIhvcNAQELBQADggIBAK0BmL5B1fPSMbFy8Hbc
/ESEunt4HGaRWmZZSa/aOtTjhKyDXLLJZz3C4McugfOf9BvvmAOZU4uYjfHTnNH2
Z3neBkdTpQuJDvrBPNoCtJns01X/nuqFaTK/Tt9ZjAcVeQmp51RwhyiD7nqOJ/7E
Hp2rC6gH2ABXeexws4BDoZPoJktS8fzGWdFBCHzf4mCJcb4XkI+7GTYpglR818L3
dMNJwXeuUsmxxKScBVH6rgbgcEC/6YwepLMTHB9VcH3X5VCfkDIyPYLWmvE0gKV7
6OU91E2Rs8PzbJ3EuyQpJLxFUQp8ohv5zaNBlnMb76UJOPR6hXfst5V+e7l5Dgwv
Dh4CeO46exmkEsB+6R3pQR8uOFtubH2snA0S3JA1ji6baP5Y9Wh9bJ5McQUgbAPE
sCRBFoDLXOj3EgzibohC5WrxN3KIMxlQnxPl3VdQvp4gF899mn0Z9V5dAsGPbxRd
quE+DwfXkm0Sa6Ylwqrzu2OvSVgbMliF3UnWbNsDD5KcHGIaFxVC1qkwK4cT3pyS
58i/HAB2+P+O+MltQUDiuw0OSUFDC0IIjkDfxLVffbF+27ef9C5NG81QlwTz7TuN
zeigcsBKooMJTszxCl6dtxSyWTj7hJWXhy9pXsm1C1QulG6uT4RwCa3m0QZoO7G+
6Wu6lP/kodPuoNubstIuPdi2
-----END CERTIFICATE-----
]]

local other_ca_cert = [[
-----BEGIN CERTIFICATE-----
MIIFrTCCA5WgAwIBAgIUFQe9z25yjw26iWzS+P7+hz1zx6AwDQYJKoZIhvcNAQEL
BQAwXjELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMQswCQYDVQQHDAJTRjENMAsG
A1UECgwES29uZzEUMBIGA1UECwwLRW5naW5lZXJpbmcxEDAOBgNVBAMMB3Jvb3Rf
Y2EwHhcNMjEwMzA0MTEyMjM0WhcNNDEwMjI3MTEyMjM0WjBeMQswCQYDVQQGEwJV
UzELMAkGA1UECAwCQ0ExCzAJBgNVBAcMAlNGMQ0wCwYDVQQKDARLb25nMRQwEgYD
VQQLDAtFbmdpbmVlcmluZzEQMA4GA1UEAwwHcm9vdF9jYTCCAiIwDQYJKoZIhvcN
AQEBBQADggIPADCCAgoCggIBAKKjido39I5SEmPhme0Z+hG0buOylXg+jmqHpJ/K
rs+dSq/PsJCjSke81eOP2MFa5duyBxdnXmMJwZYxuQ91bKxdzWVE9ZgCJgNJYsB6
y5+Fe7ypERwa2ebS/M99FFJ3EzpF017XdsgnSfVh1GEQOZkWQ1+7YrEUEgtwN5lO
MVUmj1EfoL+jQ/zwxwdxpLu3dh3Ica3szmx3YxqIPRnpyoYYqbktjL63gmFCjLeW
zEXdVZyoisdaA4iZ9e/wmuLR2/F4cbZ0SjU7QULZ2Zt/SCrs3CaJ3/ZAa6s84kjg
JBMav+GxbvATSuWQEajiVQrkW9HvXD/NUQBCzzZsOfpzn0044Ls7XvWDCCXs+xtG
Uhd5cJfmlcbHbZ9PU1xTBqdbwiRX+XlmX7CJRcfgnYnU/B3m5IheA1XKYhoXikgv
geRwq5uZ8Z2E/WONmFts46MLSmH43Ft+gIXA1u1g3eDHkU2bx9u592lZoluZtL3m
bmebyk+5bd0GdiHjBGvDSCf/fgaWROgGO9e0PBgdsngHEFmRspipaH39qveM1Cdh
83q4I96BRmjU5tvFXydFCvp8ABpZz9Gj0h8IRP+bK5ukU46YrEIxQxjBee1c1AAb
oatRJSJc2J6zSYXRnQfwf5OkhpmVYc+1TAyqPBfixa2TQ7OOhXxDYsJHAb7WySKP
lfonAgMBAAGjYzBhMB0GA1UdDgQWBBT00Tua7un0KobEs1aXuSZV8x4Q7TAfBgNV
HSMEGDAWgBT00Tua7un0KobEs1aXuSZV8x4Q7TAPBgNVHRMBAf8EBTADAQH/MA4G
A1UdDwEB/wQEAwIBhjANBgkqhkiG9w0BAQsFAAOCAgEAgI8CSmjvzQgmnzcNwqX5
o+KBWEMHJEqQfowaZE7o6xkvEljb1YHRDE0hlwUtD1vbKUthoHD8Mqim3No5z4J0
dEE+mXQ3zlJWKl5gqHs9KtcLhk51mf4VJ2TW8Z7AoE2OjWSnycLNdlpqUvxzCQOn
CIhvyDfs4OV1RYywbfiLLmzTCYT7Mt5ye1ZafoRNZ37DCnI/uqoOaMb+a6VaE+0F
ZXlDonXmy54QUmt6foSG/+kYaqdVLribsE6H+GpePmPTKKOvgE1RutR5+nvMJUB3
+zMQSPVVYLzizwV+Tq9il81qNQB2hZGvM8iSRraBNn8mwpx7M6kcoJ4gvCA3kHCI
rmuuzlhkNcmZYh0uG378CzhdEOV+JMmuCh4xt2SbQIr5Luqm/+Xoq4tDplKoUVkC
DScxPoFNoi9bZYW/ppcaeX5KT3Gt0JBaCfD7d0CtbUp/iPS1HtgXTIL9XiYPipsV
oPLtqvfeORl6aUuqs1xX8HvZrSgcld51+r8X31YIs6feYTFvlbfP0/Jhf2Cs0K/j
jhC0sGVdWO1C0akDlEBfuE5YMrehjYrrOnEavtTi9+H0vNaB+BGAJHIAj+BGj5C7
0EkbQdEyhB0pliy9qzbPtN5nt+y0I1lgN9VlFMub6r1u5novNzuVm+5ceBrxG+ga
T6nsr9aTE1yghO6GTWEPssw=
-----END CERTIFICATE-----
]]

assert:set_parameter("TableFormatLevel", 10)


local UUID_PATTERN = "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x"


for _, strategy in helpers.each_strategy() do
  describe("kong.db [#" .. strategy .. "]", function()
    local db, bp, service, route
    local global_plugin
    local ca1, ca2, other_ca
    local routes = {}
    local p1, p2, p3, p4, p5, p6

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "routes",
        "services",
        "plugins",
        "ca_certificates",
      }, {
        "reference-ca-cert",
      })

      global_plugin = db.plugins:insert({ name = "key-auth",
                                          protocols = { "http" },
                                        })
      assert.truthy(global_plugin)

      ca1 = assert(bp.ca_certificates:insert({
        cert = ssl_fixtures.cert_ca,
      }))

      ca2 = assert(bp.ca_certificates:insert({
        cert = ca_cert2,
      }))

      other_ca = assert(bp.ca_certificates:insert({
        cert = other_ca_cert,
      }))

      for i = 1, 6 do
        routes[i] = assert(bp.routes:insert({
          paths = { "/foo" .. i, },
        }))
      end

      p1 = assert(bp.plugins:insert({
        name = "reference-ca-cert",
        route = routes[1],
        config = {
          ca_certificates = { ca1.id },
        }
      }))

      p2 = assert(bp.plugins:insert({
        name = "reference-ca-cert",
        route = routes[2],
        config = {
          ca_certificates = { ca1.id },
        }
      }))

      p3 = assert(bp.plugins:insert({
        name = "reference-ca-cert",
        route = routes[3],
        config = {
          ca_certificates = { ca2.id },
        }
      }))

      p4 = assert(bp.plugins:insert({
        name = "reference-ca-cert",
        route = routes[4],
        config = {
          ca_certificates = { ca2.id },
        }
      }))

      p5 = assert(bp.plugins:insert({
        name = "reference-ca-cert",
        route = routes[5],
        config = {
          ca_certificates = { ca1.id, ca2.id },
        }
      }))

      p6 = assert(bp.plugins:insert({
        name = "reference-ca-cert",
        route = routes[6],
        config = {
          ca_certificates = { ca1.id, ca2.id },
        }
      }))
    end)

    describe("Plugins #plugins", function()

      before_each(function()
        service = bp.services:insert()
        route = bp.routes:insert({ service = { id = service.id },
                                   protocols = { "tcp" },
                                   sources = { { ip = "127.0.0.1" } },
                                 })
      end)

      describe(":insert()", function()
        it("checks composite uniqueness", function()
          local route = bp.routes:insert({ methods = {"GET"} })

          local plugin, err, err_t = db.plugins:insert({
            name = "key-auth",
            route = { id = route.id },
          })
          assert.is_nil(err_t)
          assert.is_nil(err)

          assert.matches(UUID_PATTERN, plugin.id)
          assert.is_number(plugin.created_at)
          plugin.id = nil
          plugin.created_at = nil
          plugin.updated_at = nil

          assert.same({
            config = {
              hide_credentials = false,
              run_on_preflight = true,
              key_in_header = true,
              key_in_query = true,
              key_in_body = false,
              key_names = { "apikey" },
            },
            protocols = { "grpc", "grpcs", "http", "https" },
            enabled = true,
            name = "key-auth",
            route = {
              id = route.id,
            },
          }, plugin)

          plugin, err, err_t = db.plugins:insert({
            name = "key-auth",
            route = route,
          })

          assert.falsy(plugin)
          assert.match("UNIQUE violation", err)
          assert.same("unique constraint violation", err_t.name)
          assert.same([[UNIQUE violation detected on '{consumer=null,name="key-auth",]] ..
                      [[route={id="]] .. route.id ..
                      [["},service=null}']], err_t.message)
        end)

        it("does not validate when associated to an incompatible route, or a service with only incompatible routes", function()
          local plugin, _, err_t = db.plugins:insert({ name = "key-auth",
                                                       protocols = { "http" },
                                                       route = { id = route.id },
                                                     })
          assert.is_nil(plugin)
          assert.equals(err_t.fields.protocols, "must match the associated route's protocols")

          local plugin, _, err_t = db.plugins:insert({ name = "key-auth",
                                                       protocols = { "http" },
                                                       service = { id = service.id },
                                                     })
          assert.is_nil(plugin)
          assert.equals(err_t.fields.protocols,
                        "must match the protocols of at least one route pointing to this Plugin's service")
        end)

        it("validates when associated to a service with no routes", function()
          local service_with_no_routes = bp.services:insert()
          local plugin, _, err_t = db.plugins:insert({ name = "key-auth",
                                                       protocols = { "http" },
                                                       service = { id = service_with_no_routes.id },
                                                     })
          assert.truthy(plugin)
          assert.is_nil(err_t)
        end)
      end)

      describe(":update()", function()
        it("checks composite uniqueness", function()
          local route = bp.routes:insert({ methods = {"GET"} })

          local plugin, err, err_t = db.plugins:insert({
            name = "key-auth",
            route = { id = route.id },
          })
          assert.is_nil(err_t)
          assert.is_nil(err)

          assert.matches(UUID_PATTERN, plugin.id)
          assert.is_number(plugin.created_at)
          plugin.id = nil
          plugin.created_at = nil
          plugin.updated_at = nil

          assert.same({
            config = {
              hide_credentials = false,
              run_on_preflight = true,
              key_in_header = true,
              key_in_query = true,
              key_in_body = false,
              key_names = { "apikey" },
            },
            protocols = { "grpc", "grpcs", "http", "https" },
            enabled = true,
            name = "key-auth",
            route = {
              id = route.id,
            },
          }, plugin)

          plugin, err, err_t = db.plugins:insert({
            name = "key-auth",
            route = route,
          })

          assert.falsy(plugin)
          assert.match("UNIQUE violation", err)
          assert.same("unique constraint violation", err_t.name)
          assert.same([[UNIQUE violation detected on '{consumer=null,name="key-auth",]] ..
                      [[route={id="]] .. route.id ..
                      [["},service=null}']], err_t.message)
        end)
      end)

      it("returns an error when updating mismatched plugins", function()
        local p, _, err_t = db.plugins:update(global_plugin,
                                              { route = { id = route.id } })
        assert.is_nil(p)
        assert.equals(err_t.fields.protocols, "must match the associated route's protocols")


        local p, _, err_t = db.plugins:update(global_plugin,
                                              { service = { id = service.id } })
        assert.is_nil(p)
        assert.equals(err_t.fields.protocols,
                      "must match the protocols of at least one route pointing to this Plugin's service")
      end)
    end)

    describe(":upsert()", function()
      it("returns an error when upserting mismatched plugins", function()
        local p, _, err_t = db.plugins:upsert(global_plugin,
                                              { route = { id = route.id }, protocols = { "http" } })
        assert.is_nil(p)
        assert.equals(err_t.fields.protocols, "must match the associated route's protocols")


        local p, _, err_t = db.plugins:upsert(global_plugin,
                                              { service = { id = service.id }, protocols = { "http" } })
        assert.is_nil(p)
        assert.equals(err_t.fields.protocols,
                      "must match the protocols of at least one route pointing to this Plugin's service")
      end)
    end)

    describe(":load_plugin_schemas()", function()
      it("loads custom entities with specialized methods", function()
        local ok, err = db.plugins:load_plugin_schemas({
          ["plugin-with-custom-dao"] = true,
        })
        assert.is_nil(err)
        assert.truthy(ok)

        assert.same("I was implemented for " .. strategy, db.custom_dao:custom_method())
      end)

      it("reports failure with missing plugins", function()
        local ok, err = db.plugins:load_plugin_schemas({
          ["missing"] = true,
        })
        assert.falsy(ok)
        assert.match("missing plugin is enabled but not installed", err, 1, true)
      end)

      describe("with bad PRIORITY fails; ", function()
        setup(function()
          local schema = {}
          package.loaded["kong.plugins.NaN_priority.schema"] = schema
          package.loaded["kong.plugins.NaN_priority.handler"] = { PRIORITY = 0/0, VERSION = "1.0" }
          package.loaded["kong.plugins.huge_negative.schema"] = schema
          package.loaded["kong.plugins.huge_negative.handler"] = { PRIORITY = -math.huge, VERSION = "1.0" }
          package.loaded["kong.plugins.string_priority.schema"] = schema
          package.loaded["kong.plugins.string_priority.handler"] = { PRIORITY = "abc", VERSION = "1.0" }
        end)

        teardown(function()
          package.loaded["kong.plugins.NaN_priority.schema"] = nil
          package.loaded["kong.plugins.NaN_priority.handler"] = nil
          package.loaded["kong.plugins.huge_negative.schema"] = nil
          package.loaded["kong.plugins.huge_negative.handler"] = nil
          package.loaded["kong.plugins.string_priority.schema"] = nil
          package.loaded["kong.plugins.string_priority.handler"] = nil
        end)

        it("NaN", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["NaN_priority"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "NaN_priority" cannot be loaded because its PRIORITY field is not a valid integer number, got: "nan"', err, 1, true)
        end)

        it("-math.huge", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["huge_negative"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "huge_negative" cannot be loaded because its PRIORITY field is not a valid integer number, got: "-inf"', err, 1, true)
        end)

        it("string", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["string_priority"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "string_priority" cannot be loaded because its PRIORITY field is not a valid integer number, got: "abc"', err, 1, true)
        end)

      end)

      describe("with bad VERSION fails; ", function()
        setup(function()
          local schema = {}
          package.loaded["kong.plugins.no_version.schema"] = schema
          package.loaded["kong.plugins.no_version.handler"] = { PRIORITY = 1000, VERSION = nil }
          package.loaded["kong.plugins.too_many.schema"] = schema
          package.loaded["kong.plugins.too_many.handler"] = { PRIORITY = 1000, VERSION = "1.0.0.0" }
          package.loaded["kong.plugins.number.schema"] = schema
          package.loaded["kong.plugins.number.handler"] = { PRIORITY = 1000, VERSION = 123 }
        end)

        teardown(function()
          package.loaded["kong.plugins.no_version.schema"] = nil
          package.loaded["kong.plugins.no_version.handler"] = nil
          package.loaded["kong.plugins.too_many.schema"] = nil
          package.loaded["kong.plugins.too_many.handler"] = nil
          package.loaded["kong.plugins.number.schema"] = nil
          package.loaded["kong.plugins.number.handler"] = nil
        end)

        it("without version", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["no_version"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "no_version" cannot be loaded because its VERSION field does not follow the "x.y.z" format, got: "nil"', err, 1, true)
        end)

        it("too many components", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["too_many"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "too_many" cannot be loaded because its VERSION field does not follow the "x.y.z" format, got: "1.0.0.0"', err, 1, true)
        end)

        it("number", function()
          local ok, err = db.plugins:load_plugin_schemas({
            ["number"] = true,
          })
          assert.falsy(ok)
          assert.match('Plugin "number" cannot be loaded because its VERSION field does not follow the "x.y.z" format, got: "123"', err, 1, true)
        end)

      end)

    end)

    describe(":select_by_ca_certificate()", function()
      it("selects the correct plugins", function()
        local plugins, err = db.plugins:select_by_ca_certificate(ca1.id, nil, {
          ["reference-ca-cert"] = true,
        })
        local expected = {
          [p1.id] = true,
          [p2.id] = true,
          [p5.id] = true,
          [p6.id] = true,
        }
        local res = {}
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 4)

        for _, p in ipairs(plugins) do
          res[p.id] = true
        end
        assert.are.same(expected, res)

        local plugins, err = db.plugins:select_by_ca_certificate(ca2.id, nil, {
          ["reference-ca-cert"] = true,
        })
        local expected = {
          [p3.id] = true,
          [p4.id] = true,
          [p5.id] = true,
          [p6.id] = true,
        }
        local res = {}
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 4)

        for _, p in ipairs(plugins) do
          res[p.id] = true
        end
        assert.are.same(expected, res)

        -- unreferenced ca certificate
        local plugins, err = db.plugins:select_by_ca_certificate(other_ca.id, nil, {
          ["reference-ca-cert"] = true,
        })
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 0)
      end)

      it("plugin_names default to all plugins", function()
        local plugins, err = db.plugins:select_by_ca_certificate(ca1.id, nil)
        local expected = {
          [p1.id] = true,
          [p2.id] = true,
          [p5.id] = true,
          [p6.id] = true,
        }
        local res = {}
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 4)

        for _, p in ipairs(plugins) do
          res[p.id] = true
        end
        assert.are.same(expected, res)

        local plugins, err = db.plugins:select_by_ca_certificate(ca2.id, nil)
        local expected = {
          [p3.id] = true,
          [p4.id] = true,
          [p5.id] = true,
          [p6.id] = true,
        }
        local res = {}
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 4)

        for _, p in ipairs(plugins) do
          res[p.id] = true
        end
        assert.are.same(expected, res)

        -- unreferenced ca certificate
        local plugins, err = db.plugins:select_by_ca_certificate(other_ca.id, nil)
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 0)
      end)

      it("limits the number of returned plugins", function()
        local plugins, err = db.plugins:select_by_ca_certificate(ca1.id, 1, {
          ["reference-ca-cert"] = true,
        })
        local expected = {
          [p1.id] = true,
          [p2.id] = true,
          [p5.id] = true,
          [p6.id] = true,
        }
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 1)
        assert(expected[plugins[1].id])

        local plugins, err = db.plugins:select_by_ca_certificate(ca2.id, 1, {
          ["reference-ca-cert"] = true,
        })
        local expected = {
          [p3.id] = true,
          [p4.id] = true,
          [p5.id] = true,
          [p6.id] = true,
        }
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 1)
        assert(expected[plugins[1].id])

        -- unreferenced ca certificate
        local plugins, err = db.plugins:select_by_ca_certificate(other_ca.id, 1, {
          ["reference-ca-cert"] = true,
        })
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 0)
      end)

      it("plugin_names supports string type", function()
        local plugins, err = db.plugins:select_by_ca_certificate(ca1.id, nil, "reference-ca-cert")
        local expected = {
          [p1.id] = true,
          [p2.id] = true,
          [p5.id] = true,
          [p6.id] = true,
        }
        local res = {}
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 4)

        for _, p in ipairs(plugins) do
          res[p.id] = true
        end
        assert.are.same(expected, res)
      end)

      it("return empty table when plugin doesn't reference ca_certificates", function()
        local plugins, err = db.plugins:select_by_ca_certificate(ca1.id, nil, "key-auth")
        assert.is_nil(err)
        assert(plugins)
        assert(#plugins == 0)
      end)

    end)
  end) -- kong.db [strategy]

end
