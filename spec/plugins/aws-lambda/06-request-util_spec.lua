local default_client_body_buffer_size = 1024 * 8

describe("[AWS Lambda] request-util", function()

  local mock_request
  local old_ngx
  local request_util
  local body_data
  local body_data_filepath


  setup(function()
    old_ngx = ngx
    _G.ngx = setmetatable({
      req = {
        read_body = function()
          body_data = mock_request.body

          -- if the request body is greater than the client buffer size, buffer
          -- it to disk and set the filepath
          if #body_data > default_client_body_buffer_size then
            body_data_filepath = os.tmpname()
            local f = io.open(body_data_filepath, "w")
            f:write(body_data)
            f:close()
            body_data = nil
          end
        end,
        get_body_data = function()
          -- will be nil if request was large and required buffering
          return body_data
        end,
        get_body_file = function()
          -- will be nil if request wasn't large enough to buffer
          return body_data_filepath
        end
      },
      log = function() end,
    }, {
      -- look up any unknown key in the mock request, eg. .var and .ctx tables
      __index = function(self, key)
        return mock_request and mock_request[key]
      end,
    })

    -- always reload
    package.loaded["kong.plugins.aws-lambda.request-util"] = nil
    request_util = require "kong.plugins.aws-lambda.request-util"
  end)


  teardown(function()

    body_data = nil

    -- ignore return value, file might not exist
    os.remove(body_data_filepath)

    body_data_filepath = nil

    -- always unload and restore
    package.loaded["kong.plugins.aws-lambda.request-util"] = nil
    ngx = old_ngx         -- luacheck: ignore
  end)


  describe("when skip_large_bodies is true", function()
    local config = {skip_large_bodies = true}

    it("it skips file-buffered body > max buffer size", function()
      mock_request = {
        body = string.rep("x", 1024 * 9 )
      }
      spy.on(ngx.req, "read_body")
      spy.on(ngx.req, "get_body_file")
      local out = request_util.read_request_body(config.skip_large_bodies)
      assert.spy(ngx.req.read_body).was.called(1)
      -- the payload was buffered to disk, but won't be read because we're skipping
      assert.spy(ngx.req.get_body_file).was.called(1)
      assert.is_nil(out)
    end)

    it("it reads body < max buffer size", function()
      mock_request = {
        body = string.rep("x", 1024 * 2 )
      }
      spy.on(ngx.req, "read_body")
      spy.on(ngx.req, "get_body_file")
      local out = request_util.read_request_body(config.skip_large_bodies)
      assert.spy(ngx.req.read_body).was.called(1)
      assert.spy(ngx.req.get_body_file).was.called(0)
      assert.is_not_nil(out)
    end)
  end)

  describe("when skip_large_bodies is false", function()
    local config = {skip_large_bodies = false}

    it("it reads file-buffered body > max buffer size", function()
      mock_request = {
        body = string.rep("x", 1024 * 10 )
      }
      spy.on(ngx.req, "read_body")
      spy.on(ngx.req, "get_body_file")
      local out = request_util.read_request_body(config.skip_large_bodies)
      assert.spy(ngx.req.read_body).was.called(1)
      -- this payload was buffered to disk, and was read
      assert.spy(ngx.req.get_body_file).was.called(1)
      assert.is_not_nil(out)
    end)

    it("it reads body < max buffer size", function()
      mock_request = {
        body = string.rep("x", 1024 * 2 )
      }
      spy.on(ngx.req, "read_body")
      spy.on(ngx.req, "get_body_file")
      local out = request_util.read_request_body(config.skip_large_bodies)
      assert.spy(ngx.req.read_body).was.called(1)
      assert.spy(ngx.req.get_body_file).was.called(0)
      assert.is_not_nil(out)
    end)
  end)
end)
