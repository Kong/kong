local utils = require "kong.tools.utils"
local cjson = require "cjson"

local kProxyURL = "http://localhost:8000/"
local kPostURL = kProxyURL.."/post"
local kGetURL = kProxyURL.."/get"

local KONG_BIN = "../../bin/kong"
local DB_BIN = "../../scripts/db.lua"

local function start_server()
  os.execute(KONG_BIN.." start")
end

local function stop_server()
  os.execute(KONG_BIN.." stop")
end

local function drop_db()
  os.execute(KONG_BIN.." stop")
end

local function replace_yaml_property(name, value)

end

describe("Server #server", function()

  describe("Plugins Check", function()

    it("should work when no plugins are enabled and the DB is empty", function()

    end)

  end)

end)
