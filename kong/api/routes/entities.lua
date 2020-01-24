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
