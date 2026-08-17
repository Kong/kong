local Schema = require "kong.db.schema"
local snis = require "kong.db.schema.entities.snis"
local certificates = require "kong.db.schema.entities.certificates"
local uuid = require "kong.tools.uuid"

Schema.new(certificates)
local Snis = assert(Schema.new(snis))

local function setup_global_env()
  _G.kong = _G.kong or {}
  _G.kong.log = _G.kong.log or {
    debug = function(msg)
      ngx.log(ngx.DEBUG, msg)
    end,
    error = function(msg)
      ngx.log(ngx.ERR, msg)
    end,
    warn = function (msg)
      ngx.log(ngx.WARN, msg)
    end
  }
end

local function validate(b)
  return Snis:validate(Snis:process_auto_fields(b, "insert"))
end


describe("snis", function()
  local certificate = { id = uuid.uuid() }

  setup_global_env()

  describe("name", function()
    it("accepts a hostname", function()
      local names = { "valid.name", "foo.valid.name", "bar.foo.valid.name" }

      for _, name in ipairs(names) do
        local ok, err = validate({ name = name, certificate = certificate })
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)

    it("accepts a * for default certificate", function()
      local names = { "*" }

      for _, name in ipairs(names) do
        local ok, err = validate({ name = name, certificate = certificate })
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)

    it("accepts wildcards", function()
      local names = { "*.wildcard.com", "wildcard.*", "test.wildcard.*",
                      "foo.test.wildcard.*", "*.test.wildcard.com" }

      for _, name in ipairs(names) do
        local ok, err = validate({ name = name, certificate = certificate })
        assert.is_nil(err)
        assert.is_true(ok)
      end
    end)

    it("rejects wrong wildcard placements", function()
      local names = { "foo.*.com", "foo.*.wildcard.com" }

      for _, name in ipairs(names) do
        local ok, err = validate({ name = name, certificate = certificate })
        assert.is_nil(ok)
        assert.same({ name = "wildcard must be leftmost or rightmost character" }, err)
      end
    end)

    it("rejects multiple wildcards", function()
      local names = { "*.example.*", "*.foo.*.wildcard.com", "*.*.wildcard.*" }

      for _, name in ipairs(names) do
        local ok, err = validate({ name = name, certificate = certificate })
        assert.is_nil(ok)
        assert.same({ name = "only one wildcard must be specified" }, err)
      end
    end)

    it("rejects wildcard with port", function()
      local names = { "*.wildcard.com:8000", "wildcard.*:80",
                      "test.wildcard.*:80", "test.wildcard.com:*" }

      for _, name in ipairs(names) do
        local ok, err = validate({ name = name, certificate = certificate })
        assert.is_nil(ok)
        assert.is_true(err.name == "must not have a port"
                       or err.name == "invalid value: test.wildcard.com:wildcard"
                       or err.name == "wildcard must be leftmost or rightmost character")
      end
    end)

    it("rejects a hostname with a port", function()
      local names = { "valid.name:8000", "foo.valid.name:443" }

      for _, name in ipairs(names) do
        local ok, err = validate({ name = name, certificate = certificate })
        assert.is_nil(ok)
        assert.same({ name = "must not have a port" }, err)
      end
    end)

    it("rejects a hostname with an IP", function()
      local names = { "127.0.0.1", "10.0.0.1", "10.0.0.1:8001", "::1" }

      for _, name in ipairs(names) do
        local ok, err = validate({ name = name, certificate = certificate })
        assert.is_nil(ok)
        assert.same({ name = "must not be an IP" }, err)
      end
    end)

    it("rejects non-hostname values", function()
      local names = { "example^com" }

      for _, name in ipairs(names) do
        local ok, err = validate({ name = name, certificate = certificate })
        assert.is_nil(ok)
        assert.same({ name = "invalid value: " .. name }, err)
      end
    end)
  end)
end)
