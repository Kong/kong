local Schema = require "kong.db.schema"
local targets = require "kong.db.schema.entities.targets"
local certificates = require "kong.db.schema.entities.certificates"
local upstreams = require "kong.db.schema.entities.upstreams"
local uuid = require "kong.tools.uuid"

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

assert(Schema.new(certificates))
assert(Schema.new(upstreams))
local Targets = assert(Schema.new(targets))

local function validate(b)
  return Targets:validate(Targets:process_auto_fields(b, "insert"))
end


describe("targets", function()
  setup_global_env()
  describe("targets.target", function()
    it("validates", function()
      local upstream = { id = uuid.uuid() }
      local targets = { "valid.name", "valid.name:8080", "12.34.56.78", "1.2.3.4:123" }
      for _, target in ipairs(targets) do
        local ok, err = validate({ target = target, upstream = upstream })
        assert.is_true(ok)
        assert.is_nil(err)
      end

      local ok, err = validate({ target = "\\\\bad\\\\////name////", upstream = upstream })
      assert.falsy(ok)
      assert.same({ target = "Invalid target ('\\\\bad\\\\////name////'); not a valid hostname or ip address"}, err)
    end)
  end)
end)
