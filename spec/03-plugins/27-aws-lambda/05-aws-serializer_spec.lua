local utils = require "kong.tools.utils"
local date = require "date"

describe("[AWS Lambda] aws-gateway input", function()

  local mock_request
  local old_ngx
  local aws_serialize


  local function reload_module()
    -- make sure to reload the module
    package.loaded["kong.tracing.request_id"] = nil
    package.loaded["kong.plugins.aws-lambda.request-util"] = nil
    aws_serialize = require "kong.plugins.aws-lambda.request-util".aws_serializer
  end


  setup(function()
    old_ngx = ngx
    local body_data
    _G.ngx = setmetatable({
      req = {
        get_headers = function() return utils.cycle_aware_deep_copy(mock_request.headers) end,
        get_uri_args = function() return utils.cycle_aware_deep_copy(mock_request.query) end,
        read_body = function() body_data = mock_request.body end,
        get_body_data = function() return body_data end,
        http_version = function() return mock_request.http_version end,
        start_time = function() return mock_request.start_time end,
      },
      log = function() end,
      get_phase = function() -- luacheck: ignore
        return "access"
      end,
      encode_base64 = old_ngx.encode_base64
    }, {
      -- look up any unknown key in the mock request, eg. .var and .ctx tables
      __index = function(self, key)
        return mock_request and mock_request[key]
      end,
    })
  end)

  teardown(function()
    -- make sure to drop the mocks
    package.loaded["kong.plugins.aws-lambda.request-util"] = nil
    ngx = old_ngx         -- luacheck: ignore
  end)



  it("serializes a request regex", function()
    mock_request = {
      http_version = "1.1",
      start_time = 1662436514,
      headers = {
        ["single-header"] = "hello world",
        ["multi-header"] = { "first", "second" },
        ["user-agent"] = "curl/7.54.0",
      },
      query = {
        ["single-query"] = "hello world",
        ["multi-query"] = { "first", "second" },
        boolean = true,
      },
      body = "text",
      var = {
        request_method = "GET",
        upstream_uri = "/123/strip/more?boolean=;multi-query=first;single-query=hello%20world;multi-query=second",
        kong_request_id = "1234567890",
        host = "abc.myhost.test",
        remote_addr = "123.123.123.123"
      },
      ctx = {
        router_matches = {
          uri_captures = {
            "123",
            [0] = "/123/strip/more",
            version = "123"
          },
          uri = "/(?<version>\\d+)/strip"
        },
      },
    }

    reload_module()

    local out = aws_serialize()

    assert.same({
        httpMethod = "GET",
        path = "/123/strip/more",
        resource = "/(?<version>\\d+)/strip",
        pathParameters = {
          version = "123",
        },
        isBase64Encoded = true,
        body = ngx.encode_base64("text"),
        headers = {
          ["multi-header"] = "first",
          ["single-header"] = "hello world",
          ["user-agent"] = "curl/7.54.0",
        },
        multiValueHeaders = {
          ["multi-header"] = { "first", "second" },
          ["single-header"] = { "hello world" },
          ["user-agent"] = { "curl/7.54.0" },
        },
        queryStringParameters = {
          boolean = true,
          ["multi-query"] = "first",
          ["single-query"] = "hello world",
        },
        multiValueQueryStringParameters = {
          boolean = { true} ,
          ["multi-query"] = { "first", "second" },
          ["single-query"] = { "hello world" },
        },
        requestContext = {
          path = "/123/strip/more",
          protocol = "HTTP/1.1",
          httpMethod = "GET",
          domainName = "abc.myhost.test",
          domainPrefix = "abc",
          identity = { sourceIp = "123.123.123.123", userAgent = "curl/7.54.0" },
          requestId = "1234567890",
          requestTime = date(1662436514):fmt("%d/%b/%Y:%H:%M:%S %z"),
          requestTimeEpoch = 1662436514 * 1000,
          resourcePath = "/123/strip/more",
        }
      }, out)
  end)

  it("serializes a request no-regex", function()
    mock_request = {
      http_version = "1.0",
      start_time = 1662436514,
      headers = {
        ["single-header"] = "hello world",
        ["multi-header"] = { "first", "second" },
        ["user-agent"] = "curl/7.54.0",
      },
      query = {
        ["single-query"] = "hello world",
        ["multi-query"] = { "first", "second" },
        boolean = true,
      },
      body = "text",
      var = {
        request_method = "GET",
        upstream_uri = "/plain/strip/more?boolean=;multi-query=first;single-query=hello%20world;multi-query=second",
        kong_request_id = "1234567890",
        host = "def.myhost.test",
        remote_addr = "123.123.123.123"
      },
      ctx = {
        router_matches = {
          uri = "/plain/strip"
        },
      },
    }

    reload_module()

    local out = aws_serialize()

    assert.same({
        httpMethod = "GET",
        path = "/plain/strip/more",
        resource = "/plain/strip",
        pathParameters = {},
        isBase64Encoded = true,
        body = ngx.encode_base64("text"),
        headers = {
          ["multi-header"] = "first",
          ["single-header"] = "hello world",
          ["user-agent"] = "curl/7.54.0",
        },
        multiValueHeaders = {
          ["multi-header"] = { "first", "second" },
          ["single-header"] = { "hello world" },
          ["user-agent"] = { "curl/7.54.0" },
        },
        queryStringParameters = {
          boolean = true,
          ["multi-query"] = "first",
          ["single-query"] = "hello world",
        },
        multiValueQueryStringParameters = {
          boolean = { true} ,
          ["multi-query"] = { "first", "second" },
          ["single-query"] = { "hello world" },
        },
        requestContext = {
          path = "/plain/strip/more",
          protocol = "HTTP/1.0",
          httpMethod = "GET",
          domainName = "def.myhost.test",
          domainPrefix = "def",
          identity = { sourceIp = "123.123.123.123", userAgent = "curl/7.54.0" },
          requestId = "1234567890",
          requestTime = date(1662436514):fmt("%d/%b/%Y:%H:%M:%S %z"),
          requestTimeEpoch = 1662436514 * 1000,
          resourcePath = "/plain/strip/more",
        }
      }, out)
  end)


  do
    local td = {
      {
        description = "none",
        ct = nil,
        body_in = "text",
        body_out = ngx.encode_base64("text"),
        base64 = true,
      }, {
        description = "application/json",
        ct = "application/json",
        body_in = [[{ "text": "some text" }]],
        body_out = ngx.encode_base64([[{ "text": "some text" }]]),
        base64 = true,
      }, {
        description = "unknown",
        ct = "some-unknown-type-description",
        body_in = "text",
        body_out = ngx.encode_base64("text"),
        base64 = true,
      },
    }

    for _, tdata in ipairs(td) do

      it("serializes a request with body type: " .. tdata.description, function()
        mock_request = {
          http_version = "1.0",
          start_time = 1662436514,
          body = tdata.body_in,
          headers = {
            ["Content-Type"] = tdata.ct,
            ["user-agent"] = "curl/7.54.0",
          },
          query = {},
          var = {
            request_method = "GET",
            upstream_uri = "/plain/strip/more",
            http_content_type = tdata.ct,
            kong_request_id = "1234567890",
            host = "def.myhost.test",
            remote_addr = "123.123.123.123"
          },
          ctx = {
            router_matches = {
              uri = "/plain/strip"
            },
          },
        }

        reload_module()

        local out = aws_serialize()

        assert.same({
          body = tdata.body_out,
          headers = {
            ["Content-Type"] = tdata.ct,
            ["user-agent"] = "curl/7.54.0",
          },
          multiValueHeaders = {
            ["Content-Type"] = tdata.ct and { tdata.ct } or nil,
            ["user-agent"] = { "curl/7.54.0" },
          },
          httpMethod = "GET",
          queryStringParameters = {},
          multiValueQueryStringParameters = {},
          pathParameters = {},
          resource = "/plain/strip",
          path = "/plain/strip/more",
          isBase64Encoded = tdata.base64,
          requestContext = {
            path = "/plain/strip/more",
            protocol = "HTTP/1.0",
            httpMethod = "GET",
            domainName = "def.myhost.test",
            domainPrefix = "def",
            identity = { sourceIp = "123.123.123.123", userAgent = "curl/7.54.0" },
            requestId = "1234567890",
            requestTime = date(1662436514):fmt("%d/%b/%Y:%H:%M:%S %z"),
            requestTimeEpoch = 1662436514 * 1000,
            resourcePath = "/plain/strip/more",
          }
        }, out)
      end)
    end
  end

end)
