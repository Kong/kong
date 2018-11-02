local pl_utils = require "pl.utils"


-- test fixtures. we have to load them before requiring the
-- ALF serializer, since it caches those functions at the
-- module chunk level.
return {
  encode_base64 = function(str)
    return string.format("base64_%s", str)
  end,
  req = {
    start_time = function() return 1432844571.623 end,
    get_method = function() return "GET" end,
    http_version = function() return 1.1 end,
    raw_header = function ()
      return "GET /request/path HTTP/1.1\r\n"..
             "Host: example.com\r\n"..
             "Accept: application/json\r\n"..
             "Accept: application/x-www-form-urlencoded\r\n\r\n"
    end,
    get_headers = function()
      return {
        accept = {"application/json", "application/x-www-form-urlencoded"},
        host = "example.com"
      }
    end,
    get_uri_args = function()
      return {
        hello = "world",
        foobar = "baz"
      }
    end,
  },
  resp = {
    get_headers = function()
      return {
        connection = "close",
        ["content-type"] = {"application/json", "application/x-www-form-urlencoded"},
        ["content-length"] = "934"
      }
    end
  },

  -- ALF buffer stubs
  -- TODO: to be removed once we use resty-cli to run our tests.
  now = function()
    return os.time() * 1000  -- adding ngx.time()'s ms resolution
  end,
  log = function(...)
    local t = {...}
    table.remove(t, 1)
    return t
  end,
  sleep = function(t)
    pl_utils.execute("sleep " .. t/1000)
  end,
  timer = {
    at = function() end
  },

  -- lua-resty-http stubs
  socket = {
    tcp = function() end
  },
  re = {},
  config = {
    ngx_lua_version = ""
  }
}
