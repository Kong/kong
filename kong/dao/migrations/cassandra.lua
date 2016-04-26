return {
  {
    name = "2015-01-12-175310_skeleton",
    up = function(db, properties)
      local keyspace_name = properties.keyspace
      local strategy, strategy_properties = properties.replication_strategy, ""

      -- Format strategy options
      if strategy == "SimpleStrategy" then
        strategy_properties = string.format(", 'replication_factor': %s", properties.replication_factor)
      elseif strategy == "NetworkTopologyStrategy" then
        local dcs = {}
        for dc_name, dc_repl in pairs(properties.data_centers) do
          table.insert(dcs, string.format("'%s': %s", dc_name, dc_repl))
        end
        if #dcs > 0 then
          strategy_properties = string.format(", %s", table.concat(dcs, ", "))
        end
      else
        -- Strategy unknown
        return "invalid replication_strategy class"
      end

      -- Format final keyspace creation query
      local keyspace_str = string.format([[
        CREATE KEYSPACE IF NOT EXISTS "%s"
          WITH REPLICATION = {'class': '%s'%s};
      ]], keyspace_name, strategy, strategy_properties)

      local err = db:queries(keyspace_str, true)
      if err then
        return err
      end

      return db:queries [[
        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations list<text>
        );
      ]]
    end,
    down = [[
      DROP TABLE schema_migrations;
    ]]
  },
  {
    name = "2015-01-12-175310_init_schema",
    up = [[
      CREATE TABLE IF NOT EXISTS consumers(
        id uuid,
        custom_id text,
        username text,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON consumers(custom_id);
      CREATE INDEX IF NOT EXISTS ON consumers(username);

      CREATE TABLE IF NOT EXISTS apis(
        id uuid,
        name text,
        request_host text,
        request_path text,
        strip_request_path boolean,
        upstream_url text,
        preserve_host boolean,
        created_at timestamp,
        PRIMARY KEY (id)
      );

      CREATE INDEX IF NOT EXISTS ON apis(name);
      CREATE INDEX IF NOT EXISTS ON apis(request_host);
      CREATE INDEX IF NOT EXISTS ON apis(request_path);

      CREATE TABLE IF NOT EXISTS plugins(
        id uuid,
        api_id uuid,
        consumer_id uuid,
        name text,
        config text, -- serialized plugin configuration
        enabled boolean,
        created_at timestamp,
        PRIMARY KEY (id, name)
      );

      CREATE INDEX IF NOT EXISTS ON plugins(name);
      CREATE INDEX IF NOT EXISTS ON plugins(api_id);
      CREATE INDEX IF NOT EXISTS ON plugins(consumer_id);
    ]],
    down = [[
      DROP TABLE consumers;
      DROP TABLE apis;
      DROP TABLE plugins;
    ]]
  },
  {
    name = "2015-11-23-817313_nodes",
    up = [[
      CREATE TABLE IF NOT EXISTS nodes(
        name text,
        cluster_listening_address text,
        created_at timestamp,
        PRIMARY KEY (name)
      ) WITH default_time_to_live = 3600;

      CREATE INDEX IF NOT EXISTS ON nodes(cluster_listening_address);
    ]],
    down = [[
      DROP TABLE nodes;
    ]]
  },
  {
    name = "2016-02-25-160900_remove_null_consumer_id",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all {consumer_id = "00000000-0000-0000-0000-000000000000"}
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        row.consumer_id = nil
        local _, err = dao.plugins:update(row, row, {full = true})
        if err then
          return err
        end
      end
    end
  },
  {
    name = "2016-02-29-121813_remove_ttls",
    up = [[
      ALTER TABLE nodes WITH default_time_to_live = 0;
    ]],
    down = [[
      ALTER TABLE nodes WITH default_time_to_live = 3600;
    ]]
  }
}
