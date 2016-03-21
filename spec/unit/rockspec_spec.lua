local stringy = require "stringy"
local IO = require "kong.tools.io"
local fs = require "luarocks.fs"

describe("Rockspec", function()
  local rockspec_path, files

  setup(function()
    for _, filename in ipairs(fs.list_dir(".")) do
      if stringy.endswith(filename, "rockspec") then
        rockspec_path = filename
        break
      end
    end
    if not rockspec_path then
      error("can't find rockspec")
    end

    loadfile(rockspec_path)()

    local res = IO.os_execute("find . -type f -name *.lua", true)
    if not res or stringy.strip(res) == "" then
      error("Error executing the command")
    end

    files = stringy.split(res, "\n")
  end)

  describe("modules", function()
    for _, v in ipairs(files) do
      it("should include "..v, function()
        local path = stringy.strip(v)
        if path ~= "" and stringy.startswith(path, "./kong") then
          path = string.sub(path, 3)

          local found = false
          for mod_name, mod_path in pairs(build.modules) do
            if mod_path == path then
              found = true
              break
            end
          end

          assert.True(found)
        end
      end)
    end

    for mod_name, mod_path in pairs(build.modules) do
      if mod_name ~= "kong" and mod_name ~= "resty_http" and
         mod_name ~= "classic" and mod_name ~= "lapp" then
        it(mod_path.." has correct name", function()
          mod_path = mod_path:gsub("%.lua", ""):gsub("/", '.')
          assert.equal(mod_name, mod_path)
        end)
      end
    end
  end)
end)
