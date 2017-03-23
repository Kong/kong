return {
  {
    name = "2017-03-14_multiple_orgins",
    up = function(db)
      local cjson = require "cjson"

      local rows, err = db:query([[
        SELECT * FROM plugins WHERE name = 'cors'
      ]])
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        row.config.origins = { row.config.origin }
        row.config.origin = nil

        local _, err = db:query(string.format([[
          UPDATE plugins SET config = '%s' WHERE id = '%s'
        ]], cjson.encode(row.config), row.id))
        if err then
          return err
        end
      end
    end,
  }
}
