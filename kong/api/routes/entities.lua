-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong

return {
  ["/entities/migrate"] = {
    GET = function(self)
      local opts = {
        conf = kong.configuration,
        force = self.params.force and true or false
      }
      local ok, err = kong.db:run_core_entity_migrations(opts)

      if err then
        kong.response.exit(400, { errors = err })
      end

      if not ok then
        return kong.response.exit(500)
      end
      return kong.response.exit(204)
    end
  }
}
