local uuid = require("kong.tools.utils").uuid


return function()
  return uuid()
end
