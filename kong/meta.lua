local version = setmetatable({
  major = 0,
  minor = 9,
  patch = 9,
  pre_release = nil
}, {
  __tostring = function(t)
    return string.format("%d.%d.%d%s", t.major, t.minor, t.patch,
                         t.pre_release and t.pre_release or "")
  end
})

return {
  _NAME = "kong",
  _VERSION = tostring(version),
  _VERSION_TABLE = version,

  -- third-party dependencies' required version, as they would be specified
  -- to lua-version's `set()` in the form {from, to}
  _DEPENDENCIES = {
    nginx = {"1.11.2.1", "1.11.2.2"},
    serf = {"0.7.0", "0.8.0"},
    --resty = {}, -- not version dependent for now
  }
}
