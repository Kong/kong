local kong = kong

local TranslateBackwardsOlderPlugin = {
  PRIORITY = 1000,
  VERSION = "0.1.0",
}

function TranslateBackwardsOlderPlugin:access(conf)
    kong.log("access phase")
end

return TranslateBackwardsOlderPlugin
