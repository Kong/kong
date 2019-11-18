local kong = kong

return {
  ["/entities/migrate"] = {
    GET = function()
      local ok, _ = kong.db:run_core_entity_migrations({})
      if not ok then
        return kong.response.exit(500)
      end
      return kong.response.exit(204)
    end
  }
}
