-- miscellaneous


local ffi = require("ffi")
local pl_path = require("pl.path")
local shell = require("resty.shell")
local conf_loader = require("kong.conf_loader")
local nginx_signals = require("kong.cmd.utils.nginx_signals")
local strip = require("kong.tools.string").strip


local CONSTANTS = require("spec.details.constants")


ffi.cdef [[
  int setenv(const char *name, const char *value, int overwrite);
  int unsetenv(const char *name);
]]


local kong_exec   -- forward declaration


local pack = function(...) return { n = select("#", ...), ... } end
local unpack = function(t) return unpack(t, 1, t.n) end


--- Prints all returned parameters.
-- Simple debugging aid, it will pass all received parameters, hence will not
-- influence the flow of the code. See also `fail`.
-- @function intercept
-- @see fail
-- @usage -- modify
-- local a,b = some_func(c,d)
-- -- into
-- local a,b = intercept(some_func(c,d))
local function intercept(...)
  local args = pack(...)
  print(require("pl.pretty").write(args))
  return unpack(args)
end


--- Returns the OpenResty version.
-- Extract the current OpenResty version in use and returns
-- a numerical representation of it.
-- Ex: `1.11.2.2` -> `11122`
-- @function openresty_ver_num
local function openresty_ver_num()
  local nginx_bin = assert(nginx_signals.find_nginx_bin())
  local _, _, stderr = shell.run(string.format("%s -V", nginx_bin), nil, 0)

  local a, b, c, d = string.match(stderr or "", "openresty/(%d+)%.(%d+)%.(%d+)%.(%d+)")
  if not a then
    error("could not execute 'nginx -V': " .. stderr)
  end

  return tonumber(a .. b .. c .. d)
end


--- Unindent a multi-line string for proper indenting in
-- square brackets.
-- @function unindent
-- @usage
-- local u = helpers.unindent
--
-- u[[
--     hello world
--     foo bar
-- ]]
--
-- -- will return: "hello world\nfoo bar"
local function unindent(str, concat_newlines, spaced_newlines)
  str = string.match(str, "(.-%S*)%s*$")
  if not str then
    return ""
  end

  local level  = math.huge
  local prefix = ""
  local len

  str = str:match("^%s") and "\n" .. str or str
  for pref in str:gmatch("\n(%s+)") do
    len = #prefix

    if len < level then
      level  = len
      prefix = pref
    end
  end

  local repl = concat_newlines and "" or "\n"
  repl = spaced_newlines and " " or repl

  return (str:gsub("^\n%s*", ""):gsub("\n" .. prefix, repl):gsub("\n$", ""):gsub("\\r", "\r"))
end


--- Write a yaml file.
-- @function make_yaml_file
-- @param content (string) the yaml string to write to the file, if omitted the
-- current database contents will be written using `kong config db_export`.
-- @param filename (optional) if not provided, a temp name will be created
-- @return filename of the file written
local function make_yaml_file(content, filename)
  local filename = filename or pl_path.tmpname() .. ".yml"
  if content then
    local fd = assert(io.open(filename, "w"))
    assert(fd:write(unindent(content)))
    assert(fd:write("\n")) -- ensure last line ends in newline
    assert(fd:close())
  else
    assert(kong_exec("config db_export --conf "..CONSTANTS.TEST_CONF_PATH.." "..filename))
  end
  return filename
end


--- Set an environment variable
-- @function setenv
-- @param env (string) name of the environment variable
-- @param value the value to set
-- @return true on success, false otherwise
local function setenv(env, value)
  return ffi.C.setenv(env, value, 1) == 0
end


--- Unset an environment variable
-- @function unsetenv
-- @param env (string) name of the environment variable
-- @return true on success, false otherwise
local function unsetenv(env)
  return ffi.C.unsetenv(env) == 0
end


local deep_sort
do
  local function deep_compare(a, b)
    if a == nil then
      a = ""
    end

    if b == nil then
      b = ""
    end

    deep_sort(a)
    deep_sort(b)

    if type(a) ~= type(b) then
      return type(a) < type(b)
    end

    if type(a) == "table" then
      return deep_compare(a[1], b[1])
    end

    -- compare cjson.null or ngx.null
    if type(a) == "userdata" and type(b) == "userdata" then
      return false
    end

    return a < b
  end

  deep_sort = function(t)
    if type(t) == "table" then
      for _, v in pairs(t) do
        deep_sort(v)
      end
      table.sort(t, deep_compare)
    end

    return t
  end
end


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


local conf = assert(conf_loader(CONSTANTS.TEST_CONF_PATH))


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
function kong_exec(cmd, env, returns, env_vars)
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
  pack = pack,
  unpack = unpack,

  intercept = intercept,
  openresty_ver_num = openresty_ver_num(),
  unindent = unindent,
  make_yaml_file = make_yaml_file,
  setenv = setenv,
  unsetenv = unsetenv,
  deep_sort = deep_sort,

  conf = conf,
  exec = exec,
  kong_exec = kong_exec,
}
