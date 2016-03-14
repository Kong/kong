return {
  {
    name = "stub_fixture_mig1",
    up = function(options, dao_factory)
      return dao_factory:execute_queries [[
        CREATE TABLE plugins1(
          id uuid PRIMARY KEY,
          name text
        );
      ]]
    end,
    down = function(options, dao_factory)
      return dao_factory:execute_queries [[
        DROP TABLE plugins1;
      ]]
    end
  },
  {
    name = "stub_fixture_mig2",
    up = function(options, dao_factory)
      return dao_factory:execute_queries [[
        CREATE TABLE plugins2(
          id uuid PRIMARY KEY,
          name text
        );
      ]]
    end,
    down = function(options, dao_factory)
      return dao_factory:execute_queries [[
        DROP TABLE plugins2;
      ]]
    end
  }
}
