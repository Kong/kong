local constants = require "kong.constants"
local lpath = require "luarocks.path"

local Luarocks = {}

--
-- Luarocks
--
function Luarocks.get_kong_infos()
  return { name = constants.NAME, version = constants.ROCK_VERSION }
end

function Luarocks.get_dir()
  local cfg = require "luarocks.cfg"
  local search = require "luarocks.search"
  local infos = Luarocks.get_kong_infos()

  local tree_map = {}
  local results = {}

  for _, tree in ipairs(cfg.rocks_trees) do
    local rocks_dir = lpath.rocks_dir(tree)
    tree_map[rocks_dir] = tree
    search.manifest_search(results, rocks_dir, search.make_query(infos.name:lower(), infos.version))
  end

  local version
  for k, _ in pairs(results.kong) do
    version = k
  end

  return tree_map[results.kong[version][1].repo]
end

function Luarocks.get_config_dir()
  local repo = Luarocks.get_dir()
  local infos = Luarocks.get_kong_infos()
  return lpath.conf_dir(infos.name:lower(), infos.version, repo)
end

function Luarocks.get_install_dir()
  local repo = Luarocks.get_dir()
  local infos = Luarocks.get_kong_infos()
  return lpath.install_dir(infos.name:lower(), infos.version, repo)
end

return Luarocks