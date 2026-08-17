local helpers          = require "spec.helpers"
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

for _, strategy in helpers.each_strategy() do
  describe("db.services #" .. strategy, function()
    local bp, db
    local ca1, ca2, other_ca
    local srv1, srv2, srv3, srv4, srv5, srv6

    lazy_setup(function()
      bp, db = helpers.get_db_utils(strategy, {
        "services",
        "ca_certificates",
      })

      ca1 = assert(bp.ca_certificates:insert({
        cert = ssl_fixtures.cert_ca,
      }))

      ca2 = assert(bp.ca_certificates:insert({
        cert = ca_cert2,
      }))

      other_ca = assert(bp.ca_certificates:insert({
        cert = other_ca_cert,
      }))

      local url = "https://" .. helpers.mock_upstream_host .. ":" .. helpers.mock_upstream_port

      srv1 = assert(bp.services:insert {
        url = url,
        protocol = "https",
        ca_certificates = { ca1.id },
      })

      srv2 = assert(bp.services:insert {
        url = url,
        protocol = "https",
        ca_certificates = { ca1.id },
      })

      srv3 = assert(bp.services:insert {
        url = url,
        protocol = "https",
        ca_certificates = { ca2.id },
      })

      srv4 = assert(bp.services:insert {
        url = url,
        protocol = "https",
        ca_certificates = { ca2.id },
      })

      srv5 = assert(bp.services:insert {
        url = url,
        protocol = "https",
        ca_certificates = { ca1.id, ca2.id },
      })

      srv6 = assert(bp.services:insert {
        url = url,
        protocol = "https",
        ca_certificates = { ca1.id, ca2.id },
      })
    end)

    lazy_teardown(function()
      db.services:truncate()
      db.ca_certificates:truncate()
    end)

    describe("services:select_by_ca_certificate()", function()
      it("selects the correct services", function()
        local services, err = db.services:select_by_ca_certificate(ca1.id)
        local expected = {
          [srv1.id] = true,
          [srv2.id] = true,
          [srv5.id] = true,
          [srv6.id] = true,
        }
        local res = {}
        assert.is_nil(err)
        assert(services)
        assert(#services == 4)

        for _, s in ipairs(services) do
          res[s.id] = true
        end
        assert.are.same(expected, res)

        local services, err = db.services:select_by_ca_certificate(ca2.id)
        local expected = {
          [srv3.id] = true,
          [srv4.id] = true,
          [srv5.id] = true,
          [srv6.id] = true,
        }
        local res = {}
        assert.is_nil(err)
        assert(services)
        assert(#services == 4)

        for _, s in ipairs(services) do
          res[s.id] = true
        end
        assert.are.same(expected, res)

        -- unreferenced ca certificate
        local services, err = db.services:select_by_ca_certificate(other_ca.id)
        assert.is_nil(err)
        assert(services)
        assert(#services == 0)
      end)

      it("limits the number of returned services", function()
        local services, err = db.services:select_by_ca_certificate(ca1.id, 1)
        local expected = {
          [srv1.id] = true,
          [srv2.id] = true,
          [srv5.id] = true,
          [srv6.id] = true,
        }
        assert.is_nil(err)
        assert(services)
        assert(#services == 1)
        assert(expected[services[1].id])

        local services, err = db.services:select_by_ca_certificate(ca2.id, 1)
        local expected = {
          [srv3.id] = true,
          [srv4.id] = true,
          [srv5.id] = true,
          [srv6.id] = true,
        }
        assert.is_nil(err)
        assert(services)
        assert(#services == 1)
        assert(expected[services[1].id])

        -- unreferenced ca certificate
        local services, err = db.services:select_by_ca_certificate(other_ca.id, 1)
        assert.is_nil(err)
        assert(services)
        assert(#services == 0)
      end)
    end)
  end)
end
