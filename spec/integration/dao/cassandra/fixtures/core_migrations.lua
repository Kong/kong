local CORE_MIGRATIONS_FIXTURES = {
  {
    name = "stub_skeleton",
    init = true,
    up = function(dao_factory)
      -- Format final keyspace creation query
      local keyspace_str = string.format([[
          CREATE KEYSPACE IF NOT EXISTS "%s"
          WITH REPLICATION = {'class': 'SimpleStrategy', 'replication_factor': 1};
      ]], dao_factory.properties.keyspace)

      local err = dao_factory:execute_queries(keyspace_str, true)
      if err then
        return err
      end

      return dao_factory:execute_queries [[
        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations list<text>
        );
      ]]
    end,
    down = function(dao_factory)
      return dao_factory:execute_queries [[
        DROP KEYSPACE "]]..dao_factory.properties.keyspace..[[";
      ]]
    end
  },
  {
    name = "stub_mig1",
    up = function(dao_factory)
      return dao_factory:execute_queries [[
        CREATE TABLE users1(
          id uuid PRIMARY KEY,
          name text,
          age int
        );
      ]]
    end,
    down = function(dao_factory)
      return dao_factory:execute_queries [[
        DROP TABLE users1;
      ]]
    end
  },
  {
    name = "stub_mig2",
    up = function(dao_factory)
      return dao_factory:execute_queries [[
        CREATE TABLE users2(
          id uuid PRIMARY KEY,
          name text,
          age int
        );
      ]]
    end,
    down = function(dao_factory)
      return dao_factory:execute_queries [[
        DROP TABLE users2;
      ]]
    end
  }
}

return CORE_MIGRATIONS_FIXTURES
