-- Copyright (C) Mashape, Inc.

local utils = require "apenode.core.utils"

local _M = {}

function _M.init(app)

  app:get("/applications/", function(self)
    return utils.show_response(200, dao.applications.get_all())
  end)

end

return _M