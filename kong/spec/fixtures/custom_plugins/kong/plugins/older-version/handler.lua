local meta = require "kong.meta"


local version = setmetatable({
  major = 3,
  minor = 9,
  patch = 0,
}, {
  __tostring = function(t)
    return string.format("%d.%d.%d%s", t.major, t.minor, t.patch,
            t.suffix or "")
  end
})


local OlderVersion =  {
  VERSION = "1.0.0",
  PRIORITY = 1000,
}


function OlderVersion:init_worker()
  meta._VERSION = tostring(version)
  meta._VERSION_TABLE = version
  meta._SERVER_TOKENS = "kong/" .. tostring(version)
  meta.version = tostring(version)
  kong.version = meta._VERSION
end


return OlderVersion
