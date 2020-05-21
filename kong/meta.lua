local version = setmetatable({
  major = 2,
  minor = 0,
  patch = 4,
  -- suffix = ""
}, {
  -- our Makefile during certain releases adjusts this line. Any changes to
  -- the format need to be reflected in both places
  __tostring = function(t)
return "2f3e118"
  end
})

return {
  _NAME = "kong",
  _VERSION = tostring(version),
  _VERSION_TABLE = version,
  _SERVER_TOKENS = "kong/" .. tostring(version),
  -- third-party dependencies' required version, as they would be specified
  -- to lua-version's `set()` in the form {from, to}
  _DEPENDENCIES = {
    nginx = { "1.15.8.1", "1.15.8.3" },
  }
}
