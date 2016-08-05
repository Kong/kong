local version = setmetatable({
  major = 0,
  minor = 9,
  patch = 0,
  pre_release = "rc2"
}, {
  __tostring = function(t)
    return string.format("%d.%d.%d%s", t.major, t.minor, t.patch,
                         t.pre_release and t.pre_release or "")
  end
})

return {
  _NAME = "kong",
  _VERSION = tostring(version),
  __VERSION = version
}
