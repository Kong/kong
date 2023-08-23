-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require "cjson"

local ee_jwt = require "kong.enterprise_edition.jwt"
local ee_utils = require "kong.enterprise_edition.utils"

describe("request", function()
  local http, opts

  local client = mock({ request_uri = function() end})

  local request = ee_utils.request

  setup(function()
    http = mock(require "resty.http", true)
    stub(http, "new").returns(client)
    package.loaded["resty.http"] = http
  end)

  teardown(function()
    http.new:revert()
  end)

  before_each(function()
    -- reset opts to defaults
    opts = {
      headers = {},
      method = "GET",
      ssl_verify  = false,
    }
  end)

  after_each(function()
    client.request_uri:clear()
  end)

  describe("makes http request_uri calls with arguments", function()
    describe("GET", function()
      it("encodes data as url arguments", function()
        request("http://some-web.site", {
          data = { foo = "bar", bar = "baz" }
        })

        assert.stub(client.request_uri)
              .was.called_with(client, "http://some-web.site?bar=baz&foo=bar",
                               opts)
      end)
    end)
    for _, method in ipairs({ "POST", "PUT", "PATCH" }) do
      local url = "http://some-web.site"

      describe("#".. method, function()
        describe("data", function()
          describe("encodes data as body if body is not specified", function()
            it("defaulting content type to multipart/form-data", function()
              local match = require("luassert.match")
              local function is_request(state, arguments)
                local compare_no_order = require "pl.tablex".compare_no_order

                local function compare_header(actual, boundary)
                  return compare_no_order({
                    ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
                  }, actual)
                end

                local function compare_body(actual, boundary, data)
                  -- Import string functions (e.g. split)
                  require "pl.stringx".import()

                  -- Verify start/end and gather the form content
                  local expected_start = "--" .. boundary .. "\r\n"
                  local expected_end = "--" .. boundary .. "--\r\n"
                  local starts_with = actual:sub(1, #expected_start) == expected_start
                  local ends_with = actual:sub(-#expected_end) == expected_end
                  local actual_form_content = actual:sub(1 + #expected_start, -(1 + #expected_end))
                  actual_form_content = actual_form_content:split("--" .. boundary .. "\r\n")

                  local expected_form_content = {}
                  for k, v in pairs(data) do
                    table.insert(expected_form_content, "Content-Disposition: form-data; name=\"" .. k .. "\"\r\n\r\n" .. v .. "\r\n")
                  end

                  return starts_with and
                         ends_with and
                         compare_no_order(expected_form_content, actual_form_content)
                end

                return function(value)
                  return arguments[1].method == value.method and
                         arguments[1].ssl_verify == value.ssl_verify and
                         compare_header(value.headers, arguments[2]) and
                         compare_body(value.body, arguments[2], arguments[3])
                end
              end
              assert:register("matcher", "is_request", is_request)

              local data = { foo = "bar", bar = "baz" }
              request(url, {
                method = method,
                data = data
              })

              local boundary = "8fd84e9444e3946c"
              assert.stub(client.request_uri).was.called_with(client, url, match.is_request({
                  method = method,
                  ssl_verify = false,
                  headers = {
                    ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,
                  }
                }, boundary, data))
            end)

            it("with content-type application/#json body is data as json", function()
              local data = { foo = "bar", bar = "baz" }
              request(url, {
                method = method,
                data = data,
                headers = { ["Content-Type"] = "application/json" },
              })

              opts = {
                method = method,
                ssl_verify = false,
                body = cjson.encode(data),
                headers = {
                  ["Content-Type"] = "application/json",
                },
              }

              assert.stub(client.request_uri).was.called_with(client, url, opts)
            end)

            it("with content-type application/#json body is data as json", function()
              local data = { foo = "bar", bar = "baz" }
              request(url, {
                method = method,
                data = data,
                headers = { ["Content-Type"] = "application/json" },
              })

              opts = {
                method = method,
                ssl_verify = false,
                body = cjson.encode(data),
                headers = {
                  ["Content-Type"] = "application/json",
                },
              }

              assert.stub(client.request_uri).was.called_with(client, url, opts)
            end)

            it("with content-type www-form-urlencoded body is data urllencoded", function()
              local data = { foo = "bar", bar = "baz" }
              request(url, {
                method = method,
                data = data,
                headers = {
                  ["Content-Type"] = "application/x-www-form-urlencoded",
                },
              })

              opts = {
                method = method,
                ssl_verify = false,
                body = "bar=baz&foo=bar",
                headers = {
                  ["Content-Type"] = "application/x-www-form-urlencoded",
                },
              }

              assert.stub(client.request_uri).was.called_with(client, url, opts)
            end)

          end)

          it("body is sent as it is always", function()
            local body = "HELLO WORLD"

            request(url, {
              method = method,
              body = body,
            })

            opts.method = method
            opts.body = body
            opts.headers = {}

            assert.stub(client.request_uri).was.called_with(client, url, opts)
          end)

          describe("sign_with", function()
            it("signs body with a provided function", function()
              local body = "HELLO WORLD"

              request(url, {
                method = method,
                body = body,
                sign_with = function(body)
                  return "some_algo", "body_hmac"
                end
              })

              opts.method = method
              opts.body = body
              opts.headers = {
                ["X-Kong-Signature"] = "some_algo=body_hmac",
              }

              assert.stub(client.request_uri).was.called_with(client, url, opts)
            end)

            it("sign header can be specified with sign_header", function()
              local body = "HELLO WORLD"

              request(url, {
                method = method,
                body = body,
                sign_header = "X-My-Signature",
                sign_with = function(body)
                  return "some_algo", "body_hmac"
                end
              })

              opts.method = method
              opts.body = body
              opts.headers = {
                ["X-My-Signature"] = "some_algo=body_hmac",
              }

              assert.stub(client.request_uri).was.called_with(client, url, opts)
            end)
          end)
        end)
      end)
    end
  end)

  teardown(function()
    mock.revert(http)
  end)
end)


describe("validate_reset_jwt", function()
  it("should return an error if fails to parse jwt", function()
    stub(ee_jwt, "parse_JWT").returns(nil, "error!")
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error if header is missing", function()
    local jwt = {}

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error type is not 'JWT'", function()
    local jwt = {
      header = {
        typ = "not_JWT",
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error if alg is not 'HS256'", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "not_HS256",
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error if claims is missing", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "HS256",
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error if expiration is missing from claims", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "HS256",
      },
      claims = {},
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return an error if expired", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "HS256",
      },
      claims = {
        exp = ngx.time() - 1000000,
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.EXPIRED_JWT, err)
  end)

  it("should return an error if id is missing from claims", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "HS256",
      },
      claims = {
        exp = ngx.time() + 1000000,
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local ok, err = ee_utils.validate_reset_jwt()
    assert.is_nil(ok)
    assert.equal(ee_jwt.INVALID_JWT, err)
  end)

  it("should return jwt if valid", function()
    local jwt = {
      header = {
        typ = "JWT",
        alg = "HS256",
      },
      claims = {
        exp = ngx.time() + 1000000,
        id = 1,
      },
    }

    stub(ee_jwt, "parse_JWT").returns(jwt)
    local res, err = ee_utils.validate_reset_jwt()
    assert.is_nil(err)
    assert.equal(jwt, res)
  end)
end)
