-- Copyright (C) Mashape, Inc.

local utils = require "apenode.core.utils"
local app_helpers = require "lapis.application"
local capture_errors, yield_error = app_helpers.capture_errors, app_helpers.yield_error

app:get("/apis/", function(self)
  return utils.show_response(200, dao.api.get_all())
end)

app:get("/apis/:id", function(self)
  local api = dao.api.get_by_id(self.params.id)
  if api then
    return utils.show_response(200, dao.api.get_by_id(self.params.id))
  else
    return utils.show_error(404, "Not found")
  end
end)

app:delete("/apis/:id", function(self)
  local api = dao.api.delete(self.params.id)
  if api then
    return utils.show_response(200, dao.api.delete(self.params.id))
  else
    return utils.show_error(404, "Not found")
  end
end)

app:post("/apis/", capture_errors({
  on_error = function(self)
    return utils.show_error(400, self.errors)
  end,
  function(self)
    validate.assert_valid(self.params, {
      { "public_dns", exists = true, min_length = 1, "Invalid public_dns" },
      { "target_url", exists = true, min_length = 1, "Invalid target_url" },
      { "authentication_type", exists = true, one_of = { "query", "header", "basic"}, "Invalid authentication_type" }
    })

    local api = dao.api.save({
      public_dns = self.params.public_dns,
      target_url = self.params.target_url,
      authentication_type = self.params.authentication_type,
    authentication_key_names = "apikey"
    })

    return utils.show_response(200, api)
  end
}))