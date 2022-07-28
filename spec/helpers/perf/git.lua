local perf
local logger = require("spec.helpers.perf.logger")
local utils = require("spec.helpers.perf.utils")

local my_logger = logger.new_logger("[git]")

local git_temp_repo = "/tmp/perf-temp-repo"

local function is_git_repo()
  -- reload the perf module, for circular dependency issue
  perf = require("spec.helpers.perf")

  local _, err = perf.execute("git rev-parse HEAD")
  return err == nil
end

-- is this test based on git versions: e.g. have we git checkout versions?
local function is_git_based()
  return package.path:find(git_temp_repo)
end

local function git_checkout(version)
  -- reload the perf module, for circular dependency issue
  perf = require("spec.helpers.perf")

  local _, err = perf.execute("which git")
  if err then
    error("git binary not found")
  end

  if not is_git_repo() then
    error("not in a git repo")
  end

  for _, cmd in ipairs({
    "rm -rf " .. git_temp_repo,
    "git clone . " .. git_temp_repo,
    "cp -r .git/refs/ " .. git_temp_repo .. "/.git/.",
    -- version is sometimes a hash so we can't always use -b
    "cd " .. git_temp_repo .. " && git checkout " ..version
  }) do
    local _, err = perf.execute(cmd, { logger = my_logger.log_exec })
    if err then
      error("error preparing temporary repo: " .. err)
    end
  end

  utils.add_lua_package_paths(git_temp_repo)

  return git_temp_repo
end

local function git_restore()
  return utils.restore_lua_package_paths()
end

local version_map_table = {
  -- temporary hack, we usually bump version when released, but it's
  -- true for master currently
  ["3.0.0"] = "2.8.1",
}

local function get_kong_version(raw)
  -- unload the module if it's previously loaded
  package.loaded["kong.meta"] = nil

  local ok, meta, _ = pcall(require, "kong.meta")
  local v = meta._VERSION
  if not raw and version_map_table[v] then
    return version_map_table[v]
  end
  if ok then
    return v
  end
  error("can't read Kong version from kong.meta: " .. (meta or "nil"))
end


return {
  is_git_repo = is_git_repo,
  is_git_based = is_git_based,
  git_checkout = git_checkout,
  git_restore = git_restore,
  get_kong_version = get_kong_version,
}
