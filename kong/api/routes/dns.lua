local kong = kong


return {
  ["/status/dns"] = {
    GET = function (self, db, helpers)

      if not kong.configuration.new_dns_client then
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
