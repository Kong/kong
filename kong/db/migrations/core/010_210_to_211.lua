-- this migration is empty and makes little sense
-- it contained a Cassandra specific migration at one point
-- this is left as is to not mess up existing migrations in installations worldwide
-- see commit 8a214df628b3c754b1446e94f98eeb7609942761 for history
return {
  postgres = {
    up = [[ SELECT 1 ]],
  },
}
