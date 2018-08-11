return {
  namespace = "kong.db.migrations",

  {
    name = "base",
  },

  --[[
  -- add column to the routes table
  {
    name = "add_column",
  },
  --]]

  ---[[
  -- rename column on the routes table
  {
    name = "rename_column",
  },
  --]]
}
