local version = setmetatable({
  major = 3,
  minor = 1,
  patch = 0,
  --suffix = "-alpha.13"
}, {
  -- our Makefile during certain releases adjusts this line. Any changes to
  -- the format need to be reflected in both places
  __tostring = function(t)
    return string.format("%d.%d.%d%s", t.major, t.minor, t.patch,
                         t.suffix or "")
  end
})

return {
  _NAME = "kong",
  _VERSION = tostring(version),
  _VERSION_TABLE = version,
  _SERVER_TOKENS = "kong/" .. tostring(version),

  -- unified version string for CE and EE
  version = tostring(version),

  -- third-party dependencies' required version, as they would be specified
  -- to lua-version's `set()` in the form {from, to}
  _DEPENDENCIES = {
    nginx = { "1.21.4.1" },
  }
}
