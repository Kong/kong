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
  _VERSION_TABLE = version,

  -- third-party dependencies' required version, as they would be specified
  -- to lua-version's `set()`.
  _DEPENDENCIES = {
    nginx_from = "1.9.15.1",
    nginx_to = "1.9.15.1",
    --resty_from = "", -- not version dependent for now
    --resty_to = ""
    serf_from  = "0.7.0",
    serf_to  = "0.7.0",
    --dnsmasq_from = "" -- not version dependent for now
    --dnsmasq_to = ""
  }
}
