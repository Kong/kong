------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers


local shell = require("resty.shell")
local strip = require("kong.tools.string").strip


local CONSTANTS = require("spec.internal.constants")
local conf = require("spec.internal.conf")


----------------
-- Shell helpers
-- @section Shell-helpers

--- Execute a command.
-- Modified version of `pl.utils.executeex()` so the output can directly be
-- used on an assertion.
-- @function execute
-- @param cmd command string to execute
-- @param returns (optional) boolean: if true, this function will
-- return the same values as Penlight's executeex.
-- @return if `returns` is true, returns four return values
-- (ok, code, stdout, stderr); if `returns` is false,
-- returns either (false, stderr) or (true, stderr, stdout).
local function exec(cmd, returns)
  --100MB for retrieving stdout & stderr
  local ok, stdout, stderr, _, code = shell.run(cmd, nil, 0, 1024*1024*100)
  if returns then
    return ok, code, stdout, stderr
  end
  if not ok then
    stdout = nil -- don't return 3rd value if fail because of busted's `assert`
  end
  return ok, stderr, stdout
end


--- Execute a Kong command.
-- @function kong_exec
-- @param cmd Kong command to execute, eg. `start`, `stop`, etc.
-- @param env (optional) table with kong parameters to set as environment
-- variables, overriding the test config (each key will automatically be
-- prefixed with `KONG_` and be converted to uppercase)
-- @param returns (optional) boolean: if true, this function will
-- return the same values as Penlight's `executeex`.
-- @param env_vars (optional) a string prepended to the command, so
-- that arbitrary environment variables may be passed
-- @return if `returns` is true, returns four return values
-- (ok, code, stdout, stderr); if `returns` is false,
-- returns either (false, stderr) or (true, stderr, stdout).
local function kong_exec(cmd, env, returns, env_vars)
  cmd = cmd or ""
  env = env or {}

  -- Insert the Lua path to the custom-plugin fixtures
  do
    local function cleanup(t)
      if t then
        t = strip(t)
        if t:sub(-1,-1) == ";" then
          t = t:sub(1, -2)
        end
      end
      return t ~= "" and t or nil
    end
    local paths = {}
    table.insert(paths, cleanup(CONSTANTS.CUSTOM_PLUGIN_PATH))
    table.insert(paths, cleanup(CONSTANTS.CUSTOM_VAULT_PATH))
    table.insert(paths, cleanup(env.lua_package_path))
    table.insert(paths, cleanup(conf.lua_package_path))
    env.lua_package_path = table.concat(paths, ";")
    -- note; the nginx config template will add a final ";;", so no need to
    -- include that here
  end

  if not env.plugins then
    env.plugins = "bundled,dummy,cache,rewriter,error-handler-log," ..
                  "error-generator,error-generator-last," ..
                  "short-circuit"
  end

  -- build Kong environment variables
  env_vars = env_vars or ""
  for k, v in pairs(env) do
    env_vars = string.format("%s KONG_%s='%s'", env_vars, k:upper(), v)
  end

  return exec(env_vars .. " " .. CONSTANTS.BIN_PATH .. " " .. cmd, returns)
end


return {
  run = shell.run,

  exec = exec,
  kong_exec = kong_exec,
}
