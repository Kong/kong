return {
  {
    name = "2016-04-15_galileo-import-mashape-analytics",
    up = function(_, _, dao)
      local rows, err = dao.plugins:find_all {name = "mashape-analytics"}
      if err then return err end

      for i = 1, #rows do
        local analytics = rows[i]
        local _, err = dao.plugins:insert {
          name = "galileo",
          api_id = analytics.api_id,
          enabled = analytics.enabled,
          config = {
            service_token = analytics.config.service_token,
            environment = analytics.config.environment,
            host = analytics.config.host,
            port = analytics.config.port,
            log_bodies = analytics.config.log_body,
            queue_size = analytics.config.batch_size,
            flush_timeout = analytics.config.delay
          }
        }
        if err then return err end

        _, err = dao.plugins:delete(analytics)
        if err then return err end
      end
    end
  }
}
