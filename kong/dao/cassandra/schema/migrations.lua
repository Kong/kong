local Migrations = {
  {
    init = true,
    name = "2015-01-12-175310_skeleton",
    up = function(options)
      local keyspace_name = options.keyspace
      local strategy, strategy_properties = options.replication_strategy, ""

      -- Format strategy options
      if strategy == "SimpleStrategy" then
        strategy_properties = string.format(", 'replication_factor': %s", options.replication_factor)
      elseif strategy == "NetworkTopologyStrategy" then
        local dcs = {}
        for dc_name, dc_repl in pairs(options.data_centers) do
          table.insert(dcs, string.format("'%s': %s", dc_name, dc_repl))
        end
        if #dcs > 0 then
          strategy_properties = string.format(", %s", table.concat(dcs, ", "))
        end
      else
        -- Strategy unknown
        return nil, "invalid replication_strategy class"
      end

      -- Format final keyspace creation query
      local keyspace_str = string.format([[
        CREATE KEYSPACE IF NOT EXISTS "%s"
          WITH REPLICATION = {'class': '%s'%s};
      ]], keyspace_name, strategy, strategy_properties)

      return keyspace_str..[[
        USE "]]..keyspace_name..[[";

        CREATE TABLE IF NOT EXISTS schema_migrations(
          id text PRIMARY KEY,
          migrations list<text>
        );
      ]]
    end,
    down = function(options)
      return [[
        DROP KEYSPACE "]]..options.keyspace..[[";
      ]]
    end
  },
  -- init schema migration
  {
    name = "2015-01-12-175310_init_schema",
    up = function(options)
      return [[
        CREATE TABLE IF NOT EXISTS consumers(
          id uuid,
          custom_id text,
          custom_data text,
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
      ]]
    end,
    down = function(options)
      return [[
        DROP TABLE consumers;
        DROP TABLE apis;
        DROP TABLE plugins;
      ]]
    end
  }
}

return Migrations
