return {
  {
    name = "2017-02-09-160000_datadog_schema_changes",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all {name = "datadog"}
      if err then return err end
      
      local default_metrics = {
        request_count = {
          name = "request_count",
          stat_type = "counter",
          sample_rate = 1,
          tags = {"app:kong"}
        },
        latency = {
          name = "latency",
          stat_type = "timer",
          tags = {"app:kong"}
        },
        request_size = {
          name = "request_size",
          stat_type = "timer",
          tags = {"app:kong"}
        },
        status_count = {
          name = "status_count",
          stat_type = "counter",
          sample_rate = 1,
          tags = {"app:kong"}
        },
        response_size = {
          name = "response_size",
          stat_type = "timer",
          tags = {"app:kong"}
        },
        unique_users = {
          name = "unique_users",
          stat_type = "set",
          consumer_identifier = "consumer_id",
          tags = {"app:kong"}
        },
        request_per_user = {
          name = "request_per_user",
          stat_type = "counter",
          sample_rate = 1,
          consumer_identifier = "consumer_id",
          tags = {"app:kong"}
        },
        upstream_latency = {
          name = "upstream_latency",
          stat_type = "timer",
          tags = {"app:kong"}
        },
        kong_latency = {
          name = "kong_latency",
          stat_type = "timer",
          tags = {"app:kong"}
        },
        status_count_per_user = {
          name = "status_count_per_user",
          stat_type = "counter",
          sample_rate = 1,
          consumer_identifier = "consumer_id",
          tags = {"app:kong"}
        }
      }


      for i = 1, #rows do
        local row = rows[i]

        local _, err = dao.plugins:delete(row)
        if err then return err end
        local new_metrics = {}
        if row.config.metrics ~=nil then
          for _, metric in ipairs(row.config.metrics) do
            table.insert(new_metrics, default_metrics[metric])
          end
        end

        local _, err = dao.plugins:insert {
          name = "datadog",
          api_id = row.api_id,
          enabled = row.enabled,
          config = {
            host = row.config.host,
            port = row.config.port,
            metrics = new_metrics,
          }
        }
        if err then return err end
      end
    end
  }  
}