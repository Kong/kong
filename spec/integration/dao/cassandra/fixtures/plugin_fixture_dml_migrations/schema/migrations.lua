return {
  {
    name = "stub_fixture_dml_migrations1",
    up = function(options, dao_factory)
      return dao_factory:execute_queries [[
        CREATE TABLE some_table(
          id text PRIMARY KEY,
          name text
        );
      ]]
    end,
    down = function(options, dao_factory)
      return dao_factory:execute_queries [[
        DROP TABLE some_table;
      ]]
    end
  },
  {
    name = "stub_fixture_dml_migrations2",
    up = function(options, dao_factory)
      return dao_factory:execute_queries [[
        INSERT INTO some_table(id, name) VALUES('key1', 'hello');
        INSERT INTO some_table(id, name) VALUES('key2', 'hello');
      ]]
    end,
    down = function(options, dao_factory)
      return dao_factory:execute_queries [[
        TRUNCATE some_table;
      ]]
    end
  }
}
