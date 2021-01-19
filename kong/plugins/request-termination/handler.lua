local kong = kong


local DEFAULT_RESPONSE = {
  [401] = "Unauthorized",
  [404] = "Not found",
  [405] = "Method not allowed",
  [500] = "An unexpected error occurred",
  [502] = "Bad Gateway",
  [503] = "Service unavailable",
}


local RequestTerminationHandler = {}


RequestTerminationHandler.PRIORITY = 2
RequestTerminationHandler.VERSION = "2.0.1"


function RequestTerminationHandler:access(conf)
  local status  = conf.status_code
  local content = conf.body

  if conf.echo then
    local req_headers = kong.request.get_headers()
    local req_query = kong.request.get_query()

    if conf.echo_trigger and
       not req_headers[conf.echo_trigger] and
       not req_query[conf.echo_trigger] then
      return -- no trigger found, nothing to do
    end

    content = {
      message = conf.message or DEFAULT_RESPONSE[status],
      request = {
        scheme = kong.request.get_scheme(),
        host = kong.request.get_host(),
        port = kong.request.get_port(),
        headers = req_headers,
        query = req_query,
        body = kong.request.get_body(),
        raw_body = kong.request.get_raw_body(),
        method = kong.request.get_method(),
        path = kong.request.get_path(),
      },
      matched_route = kong.router.get_route(),
      matched_service = kong.router.get_service(),
    }

    return kong.response.exit(status, content)
  end

  if content then
    local headers = {
      ["Content-Type"] = conf.content_type
    }

    return kong.response.exit(status, content, headers)
  end

  local message = conf.message or DEFAULT_RESPONSE[status]
  return kong.response.exit(status, message and { message = message } or nil)
end


return RequestTerminationHandler
