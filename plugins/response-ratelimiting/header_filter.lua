if not conf.hide_client_headers then
        ngx.header[RATELIMIT_LIMIT.."-"..limit_name.."-"..period_name] = lv.limit
        ngx.header[RATELIMIT_REMAINING.."-"..limit_name.."-"..period_name] = math_max(0, lv.remaining - (increments[limit_name] and increments[limit_name] or 0)) -- increment_value for this current request
      end

      if increments[limit_name] and increments[limit_name] > 0 and lv.remaining <= 0 then
        stop = true -- No more
