local version = setmetatable({
  major = 0,
  minor = 7,
  patch = 0,
  --pre_release = "alpha"
}, {
  __tostring = function(t)
    return string.format("%d.%d.%d%s", t.major, t.minor, t.patch,
                         t.pre_release and "-"..t.pre_release or "")
  end
})

return {
  name = "Kong",
  version = version
}
