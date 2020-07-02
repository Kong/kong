local re_match   = ngx.re.match
local re_find    = ngx.re.find
local add_header = require("ngx.resp").add_header

local function get_headers(headers)
  _G.ngx.resp.get_headers = function()
    return headers
  end

  _G.ngx.header = headers

  return headers
end

describe("Plugin: response-transformer-advanced", function()
  local header_transformer

  setup(function()
    _G.ngx = {
      headers_sent = false,
      config = {
        subsystem = { "http" }
      },
      resp = {
        add_header = add_header
      },
      re = {
        match = re_match,
        find  = re_find
      }
    }
    _G.kong = {
      response = require "kong.pdk.response".new(),
      ctx = {
        core = {
          phase = 0x00000200,
        }
      }
    }

    -- mock since FFI based ngx.resp.add_header won't work in this setup
    _G.kong.response.add_header = function(name, value)
      local new_value = _G.kong.response.get_headers()[name]
      if type(new_value) ~= "table" then
        new_value = { new_value }
      end

      table.insert(new_value, value)

      ngx.header[name] = new_value
    end

    header_transformer = require "kong.plugins.response-transformer-advanced.header_transformer"
  end)

  describe("execute_headers()", function()
    local default_conf = {
      remove = {
        json = {},
        headers = {},
        if_status = {}
      },
      rename = {
        headers = {},
        if_status = {}
      },
      replace = {
        body = {},
        json = {},
        headers = {},
        if_status = {}
      },
      add = {
        json = {},
        headers = {},
        if_status = {}
      },
      append = {
        json = {},
        headers = {},
        if_status = {}
      },
      transform = {
        functions = {},
        if_status = {}
      }
    }

    local function get_assign(default, table)
      return setmetatable(table, {
        __index = function (t, k)
          if rawget(t, k) ~= nil then return rawget(t, k) end
          return default[k]
        end
      })
    end

    describe("remove", function()
      local conf_skip = get_assign(default_conf, {
        remove    = {
          headers = {
            "h1",
            "h2",
            "h3:v1",
            "h4:v1",
            "h4:v2",
            "h5:v1",
            "h6:v1",
            "h7:v1",
            "h8:v1",
            "h9:v1",
            "h10:v1",
            "h10:v2",
            "h11:v1",
            "h12:v1",
            "h13:v1",
            "h14:/JSESSIONID=.*/",
            "h15://status/$/",
            "h16:/^/begin//",
            "h17:/JSESSIONID=.*/",
            "h18://status/$/",
            "h19:/^/begin//",
            "h20:v22",
            "h21:/v2^/",
            "h22:v2",
            "h23:/v2/",
            "Set-Cookie:/JSESSIONID=.*/",
            "h24:v1",
            "h25:/v1/"
          },
            if_status = {"201-300", "500"}
        },
        add       = {
          json    = {"p1:v1"},
          headers = {}
        }
      })

      it("skips removing headers if response code doesn't match", function()
        local headers = get_headers({ h1 = "value1", h2 = { "value2a", "value2b" } })
        local headers_copy = { h1 = "value1", h2 = { "value2a", "value2b" } }
        header_transformer.transform_headers(conf_skip, headers, 200)
        assert.same(headers, headers_copy)
      end)

      it("removes headers if response code is in given range #a", function()
        local headers = get_headers({ h1 = "value1", h2 = { "value2a", "value2b" } })
        local headers_copy = { h1 = "value1", h2 = { "value2a", "value2b" } }
        header_transformer.transform_headers(conf_skip, headers, 201)
        assert.is_not.same(headers, headers_copy)
      end)

      it("specific header value", function()
        local headers = get_headers({
          h1 = {"v1", "v2", "v3"},
          h2 = {"v2"},
          h3 = {"v1"},
          h4 = {"v1", "v2", "v3"},
          h5 = {"v1", "v2"},
          h6 = {"v2"},
          h7 = "v1",
          h8 = "v2",
          h9 = "v1,v2",
          h10 = "v1,v2,v3",
          h11 = "v1, v2, v3",
          h12 = "v1;v2;v3",
          h13 = "v1; v2; v3",
          h14 = "JSESSIONID=1876832,path=/,COOKIE2",
          h15 = "/match/status/,/status/no-match/",
          h16 = "/begin/match/,/no-match/begin/",
          h17 = {"JSESSIONID=1876832", "path=/", "COOKIE2"},
          h18 = {"/match/status/","/status/no-match/"},
          h19 = {"/begin/match/","/no-match/begin/"},
          h20 = "v2",
          h21 = "v22",
          h22 = "v22",
          h23 = "v22",
          ["Set-Cookie"] = "JSESSIONID=12345,path=/",
          h24 = "v1,v2,v3",
          h25 = "v1;v2;v3",
        })

        header_transformer.transform_headers(conf_skip, headers, 201)

        assert.same({
          h4 = {"v3"},
          h5 = {"v2"},
          h6 = {"v2"},
          h8 = "v2",
          h9 = "v2",
          h10 = "v3",
          h11 = " v2, v3",
          h12 = "v1;v2;v3",
          h13 = "v1; v2; v3",
          h14 = "path=/,COOKIE2",
          h15 = "/status/no-match/",
          h16 = "/no-match/begin/",
          h17 = {"path=/", "COOKIE2"},
          h18 = {"/status/no-match/"},
          h19 = {"/no-match/begin/"},
          h20 = "v2",
          h21 = "v22",
          h22 = "v22",
          ["Set-Cookie"] = "path=/",
          h24 = "v2,v3",
        }, headers)
      end)
    end)

    describe("replace", function()
      local conf_skip = get_assign(default_conf,{
        replace   = {
          headers = {"h1:v1", "h2:value:2"},  -- payload with colon to verify parsing
          if_status = {"201-300", "500"}
        },
        add       = {
          json    = {"p1:v1"},
          headers = {}
        }
      })

      it("is skipped if response code doesn't match", function()
        local headers = get_headers({ h1 = "value1", h2 = { "value2a", "value2b" } })
        local headers_copy = { h1 = "value1", h2 = { "value2a", "value2b" } }
        header_transformer.transform_headers(conf_skip, headers, 200)
        assert.same(headers, headers_copy)
      end)

      it("is not skipped if response code is in range", function()
        local headers = get_headers({ h1 = "value1", h2 = { "value2a", "value2b" } })
        local headers_copy = { h1 = "value1", h2 = { "value2a", "value2b" } }
        header_transformer.transform_headers(conf_skip, headers, 205)
        assert.is_not.same(headers, headers_copy)
      end)
    end)

    describe("rename", function ()
      local conf = get_assign(default_conf, {
        rename = {
          headers = {"old1:new1", "old2:new2", "set_name:Set-Name"},
          if_status = { "201-300", "500 "}
        }
      })

      local function shallow_cpy(t)
        local t2 = {}
        for k,v in pairs(t) do
          t2[k] = v
        end
        return t2
      end

      it("is skipped if response code doesn't match", function ()
        local headers = get_headers({ old1 = 42, set_name = "x was here" })
        local headers_cpy = shallow_cpy(headers)
        header_transformer.transform_headers(conf, headers, 401)
        assert.same(headers, headers_cpy)
      end)

      it("renames header if response code is in range", function ()
        local headers = get_headers({ old1 = "42", set_name = "x was here" })
        header_transformer.transform_headers(conf, headers, 201)
        assert.same(headers, {
          new1 = "42",
          ["Set-Name"] = "x was here"
        })
      end)
    end)

    describe("add", function()
      local conf_skip = get_assign(default_conf, {
        add       = {
          json    = {"p1:v1"},
          headers = {"h2:v2"},
          if_status = {"201-300", "500"}
        }
      })

      it("is skipped if response code doesn't match", function()
        local headers = get_headers({ h1 = "v1" })
        local headers_copy = {h1 = "v1"}
        header_transformer.transform_headers(conf_skip, headers, 200)
        assert.same(headers, headers_copy)
      end)

      it("is not skipped if response code is in range", function()
        local headers = get_headers({ h1 = "v1" })
        local headers_copy = {h1 = "v1"}
        header_transformer.transform_headers(conf_skip, headers, 201)
        assert.is_not.same(headers, headers_copy)
      end)
    end)

    describe("append", function()
      local conf_skip = get_assign(default_conf, {
        add       = {
          json    = {"p1:v1"},
          headers = {}
        },
        append    = {
          headers = {"h1:v2"},
          if_status = {"201-300", "500"}
        }
      })

      it("is skipped if response code doesn't match", function()
        local headers = get_headers({})
        header_transformer.transform_headers(conf_skip, headers, 200)
        assert.same({}, headers)
      end)
      it("is not skipped if response code is in range", function()
        local headers = get_headers({})
        header_transformer.transform_headers(conf_skip, headers, 205)
        assert.is_not.same({}, headers)
      end)
    end)

    describe("performing remove, replace, add, append together", function()
      local conf_skip = get_assign(default_conf, {
        remove    = {
          headers = {"h1:v1"},
          if_status = {500}
        },
        replace   = {
          headers = {"h2:v3"},
          if_status = {500}
        },
        add       = {
          json    = {"p1:v1"},
          headers = {"h3:v3"},
          if_status = {500}
        },
        append    = {
          headers = {"h3:v4"},
          if_status = {500}
        }
      })

      it("transforms all headers is skipped if response code doesn't match", function()
        local headers = get_headers({ h1 = "v1", h2 = "v2" })
        local headers_copy = { h1 = "v1", h2 = "v2" }
        header_transformer.transform_headers(conf_skip, headers, 200)
        assert.same(headers, headers_copy)
      end)
    end)
  end)
end)
