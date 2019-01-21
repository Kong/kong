local reports = require "kong.reports"
local utils = require "kong.tools.utils"


local function post_process(data)
  local r_data = utils.deep_copy(data)
  r_data.config = nil
  r_data.e = "r"
  reports.send("api", r_data)
  return data
end


return {
  ["/routes/:routes/plugins"] = {
    POST = function(_, _, _, parent)
      return parent(post_process)
    end,
  },
}
