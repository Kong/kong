local utils = require "kong.tools.utils"
local pl_utils = require "pl.utils"


-- test fixtures. we have to load them before requiring the
-- ALF serializer, since it caches those functions at the
-- module chunk level.
local _kong = {
  response = {
    get_headers = function()
      return {
        connection = "close",
        ["content-type"] = {"application/json", "application/x-www-form-urlencoded"},
        ["content-length"] = "934"
      }
    end
  },
}

local _ngx = {
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
_G.ngx = _ngx
_G.kong = _kong

-- asserts if an array contains a given table
local function contains(state, args)
  local entry, t = unpack(args)
  for i = 1, #t do
    if pcall(assert.same, entry, t[i]) then
      return true
    end
  end
  return false
end

local say = require "say"
local luassert = require "luassert"
say:set("assertion.contains.positive", "Should contain")
say:set("assertion.contains.negative", "Should not contain")
luassert:register("assertion", "contains", contains,
                  "assertion.contains.positive",
                  "assertion.contains.negative")

local alf_serializer = require "kong.plugins.brain.alf"

-- since our module caches ngx's global functions, this is a
-- hacky utility to reload it, allowing us to send different
-- input sets to the serializer.
local function reload_alf_serializer()
  package.loaded["kong.plugins.brain.alf"] = nil
  alf_serializer = require "kong.plugins.brain.alf"
end

---------------------------
-- Serialization unit tests
---------------------------

describe("ALF serializer", function()
  local _ngx
  before_each(function()
    _ngx = {
      status = 200,
      var    = {
        server_protocol = "HTTP/1.1",
        scheme          = "https",
        host            = "example.com",
        request_uri     = "/request/path",
        request_length  = 32,
        remote_addr     = "127.0.0.1",
      },
      ctx   = {
        KONG_PROXY_LATENCY = 3,
        KONG_WAITING_TIME  = 15,
        KONG_RECEIVE_TIME  = 25,
      },
    }
  end)
  it("sanity", function()
    local alf = alf_serializer.new()
    assert.is_nil(alf.log_bodies)
    assert.equal(0, #alf.entries)

    alf = alf_serializer.new(true)
    assert.True(alf.log_bodies)
  end)

  describe("add_entry()", function()
    it("adds an entry", function()
      local alf = alf_serializer.new(nil, "10.10.10.10")
      local entry = assert(alf:add_entry(_ngx))
      assert.matches("%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ", entry.startedDateTime)
      assert.equal("10.10.10.10", entry.serverIPAddress)
      assert.equal("127.0.0.1", entry.clientIPAddress)
      assert.is_table(entry.request)
      assert.is_table(entry.response)
      assert.is_table(entry.timings)
      assert.is_table(entry._kong)
      assert.is_number(entry.time)
    end)
    it("appends the entry to the 'entries' table", function()
      local alf = alf_serializer.new()
      for i = 1, 10 do
        assert(alf:add_entry(_ngx))
        assert.equal(i, #alf.entries)
      end
    end)
    it("returns the number of entries", function()
      local alf = alf_serializer.new()
      for i = 1, 10 do
        local entry, n = assert(alf:add_entry(_ngx))
        assert.equal(i, n)
        assert.truthy(entry)
      end
    end)

    describe("request", function()
      it("captures info", function()
        local alf = alf_serializer.new()
        local entry = assert(alf:add_entry(_ngx))
        assert.equal("HTTP/1.1", entry.request.httpVersion)
        assert.equal("GET", entry.request.method)
        assert.equal("https://example.com/request/path", entry.request.url)
        assert.is_table(entry.request.headers)
        assert.is_table(entry.request.queryString)
        --assert.is_table(entry.request.postData) -- none by default
        assert.is_number(entry.request.headersSize)
        assert.is_boolean(entry.request.bodyCaptured)
        assert.is_number(entry.request.bodySize)
      end)
      it("captures querystring info", function()
        local alf = alf_serializer.new()
        local entry = assert(alf:add_entry(_ngx))
        assert.contains({name = "hello", value = "world"}, entry.request.queryString)
        assert.contains({name = "foobar", value = "baz"}, entry.request.queryString)
      end)
      it("captures headers info", function()
        local alf = alf_serializer.new()
        local entry = assert(alf:add_entry(_ngx))
        assert.contains({name = "accept", value = "application/json"}, entry.request.headers)
        assert.contains({name = "host", value = "example.com"}, entry.request.headers)
        assert.equal(118, entry.request.headersSize)
      end)
      it("handles headers with multiple values", function()
        local alf = alf_serializer.new()
        local entry = assert(alf:add_entry(_ngx))
        assert.contains({
          name = "accept",
          value = "application/json"
        }, entry.request.headers)
        assert.contains({
          name = "accept",
          value = "application/x-www-form-urlencoded"
        }, entry.request.headers)
        assert.contains({
          name = "host",
          value = "example.com"
        }, entry.request.headers)
      end)
    end)

    describe("response", function()
      it("captures info", function()
        local alf = alf_serializer.new()
        local entry = assert(alf:add_entry(_ngx))
        assert.equal(200, entry.response.status)
        assert.is_string(entry.response.statusText) -- can't get
        assert.is_string(entry.response.httpVersion) -- can't get
        assert.is_table(entry.response.headers)
        --assert.is_table(entry.response.content) -- none by default
        assert.is_number(entry.response.headersSize) -- can't get
        assert.is_boolean(entry.response.bodyCaptured)
        assert.is_number(entry.response.bodySize)
      end)
      it("captures headers info", function()
        local alf = alf_serializer.new()
        local entry = assert(alf:add_entry(_ngx))
        assert.contains({
          name = "connection",
          value = "close"
        }, entry.response.headers)
        assert.contains({
          name = "content-type",
          value = "application/json"
        }, entry.response.headers)
        assert.contains({
          name = "content-length",
          value = "934"
        }, entry.response.headers)
        assert.equal(0, entry.response.headersSize) -- can't get
      end)
      it("handles headers with multiple values", function()
        local alf = alf_serializer.new()
        local entry = assert(alf:add_entry(_ngx))
        assert.contains({
          name = "content-type",
          value = "application/json"
        }, entry.response.headers)
        assert.contains({
          name = "content-type",
          value = "application/x-www-form-urlencoded"
        }, entry.response.headers)
      end)
    end)

    describe("request body", function()
      local get_headers
      setup(function()
        get_headers = _G.ngx.req.get_headers
      end)
      teardown(function()
        _G.ngx.req.get_headers = get_headers
        reload_alf_serializer()
      end)
      it("captures body info if and only if asked for", function()
        local body_str = "hello=world&foo=bar"
        _G.kong.response.get_headers = function()
          return {}
        end
        reload_alf_serializer()

        local alf_with_body = alf_serializer.new(true)
        local alf_without_body = alf_serializer.new(false) -- no bodies

        local entry1 = assert(alf_with_body:add_entry(_ngx, body_str))
        assert.is_table(entry1.request.postData)
        assert.same({
          text = "base64_hello=world&foo=bar",
          encoding = "base64",
          mimeType = "application/octet-stream"
        }, entry1.request.postData)

        local entry2 = assert(alf_without_body:add_entry(_ngx, body_str))
        assert.is_nil(entry2.request.postData)
      end)
      it("captures bodySize from Content-Length if not logging bodies", function()
        _G.ngx.req.get_headers = function()
          return {["content-length"] = "38"}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new() -- log_bodies disabled
        local entry = assert(alf:add_entry(_ngx)) -- no body str
        assert.equal(38, entry.request.bodySize)
      end)
      it("captures bodySize reading the body if logging bodies", function()
        local body_str = "hello=world"

        _G.ngx.req.get_headers = function()
          return {["content-length"] = "3800"}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new(true) -- log_bodies enabled
        local entry = assert(alf:add_entry(_ngx, body_str))
        assert.equal(#body_str, entry.request.bodySize)
      end)
      it("zeroes bodySize if body logging but no body", function()
        _G.ngx.req.get_headers = function()
          return {}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new(true) -- log_bodies enabled
        local entry = assert(alf:add_entry(_ngx))
        assert.equal(0, entry.request.bodySize)
      end)
      it("zeroes bodySize if no body logging or Content-Length", function()
        _G.ngx.req.get_headers = function()
          return {}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new() -- log_bodies disabled
        local entry = assert(alf:add_entry(_ngx)) -- no body str
        assert.equal(0, entry.request.bodySize)
      end)
      it("ignores nil body string (no postData)", function()
        local alf = alf_serializer.new(true)
        local entry = assert(alf:add_entry(_ngx, nil))
        assert.is_nil(entry.request.postData)
      end)
      it("captures postData.mimeType", function()
        local body_str = [[{"hello": "world"}]]

        _G.ngx.req.get_headers = function()
          return {["content-type"] = "application/json"}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new(true)
        local entry = assert(alf:add_entry(_ngx, body_str))
        assert.equal("application/json", entry.request.postData.mimeType)
      end)
      it("bodyCaptured is always set from the given headers", function()
        -- this behavior tries to stay compliant with RFC 2616 by
        -- determining if the request has a body from its headers,
        -- instead of having to read it, which would defeat the purpose
        -- of the 'log_bodies' option flag.
        local alf = alf_serializer.new(true) -- log_bodies enabled
        local entry = assert(alf:add_entry(_ngx)) -- no body str
        assert.False(entry.request.bodyCaptured)

        _G.ngx.req.get_headers = function()
          return {["content-length"] = "38"}
        end
        reload_alf_serializer()
        alf = alf_serializer.new() -- log_bodies disabled
        entry = assert(alf:add_entry(_ngx)) -- no body str
        assert.True(entry.request.bodyCaptured)

        _G.ngx.req.get_headers = function()
          return {["transfer-encoding"] = "chunked"}
        end
        reload_alf_serializer()
        alf = alf_serializer.new(true)
        entry = assert(alf:add_entry(_ngx))
        assert.True(entry.request.bodyCaptured)

        _G.ngx.req.get_headers = function()
          return {["content-type"] = "multipart/byteranges"}
        end
        reload_alf_serializer()
        alf = alf_serializer.new(false)
        entry = assert(alf:add_entry(_ngx))
        assert.True(entry.request.bodyCaptured)

        _G.ngx.req.get_headers = function()
          return {["content-length"] = 0}
        end
        reload_alf_serializer()
        alf = alf_serializer.new(false)
        entry = assert(alf:add_entry(_ngx))
        assert.False(entry.request.bodyCaptured)
      end)
      it("bodyCaptures handles headers with multiple values", function()
        -- it uses the last header value
        _G.ngx.req.get_headers = function()
          return {["content-length"] = {"0", "38"}}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new(true)
        local entry = assert(alf:add_entry(_ngx))
        assert.True(entry.request.bodyCaptured)
      end)
    end)

    describe("response body", function()
      local get_headers
      setup(function()
        get_headers = _G.kong.response.get_headers
      end)
      teardown(function()
        _G.kong.response.get_headers = get_headers
        reload_alf_serializer()
      end)
      it("captures body info if and only if asked for", function()
        local body_str = "message=hello"
        _G.kong.response.get_headers = function()
          return {}
        end
        reload_alf_serializer()

        local alf_with_body = alf_serializer.new(true)
        local alf_without_body = alf_serializer.new(false) -- no bodies

        local entry1 = assert(alf_with_body:add_entry(_ngx, nil, body_str))
        assert.is_table(entry1.response.content)
        assert.same({
          text = "base64_message=hello",
          encoding = "base64",
          mimeType = "application/octet-stream"
        }, entry1.response.content)

        local entry2 = assert(alf_without_body:add_entry(_ngx, body_str))
        assert.is_nil(entry2.response.postData)
      end)
      it("captures bodySize from Content-Length if not logging bodies", function()
        _G.kong.response.get_headers = function()
          return {["content-length"] = "38"}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new() -- log_bodies disabled
        local entry = assert(alf:add_entry(_ngx)) -- no body str
        assert.equal(38, entry.response.bodySize)
      end)
      it("captures bodySize reading the body if logging bodies", function()
        local body_str = "hello=world"

        _G.kong.response.get_headers = function()
          return {["content-length"] = "3800"}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new(true) -- log_bodies enabled
        local entry = assert(alf:add_entry(_ngx, nil, body_str))
        assert.equal(#body_str, entry.response.bodySize)
      end)
      it("zeroes bodySize if body logging but no body", function()
        _G.kong.response.get_headers = function()
          return {}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new(true) -- log_bodies enabled
        local entry = assert(alf:add_entry(_ngx))
        assert.equal(0, entry.response.bodySize)
      end)
      it("zeroes bodySize if no body logging or Content-Length", function()
        _G.kong.response.get_headers = function()
          return {}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new() -- log_bodies disabled
        local entry = assert(alf:add_entry(_ngx)) -- no body str
        assert.equal(0, entry.response.bodySize)
      end)
      it("ignores nil body string (no response.content)", function()
        local alf = alf_serializer.new(true)
        local entry = assert(alf:add_entry(_ngx, nil, nil))
        assert.is_nil(entry.response.content)
      end)
      it("captures content.mimeType", function()
        local body_str = [[{"hello": "world"}]]

        _G.kong.response.get_headers = function()
          return {["content-type"] = "application/json"}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new(true)
        local entry = assert(alf:add_entry(_ngx, nil, body_str))
        assert.equal("application/json", entry.response.content.mimeType)
      end)
      it("bodyCaptured is always set from the given headers", function()
        -- this behavior tries to stay compliant with RFC 2616 by
        -- determining if the request has a body from its headers,
        -- instead of having to read it, which would defeat the purpose
        -- of the 'log_bodies' option flag.
        local alf = alf_serializer.new(true) -- log_bodies enabled
        local entry = assert(alf:add_entry(_ngx)) -- no body str
        assert.False(entry.request.bodyCaptured)

        _G.kong.response.get_headers = function()
          return {["content-length"] = "38"}
        end
        reload_alf_serializer()
        alf = alf_serializer.new("abcd", "test") -- log_bodies disabled
        entry = assert(alf:add_entry(_ngx)) -- no body str
        assert.True(entry.response.bodyCaptured)

        _G.kong.response.get_headers = function()
          return {["transfer-encoding"] = "chunked"}
        end
        reload_alf_serializer()
        alf = alf_serializer.new(true)
        entry = assert(alf:add_entry(_ngx))
        assert.True(entry.response.bodyCaptured)

        _G.kong.response.get_headers = function()
          return {["content-type"] = "multipart/byteranges"}
        end
        reload_alf_serializer()
        alf = alf_serializer.new(false)
        entry = assert(alf:add_entry(_ngx))
        assert.True(entry.response.bodyCaptured)

        _G.kong.response.get_headers = function()
          return {["content-length"] = "0"}
        end
        reload_alf_serializer()
        alf = alf_serializer.new(false)
        entry = assert(alf:add_entry(_ngx))
        assert.False(entry.response.bodyCaptured)
      end)
      it("bodyCaptures handles headers with multiple values", function()
        -- it uses the last header value
        _G.kong.response.get_headers = function()
          return {["content-length"] = {"0", "38"}}
        end
        reload_alf_serializer()
        local alf = alf_serializer.new(true)
        local entry = assert(alf:add_entry(_ngx))
        assert.True(entry.response.bodyCaptured)
      end)
    end)

    describe("timings", function()
      it("computes timings", function()
        local alf = alf_serializer.new()
        local entry = assert(alf:add_entry(_ngx))
        assert.equal(43, entry.time)
        assert.equal(3, entry.timings.send)
        assert.equal(15, entry.timings.wait)
        assert.equal(25, entry.timings.receive)
      end)
      it("handles missing timer", function()
        _ngx.ctx.KONG_WAITING_TIME = nil
        local alf = alf_serializer.new()
        local entry = assert(alf:add_entry(_ngx))
        assert.equal(28, entry.time)
        assert.equal(3, entry.timings.send)
        assert.equal(0, entry.timings.wait)
        assert.equal(25, entry.timings.receive)
      end)
    end)

    describe("kong namespace", function()
      local entry
      local workspaces = {{id = utils.uuid(), name = "default"}}
      local service = {
        id = utils.uuid(),
        host = "example.com",
        port = 80,
        protocol = "http",
      }
      local route = {
        id = utils.uuid(),
        service = { id = service.id },
        hosts = { "example.com" },
      }
      before_each(function()
        _ngx.ctx = _ngx.ctx or {}
        _ngx.ctx.log_request_workspaces = workspaces
        _ngx.ctx.service = service
        _ngx.ctx.route = route
        local alf = alf_serializer.new()
        entry = assert(alf:add_entry(_ngx))
      end)
      it("contains workspaces info", function()
        assert.same(workspaces, entry._kong.workspaces)
      end)
      it("contains route info", function()
        assert.same(route, entry._kong.route)
      end)
      it("contains service info", function()
        assert.same(service, entry._kong.service)
      end)
    end)

    it("bad self", function()
      local entry, err = alf_serializer.add_entry({})
      assert.equal("no entries table", err)
      assert.is_nil(entry)
    end)
    it("missing captured _ngx", function()
      local alf = alf_serializer.new()
      local entry, err = alf_serializer.add_entry(alf)
      assert.equal("arg #1 (_ngx) must be given", err)
      assert.is_nil(entry)
    end)
    it("invalid body string", function()
      local alf = alf_serializer.new()
      local entry, err = alf:add_entry(_ngx, false)
      assert.equal("arg #2 (req_body_str) must be a string", err)
      assert.is_nil(entry)
    end)
    it("invalid response body string", function()
      local alf = alf_serializer.new()
      local entry, err = alf:add_entry(_ngx, nil, false)
      assert.equal("arg #3 (resp_body_str) must be a string", err)
      assert.is_nil(entry)
    end)
    it("assert incompatibilities with ALF 1.1.0", function()
      local alf = alf_serializer.new()
      local entry = assert(alf:add_entry(_ngx))
      assert.equal("", entry.response.statusText) -- can't get
      assert.equal(0, entry.response.headersSize) -- can't get
    end)
  end) -- add_entry()

  describe("serialize()", function()

    local cjson = require "cjson.safe"
    it("returns a JSON encoded ALF object", function()
      local alf = alf_serializer.new()
      assert(alf:add_entry(_ngx))
      assert(alf:add_entry(_ngx))
      assert(alf:add_entry(_ngx))

      local json_encoded_alf = assert(alf:serialize("abcd", "test"))
      assert.is_string(json_encoded_alf)
      local alf_o = assert(cjson.decode(json_encoded_alf))
      assert.is_string(alf_o.version)
      assert.equal(alf_serializer._ALF_VERSION, alf_o.version)
      assert.is_string(alf_o.serviceToken)
      assert.equal("abcd", alf_o.serviceToken)
      assert.is_string(alf_o.environment)
      assert.equal("test", alf_o.environment)
      assert.is_table(alf_o.har)
      assert.is_table(alf_o.har.log)
      assert.is_table(alf_o.har.log.creator)
      assert.is_string(alf_o.har.log.creator.name)
      assert.equal(alf_serializer._ALF_CREATOR, alf_o.har.log.creator.name)
      assert.is_string(alf_o.har.log.creator.version)
      assert.equal(alf_serializer._VERSION, alf_o.har.log.creator.version)
      assert.is_table(alf_o.har.log.entries)
      assert.equal(3, #alf_o.har.log.entries)
    end)
    it("gives empty arrays and not empty objects", function()
      _G.kong.response.get_headers = function()
        return {}
      end
      _G.ngx.req.get_uri_args = function()
        return {}
      end
      reload_alf_serializer()
      local alf = alf_serializer.new()
      assert(alf:add_entry(_ngx))
      local json_encoded_alf = assert(alf:serialize("abcd"))
      assert.matches('"headers":[]', json_encoded_alf, nil, true)
      assert.matches('"queryString":[]', json_encoded_alf, nil, true)
    end)
    it("handles nil environment", function()
      local alf = alf_serializer.new()
      local json_encoded_alf = assert(alf:serialize("abcd"))
      assert.is_string(json_encoded_alf)
      local alf_o = assert(cjson.decode(json_encoded_alf))
      assert.is_nil(alf_o.environment)
    end)
    it("returns an error on invalid token", function()
      local alf = alf_serializer.new()
      local alf_str, err = alf:serialize()
      assert.equal("arg #1 (service_token) must be a string", err)
      assert.is_nil(alf_str)
    end)
    it("returns an error on invalid environment", function()
      local alf = alf_serializer.new()
      local alf_str, err = alf:serialize("abcd", false)
      assert.equal("arg #2 (environment) must be a string", err)
      assert.is_nil(alf_str)
    end)
    it("bad self", function()
      local alf = alf_serializer.new()
      assert(alf:add_entry(_ngx))

      local res, err = alf.serialize({})
      assert.equal("no entries table", err)
      assert.is_nil(res)
    end)
    it("limits ALF sizes to 20MB", function()
      local alf = alf_serializer.new(true)
      local body_12mb = string.rep(".", 21 * 2^20)
      assert(alf:add_entry(_ngx, body_12mb))
      local json_encoded_alf, err = alf:serialize("abcd")
      assert.equal("ALF too large (> 20MB)", err)
      assert.is_nil(json_encoded_alf)
    end)
    it("returns the number of entries in the serialized ALF", function()
      local alf = alf_serializer.new()
      assert(alf:add_entry(_ngx))
      assert(alf:add_entry(_ngx))
      assert(alf:add_entry(_ngx))

      local _, n_entries = assert(alf:serialize("abcd", "test"))
      assert.equal(3, n_entries)
    end)
    it("removes escaped slashes", function()
      local alf = alf_serializer.new()
      assert(alf:add_entry(_ngx))

      local json_encoded_alf = assert(alf:serialize("abcd", "test"))
      assert.matches([["value":"application/json"]], json_encoded_alf, nil, true)
      assert.matches([["httpVersion":"HTTP/1.1"]], json_encoded_alf, nil, true)
      assert.matches([["url":"https://example.com/request/path"]], json_encoded_alf, nil, true)
    end)
  end)

  describe("reset()", function()
    it("empties an ALF", function()
      local alf = alf_serializer.new()
      assert(alf:add_entry(_ngx))
      assert(alf:add_entry(_ngx))
      assert.equal(2, #alf.entries)
      alf:reset()
      assert.equal(0, #alf.entries)
    end)
  end)
end)

