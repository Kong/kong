------------------------------------------------------------------
-- Collection of utilities to help testing Kong features and plugins.
--
-- @copyright Copyright 2016-2022 Kong Inc. All rights reserved.
-- @license [Apache 2.0](https://opensource.org/licenses/Apache-2.0)
-- @module spec.helpers


local ffi = require("ffi")


ffi.cdef [[
  int setenv(const char *name, const char *value, int overwrite);
  int unsetenv(const char *name);
]]


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


return {
  setenv = setenv,
  unsetenv = unsetenv,
}
