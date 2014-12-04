-- Copyright (C) Mashape, Inc.

local utils = require "apenode.core.utils"

app:get("/applications/", function(self)
  return utils.success(dao.application.get_all())
end)