return {
  {
    name = "stub_fixture_mig1",
    up = function()
      return [[
        CREATE TABLE plugins(
          id uuid PRIMARY KEY,
          name text
        );
      ]]
    end,
    down = function()
       return [[
         DROP TABLE plugins;
       ]]
    end
  },
  {
    name = "stub_fixture_mig2",
    up = function()
      return [[
        CREATE TABLE plugins2(
          id uuid PRIMARY KEY,
          name text
        );
      ]]
    end,
    down = function()
       return [[
         DROP TABLE plugins2;
       ]]
    end
  }

}
