return {
  ["/slow-resource"] = {
    GET = function(self)
      if self.params.prime then
        local ok, err = kong.async:run(function(premature)
          if premature then
            return true
          end
          local _, err = kong.db.connector:query("SELECT pg_sleep(1)")
          if err then
            kong.log.err(err)
          end
        end)

        if not ok then
          kong.log.err(err)
        end

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
