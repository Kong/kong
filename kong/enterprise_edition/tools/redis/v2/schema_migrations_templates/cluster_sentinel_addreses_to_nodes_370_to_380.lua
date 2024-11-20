-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]


local cluster_addresses_migrations = [[
  WITH updated_config as (
    SELECT
    plugins.id,
    plugins.name,
    jsonb_set(
      plugins.config,
      '{redis, cluster_nodes}',
      subquery2.cluster_nodes,
      true
    ) as config
    FROM plugins
    INNER JOIN (
      SELECT subquery.id,
            case
              when subquery.id IS NULL then 'null'
              else
                jsonb_agg(
                  jsonb_build_object(
                    'ip', split_part(subquery.address, ':', 1),
                    'port', split_part(subquery.address, ':', 2)::int
                  )
                )
            end as cluster_nodes
      FROM (
        SELECT id,
          jsonb_array_elements_text(
            case jsonb_typeof(config #> '{redis, cluster_addresses}')
              when 'array' then config #> '{redis, cluster_addresses}'
              else '[]'
            end
          ) address
        FROM plugins
        WHERE name = '%s'
      ) as subquery
      GROUP BY subquery.id
    ) as subquery2
      ON plugins.id = subquery2.id
  )
  UPDATE plugins
  SET config = updated_config.config
  FROM updated_config
  WHERE plugins.id = updated_config.id AND plugins.name = '%s';
]]

local sentinel_addresses_migration = [[
  WITH updated_config as (
    SELECT
    plugins.id,
    plugins.name,
    jsonb_set(
      plugins.config,
      '{redis, sentinel_nodes}',
      subquery2.sentinel_nodes,
      true
    ) as config
    FROM plugins
    INNER JOIN (
      SELECT subquery.id,
            case
              when subquery.id IS NULL then 'null'
              else
                jsonb_agg(
                  jsonb_build_object(
                    'host', split_part(subquery.address, ':', 1),
                    'port', split_part(subquery.address, ':', 2)::int
                  )
                )
            end as sentinel_nodes
      FROM (
        SELECT id,
          jsonb_array_elements_text(
            case jsonb_typeof(config #> '{redis, sentinel_addresses}')
              when 'array' then config #> '{redis, sentinel_addresses}'
              else '[]'
            end
          ) address
        FROM plugins
        WHERE name = '%s'
      ) as subquery
      GROUP BY subquery.id
    ) as subquery2
      ON plugins.id = subquery2.id
  )
  UPDATE plugins
  SET config = updated_config.config
  FROM updated_config
  WHERE plugins.id = updated_config.id AND plugins.name = '%s';
]]

local function up_generator(plugin_name)
  return string.format(
    [[
      DO $$
      BEGIN
    ]] ..
      cluster_addresses_migrations ..
      sentinel_addresses_migration ..
    [[
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
    ]],
    plugin_name,
    plugin_name,
    plugin_name,
    plugin_name
  )
end

local function teardown_generator(plugin_name)
  return function(connector, _)
    local sql = string.format([[
      DO $$
      BEGIN
      UPDATE plugins
      SET config =
        CASE WHEN config ? 'redis' THEN
          jsonb_set(config, '{redis}', (config -> 'redis') - 'sentinel_addresses' - 'cluster_addresses')
        ELSE
          config
        END
      WHERE name = '%s'
        AND config ? 'redis';
      EXCEPTION WHEN UNDEFINED_COLUMN OR UNDEFINED_TABLE THEN
        -- Do nothing, accept existing state
      END$$;
      ]],
      plugin_name
    )
    assert(connector:query(sql))
    return true
  end
end

local function generate(plugin_name)
  return {
    postgres = {
      up = up_generator(plugin_name),
      teardown = teardown_generator(plugin_name),
    },
  }
end

return {
  generate = generate,
}
