------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers


-- miscellaneous


local ffi = require("ffi")
local pl_path = require("pl.path")
local pkey = require("resty.openssl.pkey")
local nginx_signals = require("kong.cmd.utils.nginx_signals")
local shell = require("spec.internal.shell")


local CONSTANTS = require("spec.internal.constants")


ffi.cdef [[
  int setenv(const char *name, const char *value, int overwrite);
  int unsetenv(const char *name);
]]


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
    assert(shell.kong_exec("config db_export --conf "..CONSTANTS.TEST_CONF_PATH.." "..filename))
  end
  return filename
end


--- Set an environment variable
-- @function setenv
-- @param env (string) name of the environment variable
-- @param value the value to set
-- @return true on success, false otherwise
local function setenv(env, value)
  assert(type(env) == "string", "env must be a string")
  assert(type(value) == "string", "value must be a string")
  return ffi.C.setenv(env, value, 1) == 0
end


--- Unset an environment variable
-- @function unsetenv
-- @param env (string) name of the environment variable
-- @return true on success, false otherwise
local function unsetenv(env)
  assert(type(env) == "string", "env must be a string")
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


--- Generate asymmetric keys
-- @function generate_keys
-- @param fmt format to receive the public and private pair
-- @return `pub, priv` key tuple or `nil + err` on failure
local function generate_keys(fmt)
  fmt = string.upper(fmt) or "JWK"
  local key, err = pkey.new({
    -- only support RSA for now
    type = 'RSA',
    bits = 2048,
    exp = 65537
  })
  assert(key)
  assert(err == nil, err)
  local pub = key:tostring("public", fmt)
  local priv = key:tostring("private", fmt)
  return pub, priv
end


-- Case insensitive lookup function, returns the value and the original key. Or
-- if not found nil and the search key
-- @usage -- sample usage
-- local test = { SoMeKeY = 10 }
-- print(lookup(test, "somekey"))  --> 10, "SoMeKeY"
-- print(lookup(test, "NotFound")) --> nil, "NotFound"
local function lookup(t, k)
  local ok = k
  if type(k) ~= "string" then
    return t[k], k
  else
    k = k:lower()
  end
  for key, value in pairs(t) do
    if tostring(key):lower() == k then
      return value, key
    end
  end
  return nil, ok
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

  generate_keys = generate_keys,

  lookup = lookup,
}
