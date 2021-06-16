local deepcopy = require "pl.tablex".deepcopy

describe("[AWS Lambda] aws-gateway input", function()

  local mock_request
  local old_ngx
  local aws_serialize

  setup(function()
    old_ngx = ngx
    local body_data
    _G.ngx = setmetatable({
      req = {
        get_headers = function() return deepcopy(mock_request.headers) end,
        get_uri_args = function() return deepcopy(mock_request.query) end,
        read_body = function() body_data = mock_request.body end,
        get_body_data = function() return body_data end,
      },
      log = function() end,
      encode_base64 = old_ngx.encode_base64
    }, {
      -- look up any unknown key in the mock request, eg. .var and .ctx tables
      __index = function(self, key)
        return mock_request and mock_request[key]
      end,
    })


    -- make sure to reload the module
    package.loaded["kong.plugins.aws-lambda.aws-serializer"] = nil
    aws_serialize = require "kong.plugins.aws-lambda.aws-serializer"
  end)

  teardown(function()
    -- make sure to drop the mocks
    package.loaded["kong.plugins.aws-lambda.aws-serializer"] = nil
    ngx = old_ngx         -- luacheck: ignore
  end)



  it("serializes a request regex", function()
    mock_request = {
      headers = {
        ["single-header"] = "hello world",
        ["multi-header"] = { "first", "second" },
      },
      query = {
        ["single-query"] = "hello world",
        ["multi-query"] = { "first", "second" },
        boolean = true,
      },
      body = "text",
      var = {
        request_method = "GET",
        request_uri = "/123/strip/more?boolean=;multi-query=first;single-query=hello%20world;multi-query=second"
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
        },
        multiValueHeaders = {
          ["multi-header"] = { "first", "second" },
          ["single-header"] = { "hello world" },
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
      }, out)
  end)

  it("serializes a request no-regex", function()
    mock_request = {
      headers = {
        ["single-header"] = "hello world",
        ["multi-header"] = { "first", "second" },
      },
      query = {
        ["single-query"] = "hello world",
        ["multi-query"] = { "first", "second" },
        boolean = true,
      },
      body = "text",
      var = {
        request_method = "GET",
        request_uri = "/plain/strip/more?boolean=;multi-query=first;single-query=hello%20world;multi-query=second"
      },
      ctx = {
        router_matches = {
          uri = "/plain/strip"
        },
      },
    }

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
        },
        multiValueHeaders = {
          ["multi-header"] = { "first", "second" },
          ["single-header"] = { "hello world" },
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
          body = tdata.body_in,
          headers = {
            ["Content-Type"] = tdata.ct,
          },
          query = {},
          var = {
            request_method = "GET",
            request_uri = "/plain/strip/more",
            http_content_type = tdata.ct,
          },
          ctx = {
            router_matches = {
              uri = "/plain/strip"
            },
          },
        }

        local out = aws_serialize()

        assert.same({
          body = tdata.body_out,
          headers = {
            ["Content-Type"] = tdata.ct,
          },
          multiValueHeaders = {
            ["Content-Type"] = tdata.ct and { tdata.ct } or nil,
          },
          httpMethod = "GET",
          queryStringParameters = {},
          multiValueQueryStringParameters = {},
          pathParameters = {},
          resource = "/plain/strip",
          path = "/plain/strip/more",
          isBase64Encoded = tdata.base64,
        }, out)
      end)
    end
  end

end)
