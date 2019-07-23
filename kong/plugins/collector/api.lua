local http = require "resty.http"


local function statuses(host)
  local client = http.new()

  local ok = client:connect(host, 5000)
    if not ok then
	  return kong.response.exit(501, { message = "Host", host, " is not up." })
    end

  local res, err = client:request {
	method = "GET",
	path = "/status"
  }

  if not res then
    -- collector isn't up yet
    return kong.response.exit(500, { message = err })
  else
	return kong.response.exit(200, res:read_body())
  end

end

return {
  ["/collector/:collector_id/status"] = {
    GET = function(self, db)
      local row =  kong.db.plugins:select( { id = self.params.collector_id } )

	  if not row then
	    return kong.response.exit(404, { message = "No configuration found." })
	  end

	  statuses(row.config.host)
    end
  },
  ["/collector/configurations"] = {
	GET = function(self, db)

	  local rows, err = kong.db.plugins:select_all( {name = "collector"} )

	    if not rows then
		  return kong.response.exit(500, { message = err })
		end

		if #rows > 0 then
		  return kong.response.exit(201, rows)
		end

		local message = "No routes or services found that are configured with collector plugin"
		return kong.response.exit(404, { message =  message })
	  end
  }


}