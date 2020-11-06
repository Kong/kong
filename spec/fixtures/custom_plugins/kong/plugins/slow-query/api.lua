-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

return {
  ["/slow-resource"] = {
    GET = function(self)
      if self.params.prime then
        ngx.timer.at(0, function()
          local _, err = kong.db.connector:query("SELECT pg_sleep(1)")
          if err then
            ngx.log(ngx.ERR, err)
          end
        end)

        return kong.response.exit(204)
      end

      local _, err = kong.db.connector:query("SELECT pg_sleep(1)")
      if err then
        return kong.response.exit(500, { error = err })
      end

      return kong.response.exit(204)
    end,
  },
}
