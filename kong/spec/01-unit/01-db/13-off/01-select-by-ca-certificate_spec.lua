local helpers = require "spec.helpers"
local txn = require "resty.lmdb.transaction"
local declarative = require "kong.db.declarative"

local CA_1_ID = "00000000-0000-0000-0000-000000000001"
local CA_1 = [[
-----BEGIN CERTIFICATE-----
MIIFsTCCA5mgAwIBAgIUdbhx3xkz+f798JXqZIqLCDE9Ev8wDQYJKoZIhvcNAQEL
BQAwYDELMAkGA1UEBhMCVVMxCzAJBgNVBAgMAkNBMQswCQYDVQQHDAJTRjENMAsG
A1UECgwEa29uZzEMMAoGA1UECwwDRlRUMRowGAYDVQQDDBF3d3cucm9vdC5rb25n
LmNvbTAeFw0yNDA3MDgxMzQxNTVaFw0zNDA3MDYxMzQxNTVaMGAxCzAJBgNVBAYT
AlVTMQswCQYDVQQIDAJDQTELMAkGA1UEBwwCU0YxDTALBgNVBAoMBGtvbmcxDDAK
BgNVBAsMA0ZUVDEaMBgGA1UEAwwRd3d3LnJvb3Qua29uZy5jb20wggIiMA0GCSqG
SIb3DQEBAQUAA4ICDwAwggIKAoICAQCn5xk7t84f58SwaMECan0537Iyc3JvBGDC
U24zmC3FWZOiqisQdm4VUSC9s7xJotAXEDHBpfFZEjc3+f9081tKZ4m2NZqxOt0a
yNSAUH9BZ15Ziuz1nmd4dsWnUpb2E5jWDYT5EJTF14/M3mATKT+ViHfUnLolQ9MR
YvH4jcC24b45+rr5UsQHGV71FOQ7jE/GAjn0iXCtxTCdFFEstQrmCb36SSjgfpQS
7/B9uH9jxfDSgvd0QULQ0tCto0zjfNcT7h8k6Jz4SaWIUMQ9DU1mVajeOSmyEWCh
P7otdQzjdpTRHyoPiDZKSi0Vkpt6fgnziw61eglt14L/0doclu1FsdKJXrVSaPGG
9ZIYdvfzOH7yAEVnODw7kknKp2b2vkQUEoy8m1OPD+f8RxSjlpa6FGEVCGGEFvwL
v1U7jSy1PXMJVDJ5WNaDw/HrMQFpIE/+70x/YQiTxRM3uwyqgjn4s2rvBqaxoWaW
saR9BqhLpfG8aDKJV/lrot/8EaeBwxuWZ8/GjgJmIrUNo9bNPnythZMAxtAL/h5q
B1I4b5CPB5JHDGDj+5nlD/Sa7rwFu0gCEvTCQkS6xX/C8QXWzbfH3oKg0nedLxCz
VEEHRW+umWvdcftkEpN5sls7aU2TEm56AZqtDvSdErH0IvoJ2s3nDbC474OqxSJ/
gbGYVZvRdwIDAQABo2MwYTAdBgNVHQ4EFgQU+l8F1VuLfqeC13PGf2GINeMgapAw
HwYDVR0jBBgwFoAU+l8F1VuLfqeC13PGf2GINeMgapAwDwYDVR0TAQH/BAUwAwEB
/zAOBgNVHQ8BAf8EBAMCAYYwDQYJKoZIhvcNAQELBQADggIBABB2yXKUr2GyU8Up
nCLWEeNYQBYCK98dMyp8A727XfLrAZLLxEWpS8JLamJJAeVruh49lOHlt+tz9z4y
g+A/u2ttNdKzyH2+u7qp8PR2KvFbUFl+VJIE75hi8GUGynYs6n/ogICVh6Kq7wWH
ou3sPAIv9fK3fCDbJqoLjuX6BsKFv3mItAqtEaio+5gJMg82PZtW6+g/QNWnfGO8
Ox3lYCCcoU9tz38ZLVTG4FghMI5O+5kxMpp7yoIFIk8Jb7SZPoslV5Z7J5MA2K6Y
xvxAkJbINGp1KEgIrsHtifVU555ryg6zXyySp9Mtwig1ZKRwxlsKjiiraUZiDgBd
Wup2pQ3hr9rlapM8WcWEVkBO8QFyFXi/bsY8Hlsmfvbjcs7hTaBZSJkk7ov6ltk/
dUS9ZfjeAIaUkWo6e3/I8NbK2vLEFQiMYWmHvYZ91jqLgxZP+pL6alWZbWuTLdfX
RGOEc859lWXiCKK3bUhnLNRY7r4ooRKkwLULaT13wPlYRZEurLbpZXpyVshZRkyz
hBAfkdnlzTMQFYZ7oWRpWXKg9lMtRtubEoFrCCSueK0A328qJfMgMNwO9eGNrHYt
/LZpOKe8Qr+0MvihbW1PceyaBsY5RxlqO2+WzaGx4x1WxS0i0T3fKti7uZiO6Ofy
9kUZGHfrVNrptILwcZJpa8NV0lpl
-----END CERTIFICATE-----
]]

local CA_2_ID = "00000000-0000-0000-0000-000000000002"
local CA_2 = [[
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

local insert_entity_for_txn = declarative.insert_entity_for_txn


local function lmdb_insert(name, entity)
  local t = txn.begin(512)
  local res, err = insert_entity_for_txn(t, name, entity, nil)
  if not res then
    error("lmdb insert failed: " .. err)
  end

  local ok, err = t:commit()
  if not ok then
    error("lmdb t:commit() failed: " .. err)
  end
end


-- insert into LMDB
local function db_insert(bp, name, entity)
  -- insert into dc blueprints
  entity = bp[name]:insert(entity)

  -- insert into LMDB
  lmdb_insert(name, entity)

  assert(kong.db[name]:select({id = entity.id}))

  return entity
end


describe("kong.db[entity]:select_by_ca_certificate() should works [#off]", function()
  local bp, db

  lazy_setup(function()
    bp, db = helpers.get_db_utils("off")

    db_insert(bp, "ca_certificates", {
      id = CA_1_ID,
      cert = CA_1,
    })

    db_insert(bp, "ca_certificates", {
      id = CA_2_ID,
      cert = CA_2,
    })
  end)

  it("services", function()
    db_insert(bp, "services", {
      name = "svc_1",
      host = "example.com",
      port = 80,
      ca_certificates = {
        CA_1_ID,
      },
    })

    db_insert(bp, "services", {
      name = "svc_2",
      host = "example.com",
      port = 80,
      ca_certificates = {
        CA_2_ID,
      },
    })

    local matches = db.services:select_by_ca_certificate(CA_1_ID, 2)
    assert.equals(1, #matches)
    assert.equals("svc_1", matches[1].name)

    matches = db.services:select_by_ca_certificate(CA_2_ID, 2)
    assert.equals(1, #matches)
    assert.equals("svc_2", matches[1].name)

    matches = db.services:select_by_ca_certificate(CA_2_ID, nil)
    assert.equals(1, #matches)
    assert.equals("svc_2", matches[1].name)
  end)
end)
