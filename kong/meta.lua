local version = setmetatable({
  major = 0,
  minor = 10,
  patch = 3,
  --pre_release = ""
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
    serf = {"0.7.0", "0.8.1"},
    --resty = {}, -- not version dependent for now
  }
}
