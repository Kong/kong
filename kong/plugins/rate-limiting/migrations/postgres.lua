local utils = require "kong.tools.utils"

local insert = table.insert

return {
  {
    name = "2015-08-03-132400_init_ratelimiting",
    up = [[
      CREATE TABLE IF NOT EXISTS ratelimiting_metrics(
        api_id uuid,
        identifier text,
        period text,
        period_date timestamp without time zone,
        value integer,
        PRIMARY KEY (api_id, identifier, period_date, period)
      );

      CREATE OR REPLACE FUNCTION increment_rate_limits(a_id uuid, i text, p text, p_date timestamp with time zone, v integer) RETURNS VOID AS $$
      BEGIN
        LOOP
          UPDATE ratelimiting_metrics SET value = value + v WHERE api_id = a_id AND identifier = i AND period = p AND period_date = p_date;
          IF found then
            RETURN;
          END IF;

          BEGIN
            INSERT INTO ratelimiting_metrics(api_id, period, period_date, identifier, value) VALUES(a_id, p, p_date, i, v);
            RETURN;
          EXCEPTION WHEN unique_violation THEN

          END;
        END LOOP;
      END;
      $$ LANGUAGE 'plpgsql';
    ]],
    down = [[
      DROP TABLE ratelimiting_metrics;
    ]]
  },
  {
    name = "2016-07-25-471385_ratelimiting_policies",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all {name = "rate-limiting"}
      if err then
        return err
      end

      for i = 1, #rows do
        local rate_limiting = rows[i]

        -- Delete the old one to avoid conflicts when inserting the new one
        local _, err = dao.plugins:delete(rate_limiting)
        if err then
          return err
        end

        local _, err = dao.plugins:insert {
          name = "rate-limiting",
          api_id = rate_limiting.api_id,
          consumer_id = rate_limiting.consumer_id,
          enabled = rate_limiting.enabled,
          config = {
            second = rate_limiting.config.second,
            minute = rate_limiting.config.minute,
            hour = rate_limiting.config.hour,
            day = rate_limiting.config.day,
            month = rate_limiting.config.month,
            year = rate_limiting.config.year,
            limit_by = "consumer",
            policy = "cluster",
            fault_tolerant = rate_limiting.config.continue_on_error
          }
        }
        if err then
          return err
        end
      end
    end
  },
  {
    name = "2017-07-11-180000_update_config",
    up = function(_, _, dao)
      local plugins, err = dao.plugins:find_all({ name = "rate-limiting" })
      if err then
        return err
      end

      for i = 1, #plugins do
        local plugin = plugins[i]

        -- drop the old entry
        local _, err = dao.plugins:delete(plugin)
        if err then
          return err
        end

        -- base config
        local config = {
          identifier = plugin.config.limit_by,
          window_size = {},
          limit = {},
          sync_rate = plugin.config.policy == "local" and -1 or 10, -- arbitrary default for cluster/redis
          namespace = utils.random_string(),
          strategy = plugin.config.policy == "redis" and "redis" or "cluster",
        }

        -- translate old windows to new arbitrary windows
        do
          local c = plugin.config
          local t = tonumber
          if t(c.second) then
            insert(config.window_size, 1)
            insert(config.limit, c.second)
          end

          if t(c.minute) then
            insert(config.window_size, 60)
            insert(config.limit, c.minute)
          end

          if t(c.hour) then
            insert(config.window_size, 3600)
            insert(config.limit, c.hour)
          end

          if t(c.day) then
            insert(config.window_size, 86400)
            insert(config.limit, c.day)
          end

          if t(c.month) then
            insert(config.window_size, 2592000)
            insert(config.limit, c.month)
          end

          if t(c.year) then
            insert(config.window_size, 31536000)
            insert(config.limit, c.year)
          end

          -- implied redis
          if c.redis_host then
            config.redis = {
              host = c.redis_host,
              port = c.redis_port,
              password = c.redis_password or "",
              database = c.redis_database or 0,
              timeout = c.redis_timeout or 2000,
            }
          end

          -- implied EE redis
          if c.redis_sentinel_master then
            config.redis = {
              sentinel_master = c.redis_sentinel_master,
              sentinel_role = c.redis_sentinel_role,
              sentinel_addresses = c.redis_sentinel_addresses,
              password = c.redis_password or "",
              database = c.redis_database or 0,
              timeout = c.redis_timeout or 2000,
            }
          end
        end

        local _, err = dao.plugins:insert({
          name = "rate-limiting",
          api_id = plugin.api_id,
          consumer_id = plugin.consumer_id,
          enabled = plugin.enabled,
          config = config,
        })
        if err then
          return err
        end
      end
    end,
    down = function() end,
  },
  {
    name = "2017-07-11-190000_cleanup",
    up = [[
      DROP TABLE ratelimiting_metrics;
    ]],
    down = [[
      CREATE TABLE IF NOT EXISTS ratelimiting_metrics(
        api_id uuid,
        identifier text,
        period text,
        period_date timestamp without time zone,
        value integer,
        PRIMARY KEY (api_id, identifier, period_date, period)
      );

      CREATE OR REPLACE FUNCTION increment_rate_limits(a_id uuid, i text, p text, p_date timestamp with time zone, v integer) RETURNS VOID AS $$
      BEGIN
        LOOP
          UPDATE ratelimiting_metrics SET value = value + v WHERE api_id = a_id AND identifier = i AND period = p AND period_date = p_date;
          IF found then
            RETURN;
          END IF;

          BEGIN
            INSERT INTO ratelimiting_metrics(api_id, period, period_date, identifier, value) VALUES(a_id, p, p_date, i, v);
            RETURN;
          EXCEPTION WHEN unique_violation THEN

          END;
        END LOOP;
      END;
      $$ LANGUAGE 'plpgsql';
    ]],
  },
}
