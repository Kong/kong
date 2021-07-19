local perf
local logger = require("spec.helpers.perf.logger")

local my_logger = logger.new_logger("[git]")

local git_stashed, git_head

local function git_checkout(version)
  -- reload the perf module, for circular dependency issue
  perf = require("spec.helpers.perf")

  if not perf.execute("which git") then
    error("git binary not found")
  end

  local res, err
  local hash, _ = perf.execute("git rev-parse HEAD")
  if not hash or not hash:match("[a-f0-f]+") then
    error("Unable to parse HEAD pointer, is this a git repository?")
  end

  -- am i on a named branch/tag?
  local n, _ = perf.execute("git rev-parse --abbrev-ref HEAD")
  if n and n ~= "HEAD" then
    hash = n
  end
  -- anything to save?
  n, err = perf.execute("git status --untracked-files=no --porcelain")
  if not err and (n and #n > 0) then
    my_logger.info("saving your working directory")
    res, err = perf.execute("git stash save kong-perf-test-autosaved")
    if err then
      error("Cannot save your working directory: " .. err .. (res or "nil"))
    end
    git_stashed = true
  end

  my_logger.debug("switching away from ", hash, " to ", version)

  res, err = perf.execute("git checkout " .. version)
  if err then
    error("Cannot switch to " .. version .. ":\n" .. res)
  end
  if not git_head then
    git_head = hash
  end
end

local function git_restore()
  -- reload the perf module, for circular dependency issue
  perf = require("spec.helpers.perf")

  if git_head then
    local res, err = perf.execute("git checkout " .. git_head)
    if err then
      return false, "git checkout: " .. res
    end
    git_head = nil

    if git_stashed then
      local res, err = perf.execute("git stash pop")
      if err then
        return false, "git stash pop: " .. res
      end
      git_stashed = false
    end
  end
end

local function get_kong_version()
  -- unload the module if it's previously loaded
  package.loaded["kong.meta"] = nil

  local ok, meta, _ = pcall(require, "kong.meta")
  if ok then
    return meta._VERSION
  end
  error("can't read Kong version from kong.meta: " .. (meta or "nil"))
end

local function is_git_repo()
  -- reload the perf module, for circular dependency issue
  perf = require("spec.helpers.perf")

  return perf.execute("git status")
end

-- is this test based on git versions: e.g. have we git checkout versions?
local function is_git_based()
  return not not git_head
end


return {
  git_checkout = git_checkout,
  git_restore = git_restore,
  get_kong_version = get_kong_version,
  is_git_repo = is_git_repo,
  is_git_based = is_git_based,
}