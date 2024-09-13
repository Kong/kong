local CONSTANTS = require("spec.internal.constants")
local conf_loader = require("kong.conf_loader")


local conf = assert(conf_loader(CONSTANTS.TEST_CONF_PATH))


return conf
