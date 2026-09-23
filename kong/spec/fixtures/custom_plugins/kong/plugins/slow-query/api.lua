return {
  ["/slow-resource"] = {
    GET = function(self)
      local delay = self.params.delay or 1

      if self.params.prime then
        ngx.timer.at(0, function()
          local _, err = kong.db.connector:query("SELECT pg_sleep(" .. delay .. ")")
          if err then
            ngx.log(ngx.ERR, err)
          end
        end)

        return kong.response.exit(204)
      end

      local _, err = kong.db.connector:query("SELECT pg_sleep(" .. delay .. ")")
      if err then
        return kong.response.exit(500, { error = err })
      end

      return kong.response.exit(204)
    end,
  },
}
