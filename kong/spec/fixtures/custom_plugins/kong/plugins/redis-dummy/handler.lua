local kong = kong

local RedisDummy = {
  PRIORITY = 1000,
  VERSION = "0.1.0",
}

function RedisDummy:access(conf)
    kong.log("access phase")
end

return RedisDummy
