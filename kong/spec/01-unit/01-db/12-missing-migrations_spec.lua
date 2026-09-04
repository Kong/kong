local pl_dir  = require("pl.dir")
local pl_path = require("pl.path")
local pl_tblx = require("pl.tablex")


local MIGRATIONS = {
  {
    dir = "kong/db/migrations/core",
    index = "kong/db/migrations/core/init.lua",
    skip = {},
  },
}
local PLUGIN_DIRS = {
  "kong/plugins",
}


--[[
  This function will fail for the following cases:
  1. An migration file is exists but not listed in the `init.lua` file.
  2. An migration file is marked as skipped but still listed in the `init.lua` file.
--]]
local function assert_no_missing_migrations(migrations)
  for _, migration in ipairs(migrations) do
    --[[
      {
        "010_210_to_211" = true,
        ...
      }
    --]]
    local indexed_migration = pl_tblx.makeset(loadfile(migration.index)())
    local files = pl_dir.getfiles(migration.dir)
    for _, file in ipairs(files) do
      if file == migration.index then
        goto continue
      end

      -- @file: kong/db/migrations/core/010_210_to_211.lua
      -- @basename: 010_210_to_211.lua
      local basename = pl_path.basename(file)

      if basename:sub(-4) ~= ".lua" then
        -- skip non-lua files
        goto continue
      end

      -- strip the extension
      -- @migration_name: 010_210_to_211
      local migration_name = basename:sub(1, -5)

      if migration.skip[file] then
        assert.Falsy(indexed_migration[migration_name], "do not skip an already indexed file: " .. file)
        goto continue
      end

      assert.True(indexed_migration[migration_name], "missing entry for " .. file .. " in " .. migration.index)

      ::continue::
    end
  end
end


describe("Checking missing entry for migrations", function()
  -- same like `@MIGRATIONS`, but for plugins
  local plugin_migrations = {}

  lazy_setup(function()
    local migrations = {
      --[[
        [plugin_name] = {
          dir = <plugin_dir>/migrations,
          index = <plugin_dir>/migrations/init.lua,
          skip = {
            <plugin_dir>/migrations/_001_280_to_300.lua = true,
          },
        },
        ...
      --]]
    }

    for _, plugins_dir in ipairs(PLUGIN_DIRS) do
      local plugins = pl_dir.getdirectories(plugins_dir)
      for _, plugin_dir in ipairs(plugins) do
        -- is this plugin has `migrations/` directory?
        -- and is this plugin has `migrations/init.lua` file?
        if pl_path.exists(pl_path.join(plugin_dir, "migrations")) and
            pl_path.exists(pl_path.join(plugin_dir, "migrations", "init.lua"))
        then
          local plugin_name = pl_path.basename(plugin_dir)
          plugin_migrations[plugin_name] = {
            dir = pl_path.join(plugin_dir, "migrations"),
            index = pl_path.join(plugin_dir, "migrations", "init.lua"),
            skip = {},
          }
        end
      end
    end

    plugin_migrations["pre-function"].skip["kong/plugins/pre-function/migrations/_001_280_to_300.lua"] = true

    plugin_migrations = pl_tblx.values(migrations)
  end)

  it("core migrations", function()
    assert_no_missing_migrations(MIGRATIONS)
  end)

  it("plugin migrations", function()
    assert_no_missing_migrations(plugin_migrations)
  end)
end)
