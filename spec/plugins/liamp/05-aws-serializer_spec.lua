local deepcopy = require("pl.tablex").deepcopy

describe("[AWS Lambda] aws-gateway input", function()

  local mock_request
  local old_ngx
  local aws_serialize

  setup(function()
    old_ngx = ngx
    _G.ngx = setmetatable({
      req = {
        get_headers = function() return deepcopy(mock_request.headers) end,
        get_uri_args = function() return deepcopy(mock_request.query) end,
        get_body_data = function() return mock_request.body end,
      },
      log = function() end,
    }, {
      -- look up any unknown key in the mock request, eg. .var and .ctx tables
      __index = function(self, key)
        return mock_request and mock_request[key]
      end,
    })


    -- make sure to reload the module
    package.loaded["kong.plugins.liamp.aws-serializer"] = nil
    aws_serialize = require("kong.plugins.liamp.aws-serializer")
  end)

  teardown(function()
    -- make sure to drop the mocks
    package.loaded["kong.plugins.liamp.aws-serializer"] = nil
    ngx = old_ngx
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
      body = nil,
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
        isBase64Encoded = false,
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
      body = nil,
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
        isBase64Encoded = false,
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

end)
