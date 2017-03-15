return {
  {
    name = "2017-03-14_multiple_orgins",
    up = function(db, _, dao)
      local cjson = require "cjson"

      local rows, err = db:query([[
        SELECT * FROM plugins WHERE name = 'cors' ALLOW FILTERING
      ]])
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        local config = cjson.decode(row.config)

        config.origins = { config.origin }
        config.origin = nil

        local _, err = db:query(string.format([[
          UPDATE plugins SET config = '%s' WHERE name = 'cors' AND id = %s
        ]], cjson.encode(config), row.id))
        if err then
          return err
        end
      end
    end,
  }
}
