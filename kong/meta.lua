local version = setmetatable({
  major = 1,
  minor = 1,
  patch = 2,
  --suffix = "",
}, {
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
  -- third-party dependencies' required version, as they would be specified
  -- to lua-version's `set()` in the form {from, to}
  _DEPENDENCIES = {
    nginx = {"1.13.6.2"},
  }
}
