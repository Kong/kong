return {
  {
    name = "2017-10-31-100000_oauth2_preflight_anonymous",
    up = function (_, _, dao)
      local rows, err = dao.plugins:find_all({name = "oauth2-introspection"})
      if err then
        return err
      end
      for _, row in ipairs(rows) do
        row.config.anonymous = ""
        row.config.run_on_preflight = true

        local _, err = dao.plugins:update(row, row)
        if err then
          return err
        end
      end
    end
  }
}
