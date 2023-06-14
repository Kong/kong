return {
  postgres = {
    up = [[
      DROP TABLE IF EXISTS "ttls";
    ]]
  }
}
