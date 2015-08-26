local Migrations = {
  {
    name = "2015-08-25-841841_init_acl",
    up = function(options)
      return [[
        CREATE TABLE IF NOT EXISTS acls(
          id uuid,
          consumer_id uuid,
          group text,
          created_at timestamp,
          PRIMARY KEY (id)
        );

        CREATE INDEX IF NOT EXISTS ON acls(group);
        CREATE INDEX IF NOT EXISTS acls_consumer_id ON acls(consumer_id);
      ]]
    end,
    down = function(options)
      return [[
        DROP TABLE acls;
      ]]
    end
  }
}

return Migrations
