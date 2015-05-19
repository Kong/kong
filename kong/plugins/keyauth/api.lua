local base_controller = require "kong.api.routes.base_controller"

return function(lapis_app, dao_factory)
  local inspect = require "inspect"
  print(inspect(lapis_app))
  lapis_app:get("api/keyauth", "/apis/:name_or_id", function(self)
    if is_valid_uuid(self.params.name_or_id) then
      self.params.id = self.params.name_or_id
    else
      self.params.name = self.params.name_or_id
    end
    self.params.name_or_id = nil

    base_controller.find_by_keys_paginated(self, dao_factory.apis)
  end)

  base_controller(lapis_app, dao_factory.apis, "apis")
end
