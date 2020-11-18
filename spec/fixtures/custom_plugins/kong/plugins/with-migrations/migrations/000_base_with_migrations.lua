return {
  postgres = {
    up = [[
      CREATE TABLE IF NOT EXISTS "foos" (
        "color" TEXT PRIMARY KEY
      );

      INSERT INTO foos (color) values ('red');
    ]],
  },

  cassandra = {
    up = [[
      CREATE TABLE IF NOT EXISTS foos (
        color text PRIMARY KEY
      );

      INSERT INTO foos(color) values('red');
    ]],
    up_f = function(connector)
      local coordinator = assert(connector:get_stored_connection())
      local _, err = coordinator:execute([[
        INSERT INTO foos(color) values('green');
      ]])

      if err then
        return nil, err
      end

      return true
    end,
  },
}
