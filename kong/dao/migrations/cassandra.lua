return {
  {
    name = "2015-01-12-175310_skeleton",
    up = function(db, kong_config)
      local keyspace_name = kong_config.cassandra_keyspace
      local strategy, strategy_properties = kong_config.cassandra_repl_strategy, ""

      -- Format strategy options
      if strategy == "SimpleStrategy" then
        strategy_properties = string.format(", 'replication_factor': %s", kong_config.cassandra_repl_factor)
      elseif strategy == "NetworkTopologyStrategy" then
        local dcs = {}
        for _, dc_conf in ipairs(kong_config.cassandra_data_centers) do
          local dc_name, dc_repl = string.match(dc_conf, "(%w+):(%d+)")
          if dc_name and dc_repl then
            table.insert(dcs, string.format("'%s': %s", dc_name, dc_repl))
          else
            return "invalid cassandra_data_centers configuration"
          end
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

      local res, err = db:query(keyspace_str, nil, nil, nil, true)
      if not res then
        return err
      end

      local res, err = db:query [[
        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations list<text>
        );
      ]]
      if not res then
        return err
      end
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
  },
  {
    -- This is a 2 step migration; first create the extra column, using a cql 
    -- statement and following iterate over the entries to insert default values.
    
    -- Step 1) create extra column
    name = "2016-09-05-212515_retries_step_1",
    up = [[
      ALTER TABLE apis ADD retries int;
    ]],
    down = [[
      ALTER TABLE apis DROP retries;
    ]]
  },
  {
    -- Step 2) insert default values
    name = "2016-09-05-212515_retries_step_2",
    up = function(_, _, dao)
      local rows, err = dao.apis:find_all() -- fetch all rows
      if err then
        return err
      end

      for _, row in ipairs(rows) do
        if not row.retries then  -- only if retries is not set already
          -- we do not specify default values explicitly, as they will be 
          -- taken from the schema automatically by the dao.
          local _, err = dao.apis:update(row, { id = row.id }, {full = true})
          if err then
            return err
          end
        end
      end
    end,
    down = nil, 
  }
}

