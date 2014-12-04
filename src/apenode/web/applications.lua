-- Copyright (C) Mashape, Inc.

local utils = require "apenode.core.utils"
local app_helpers = require "lapis.application"
local validate = require "lapis.validate"
local capture_errors, yield_error = app_helpers.capture_errors, app_helpers.yield_error

app:get("/applications/", function(self)
  return utils.success(dao.applications:get_all())
end)

app:get("/applications/:id", function(self)
  local application = dao.applications:get_by_id(self.params.id)
  if application then
    return utils.success(application)
  else
    return utils.notFound()
  end
end)

app:delete("/applications/:id", function(self)
  local application = dao.applications:delete(self.params.id)
  if application then
    return utils.success(application)
  else
    return utils.notFound()
  end
end)

app:post("/applications/", capture_errors({
  on_error = function(self)
    return utils.show_error(400, self.errors)
  end,
  function(self)
    validate.assert_valid(self.params, {
      { "secret_key", exists = true, min_length = 1, "Invalid secret_key" },
      { "account_id", exists = true, min_length = 1, "Invalid account_id" }
    })

    local application = dao.applications:save({
      account_id = self.params.account_id,
      public_key = self.params.public_key,
      secret_key = self.params.secret_key,
      status = "ACTIVE"
    })

    return utils.success(application)
  end
}))