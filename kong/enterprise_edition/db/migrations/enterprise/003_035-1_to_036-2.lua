return {
  postgres = {
    up = [[ ]],
    teardown = function(connector)
      -- Risky migrations
    end
  },

  cassandra = {
    up = [[ ]],
    teardown = function(connector, helpers)
      -- Risky migrations
    end
  },
}
