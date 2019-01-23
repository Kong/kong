local pl_utils = require "pl.utils"
local pl_path = require "pl.path"
local pl_dir = require "pl.dir"
local meta = require "kong.meta"

describe("rockspec/meta", function()
  local rock, lua_srcs = {}
  local rock_filename

  lazy_setup(function()
    lua_srcs = pl_dir.getallfiles("./kong", "*.lua")
    assert.True(#lua_srcs > 0)

    local res = pl_dir.getfiles(".", "*.rockspec")
    assert(#res == 1, "more than 1 rockspec file")

    rock_filename = res[1]

    local f = assert(loadfile(res[1]))
    setfenv(f, rock)

    f()
  end)

  describe("meta", function()
    it("has a _NAME field", function()
      assert.is_string(meta._NAME)
    end)

    it("has a _VERSION field", function()
      assert.is_string(meta._VERSION)
      assert.matches("%d+%.%d+%.%d+", meta._VERSION)
    end)

    it("has a _VERSION_TABLE field", function()
      assert.is_table(meta._VERSION_TABLE)
      assert.is_number(meta._VERSION_TABLE.major)
      assert.is_number(meta._VERSION_TABLE.minor)
      assert.is_number(meta._VERSION_TABLE.patch)
      -- suffix optional
    end)

    it("has a _SERVER_TOKENS field", function()
      assert.is_string(meta._SERVER_TOKENS)
    end)

    it("has a _SERVER_TOKENS field that equals to _NAME/_VERSION", function()
      assert.equal(meta._NAME .. "/" .. meta._VERSION, meta._SERVER_TOKENS)
    end)

    it("has a _DEPENDENCIES field", function()
      assert.is_table(meta._DEPENDENCIES)
      assert.is_table(meta._DEPENDENCIES.nginx)
    end)
  end)

  it("has same version as meta", function()
    assert.matches(meta._VERSION, rock.version:match("(.-)%-.*$"))
  end)

  it("has same name as meta", function()
    assert.equal(meta._NAME, rock.package)
  end)

  it("has correct version in filename", function()
    local pattern = meta._VERSION:gsub("%.", "%%."):gsub("-", "%%-")
    assert.matches(pattern, rock_filename)
  end)

  describe("modules", function()
    it("are all included in rockspec", function()
      for _, src in ipairs(lua_srcs) do
        local rel_src = src:sub(3) -- strip './'
        local found
        for mod_name, mod_path in pairs(rock.build.modules) do
          if mod_path == rel_src then
            found = true
            break
          end
        end
        assert(found, "could not find module entry for Lua file: " .. src)
      end
    end)

    it("all modules named as their path", function()
      for mod_name, mod_path in pairs(rock.build.modules) do
        if mod_name ~= "kong" then
          mod_path = mod_path:gsub("%.lua", ""):gsub("/", '.'):gsub("%.init", "")
          assert(mod_name == mod_path,
                 mod_path .. " has different name (" .. mod_name .. ")")
        end
      end
    end)

    it("all rockspec files do exist", function()
      for mod_name, mod_path in pairs(rock.build.modules) do
        assert(pl_path.exists(mod_path),
               mod_path .. " does not exist (" .. mod_name .. ")")
      end
    end)
  end)

  describe("requires", function()
    it("requires in the codebase are defined modules in the rockspec", function()
      for _, src in ipairs(lua_srcs) do
        local str = pl_utils.readfile(src)

        for _, mod in string.gmatch(str, "require%s*([\"'])(kong%..-)%1") do
          if not rock.build.modules[mod] then
            assert(rock.build.modules[mod] ~= nil,
                   "Invalid module require: \n"                      ..
                   "requiring module '" .. mod .. "' in Lua source " ..
                   "'" .. src .. "' that is not declared in "        ..
                   rock_filename)
          end
        end
      end
    end)
  end)
end)
