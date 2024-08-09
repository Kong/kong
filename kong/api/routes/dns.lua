-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local kong = kong


return {
  ["/status/dns"] = {
    GET = function (self, db, helpers)

      if kong.configuration.legacy_dns_client then
        return kong.response.exit(501, {
          message = "not implemented with the legacy DNS client"
        })
      end

      return kong.response.exit(200, {
        worker = {
          id = ngx.worker.id() or -1,
          count = ngx.worker.count(),
        },
        stats = kong.dns.stats(),
      })
    end
  },
}
