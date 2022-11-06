return {
  ["/slow-resource"] = {
    GET = function(self)
      local sleep_duration = self.params.sleep or 1
      if self.params.prime then
        ngx.timer.at(0, function()
          local _, err = kong.db.connector:query("SELECT pg_sleep(" .. sleep_duration .. ")")
          if err then
            ngx.log(ngx.ERR, err)
          end
        end)

        return kong.response.exit(204)
      end

      local _, err = kong.db.connector:query("SELECT pg_sleep(" .. sleep_duration .. ")")
      if err then
        return kong.response.exit(500, { error = err })
      end

      return kong.response.exit(204)
    end,
  },
}
