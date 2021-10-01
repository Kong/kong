---
-- Client response module
--
-- The downstream response module contains a set of functions for producing and
-- manipulating responses sent back to the client ("downstream"). Responses can
-- be produced by Kong (e.g. an authentication plugin rejecting a request), or
-- proxied back from an Service's response body.
--
-- Unlike `kong.service.response`, this module allows mutating the response
-- before sending it back to the client.
--
-- @module kong.response


local cjson = require "cjson.safe"
local checks = require "kong.pdk.private.checks"
local phase_checker = require "kong.pdk.private.phases"
local utils = require "kong.tools.utils"


local ngx = ngx
local arg = ngx.arg
local fmt = string.format
local type = type
local find = string.find
local lower = string.lower
local error = error
local pairs = pairs
local concat = table.concat
local coroutine = coroutine
local normalize_header = checks.normalize_header
local normalize_multi_header = checks.normalize_multi_header
local validate_header = checks.validate_header
local validate_headers = checks.validate_headers
local check_phase = phase_checker.check
local split = utils.split
local add_header
if ngx and ngx.config.subsystem == "http" then
  add_header = require("ngx.resp").add_header
end


local PHASES = phase_checker.phases


local header_body_log = phase_checker.new(PHASES.response,
                                          PHASES.header_filter,
                                          PHASES.body_filter,
                                          PHASES.log,
                                          PHASES.error,
                                          PHASES.admin_api)

local rewrite_access_header = phase_checker.new(PHASES.rewrite,
                                                PHASES.access,
                                                PHASES.response,
                                                PHASES.header_filter,
                                                PHASES.error,
                                                PHASES.admin_api)


local function new(self, major_version)
  local _RESPONSE = {}

  local MIN_HEADERS          = 1
  local MAX_HEADERS_DEFAULT  = 100
  local MAX_HEADERS          = 1000

  local MIN_STATUS_CODE      = 100
  local MAX_STATUS_CODE      = 599
  local MIN_ERR_STATUS_CODE  = 400

  local GRPC_STATUS_UNKNOWN  = 2
  local GRPC_STATUS_NAME     = "grpc-status"
  local GRPC_MESSAGE_NAME    = "grpc-message"

  local CONTENT_LENGTH_NAME  = "Content-Length"
  local CONTENT_TYPE_NAME    = "Content-Type"
  local CONTENT_TYPE_JSON    = "application/json; charset=utf-8"
  local CONTENT_TYPE_GRPC    = "application/grpc"


  local ACCEPT_NAME          = "Accept"

  local HTTP_TO_GRPC_STATUS = {
    [200] = 0,
    [400] = 3,
    [401] = 16,
    [403] = 7,
    [404] = 5,
    [409] = 6,
    [429] = 8,
    [499] = 1,
    [500] = 13,
    [501] = 12,
    [503] = 14,
    [504] = 4,
  }

  local GRPC_MESSAGES = {
    [0]  = "OK",
    [1]  = "Canceled",
    [2]  = "Unknown",
    [3]  = "InvalidArgument",
    [4]  = "DeadlineExceeded",
    [5]  = "NotFound",
    [6]  = "AlreadyExists",
    [7]  = "PermissionDenied",
    [8]  = "ResourceExhausted",
    [9]  = "FailedPrecondition",
    [10] = "Aborted",
    [11] = "OutOfRange",
    [12] = "Unimplemented",
    [13] = "Internal",
    [14] = "Unavailable",
    [15] = "DataLoss",
    [16] = "Unauthenticated",
  }

  local HTTP_MESSAGES = {
    s400 = "Bad request",
    s401 = "Unauthorized",
    s402 = "Payment required",
    s403 = "Forbidden",
    s404 = "Not found",
    s405 = "Method not allowed",
    s406 = "Not acceptable",
    s407 = "Proxy authentication required",
    s408 = "Request timeout",
    s409 = "Conflict",
    s410 = "Gone",
    s411 = "Length required",
    s412 = "Precondition failed",
    s413 = "Payload too large",
    s414 = "URI too long",
    s415 = "Unsupported media type",
    s416 = "Range not satisfiable",
    s417 = "Expectation failed",
    s418 = "I'm a teapot",
    s421 = "Misdirected request",
    s422 = "Unprocessable entity",
    s423 = "Locked",
    s424 = "Failed dependency",
    s425 = "Too early",
    s426 = "Upgrade required",
    s428 = "Precondition required",
    s429 = "Too many requests",
    s431 = "Request header fields too large",
    s451 = "Unavailable for legal reasons",
    s494 = "Request header or cookie too large",
    s500 = "An unexpected error occurred",
    s501 = "Not implemented",
    s502 = "An invalid response was received from the upstream server",
    s503 = "The upstream server is currently unavailable",
    s504 = "The upstream server is timing out",
    s505 = "HTTP version not supported",
    s506 = "Variant also negotiates",
    s507 = "Insufficient storage",
    s508 = "Loop detected",
    s510 = "Not extended",
    s511 = "Network authentication required",
    default = "The upstream server responded with %d"
  }


  ---
  -- Returns the HTTP status code currently set for the downstream response (as
  -- a Lua number).
  --
  -- If the request was proxied (as per `kong.response.get_source()`), the
  -- return value will be that of the response from the Service (identical to
  -- `kong.service.response.get_status()`).
  --
  -- If the request was _not_ proxied, and the response was produced by Kong
  -- itself (i.e. via `kong.response.exit()`), the return value will be
  -- returned as-is.
  --
  -- @function kong.response.get_status
  -- @phases header_filter, response, body_filter, log, admin_api
  -- @treturn number status The HTTP status code currently set for the
  -- downstream response
  -- @usage
  -- kong.response.get_status() -- 200
  function _RESPONSE.get_status()
    check_phase(header_body_log)

    return ngx.status
  end


  ---
  -- Returns the value of the specified response header, as would be seen by
  -- the client once received.
  --
  -- The list of headers returned by this function can consist of both response
  -- headers from the proxied Service _and_ headers added by Kong (e.g. via
  -- `kong.response.add_header()`).
  --
  -- The return value is either a `string`, or can be `nil` if a header with
  -- `name` was not found in the response. If a header with the same name is
  -- present multiple times in the request, this function will return the value
  -- of the first occurrence of this header.
  --
  -- @function kong.response.get_header
  -- @phases header_filter, response, body_filter, log, admin_api
  -- @tparam string name The name of the header
  --
  -- Header names are case-insensitive and dashes (`-`) can be written as
  -- underscores (`_`); that is, the header `X-Custom-Header` can also be
  -- retrieved as `x_custom_header`.
  --
  -- @treturn string|nil The value of the header
  -- @usage
  -- -- Given a response with the following headers:
  -- -- X-Custom-Header: bla
  -- -- X-Another: foo bar
  -- -- X-Another: baz
  --
  -- kong.response.get_header("x-custom-header") -- "bla"
  -- kong.response.get_header("X-Another")       -- "foo bar"
  -- kong.response.get_header("X-None")          -- nil
  function _RESPONSE.get_header(name)
    check_phase(header_body_log)

    if type(name) ~= "string" then
      error("header name must be a string", 2)
    end

    local header_value = _RESPONSE.get_headers()[name]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  ---
  -- Returns a Lua table holding the response headers. Keys are header names.
  -- Values are either a string with the header value, or an array of strings
  -- if a header was sent multiple times. Header names in this table are
  -- case-insensitive and are normalized to lowercase, and dashes (`-`) can be
  -- written as underscores (`_`); that is, the header `X-Custom-Header` can
  -- also be retrieved as `x_custom_header`.
  --
  -- A response initially has no headers until a plugin short-circuits the
  -- proxying by producing one (e.g. an authentication plugin rejecting a
  -- request), or the request has been proxied, and one of the latter execution
  -- phases is currently running.
  --
  -- Unlike `kong.service.response.get_headers()`, this function returns *all*
  -- headers as the client would see them upon reception, including headers
  -- added by Kong itself.
  --
  -- By default, this function returns up to **100** headers. The optional
  -- `max_headers` argument can be specified to customize this limit, but must
  -- be greater than **1** and not greater than **1000**.
  --
  -- @function kong.response.get_headers
  -- @phases header_filter, response, body_filter, log, admin_api
  -- @tparam[opt] number max_headers Limits how many headers are parsed
  -- @treturn table headers A table representation of the headers in the
  -- response
  --
  -- @treturn string err If more headers than `max_headers` were present, a
  -- string with the error `"truncated"`.
  -- @usage
  -- -- Given an response from the Service with the following headers:
  -- -- X-Custom-Header: bla
  -- -- X-Another: foo bar
  -- -- X-Another: baz
  --
  -- local headers = kong.response.get_headers()
  --
  -- headers.x_custom_header -- "bla"
  -- headers.x_another[1]    -- "foo bar"
  -- headers["X-Another"][2] -- "baz"
  function _RESPONSE.get_headers(max_headers)
    check_phase(header_body_log)

    if max_headers == nil then
      return ngx.resp.get_headers(MAX_HEADERS_DEFAULT)
    end

    if type(max_headers) ~= "number" then
      error("max_headers must be a number", 2)

    elseif max_headers < MIN_HEADERS then
      error("max_headers must be >= " .. MIN_HEADERS, 2)

    elseif max_headers > MAX_HEADERS then
      error("max_headers must be <= " .. MAX_HEADERS, 2)
    end

    return ngx.resp.get_headers(max_headers)
  end


  ---
  -- This function helps determining where the current response originated
  -- from.  Kong being a reverse proxy, it can short-circuit a request and
  -- produce a response of its own, or the response can come from the proxied
  -- Service.
  --
  -- Returns a string with three possible values:
  --
  -- * "exit" is returned when, at some point during the processing of the
  --   request, there has been a call to `kong.response.exit()`. In other
  --   words, when the request was short-circuited by a plugin or by Kong
  --   itself (e.g.  invalid credentials)
  -- * "error" is returned when an error has happened while processing the
  --   request - for example, a timeout while connecting to the upstream
  --   service.
  -- * "service" is returned when the response was originated by successfully
  --   contacting the proxied Service.
  --
  -- @function kong.response.get_source
  -- @phases header_filter, response, body_filter, log, admin_api
  -- @treturn string the source.
  -- @usage
  -- if kong.response.get_source() == "service" then
  --   kong.log("The response comes from the Service")
  -- elseif kong.response.get_source() == "error" then
  --   kong.log("There was an error while processing the request")
  -- elseif kong.response.get_source() == "exit" then
  --   kong.log("There was an early exit while processing the request")
  -- end
  function _RESPONSE.get_source(ctx)
    if ctx == nil then
      check_phase(header_body_log)
      ctx = ngx.ctx
    end

    if ctx.KONG_UNEXPECTED then
      return "error"
    end

    if ctx.KONG_EXITED then
      return "exit"
    end

    if ctx.KONG_PROXIED then
      return "service"
    end

    return "error"
  end


  ---
  -- Allows changing the downstream response HTTP status code before sending it
  -- to the client.
  --
  -- @function kong.response.set_status
  -- @phases rewrite, access, header_filter, response, admin_api
  -- @tparam number status The new status
  -- @return Nothing; throws an error on invalid input.
  -- @usage
  -- kong.response.set_status(404)
  function _RESPONSE.set_status(status)
    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    if type(status) ~= "number" then
      error("code must be a number", 2)

    elseif status < MIN_STATUS_CODE or status > MAX_STATUS_CODE then
      error(fmt("code must be a number between %u and %u", MIN_STATUS_CODE, MAX_STATUS_CODE), 2)
    end

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    ngx.status = status
  end


  ---
  -- Sets a response header with the given value. This function overrides any
  -- existing header with the same name.
  --
  -- Note: Underscores in Header names are automatically transformed into dashes
  -- by default. If you want to deactivate this behavior you should set
  -- the `lua_transform_underscores_in_response_headers` nginx config option to `off`
  --
  -- This setting can be set in the Kong Config file:
  --
  --     nginx_http_lua_transform_underscores_in_response_headers = off
  --
  -- Be aware that changing this setting might slightly break any plugins that
  -- rely on the automatic underscore conversion.
  --
  -- @function kong.response.set_header
  -- @phases rewrite, access, header_filter, response, admin_api
  -- @tparam string name The name of the header
  -- @tparam string|number|boolean value The new value for the header
  -- @return Nothing; throws an error on invalid input.
  -- @usage
  -- kong.response.set_header("X-Foo", "value")
  function _RESPONSE.set_header(name, value)
    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    validate_header(name, value)

    ngx.header[name] = normalize_header(value)
  end


  ---
  -- Adds a response header with the given value. Unlike
  -- `kong.response.set_header()`, this function does not remove any existing
  -- header with the same name. Instead, another header with the same name will
  -- be added to the response. If no header with this name already exists on
  -- the response, then it is added with the given value, similarly to
  -- `kong.response.set_header().`
  --
  -- @function kong.response.add_header
  -- @phases rewrite, access, header_filter, response, admin_api
  -- @tparam string name The header name
  -- @tparam string|number|boolean value The header value
  -- @return Nothing; throws an error on invalid input.
  -- @usage
  -- kong.response.add_header("Cache-Control", "no-cache")
  -- kong.response.add_header("Cache-Control", "no-store")
  function _RESPONSE.add_header(name, value)
    -- stream subsystem would been stopped by the phase checker below
    -- therefore the nil reference to add_header will never have chance
    -- to show
    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    validate_header(name, value)

    add_header(name, normalize_header(value))
  end


  ---
  -- Removes all occurrences of the specified header in the response sent to
  -- the client.
  --
  -- @function kong.response.clear_header
  -- @phases rewrite, access, header_filter, response, admin_api
  -- @tparam string name The name of the header to be cleared
  -- @return Nothing; throws an error on invalid input.
  -- @usage
  -- kong.response.set_header("X-Foo", "foo")
  -- kong.response.add_header("X-Foo", "bar")
  --
  -- kong.response.clear_header("X-Foo")
  -- -- from here onwards, no X-Foo headers will exist in the response
  function _RESPONSE.clear_header(name)
    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    if type(name) ~= "string" then
      error("header name must be a string", 2)
    end

    ngx.header[name] = nil
  end


  ---
  -- Sets the headers for the response. Unlike `kong.response.set_header()`,
  -- the `headers` argument must be a table in which each key is a string
  -- (corresponding to a header's name), and each value is a string, or an
  -- array of strings.
  --
  -- The resulting headers are produced in lexicographical order. The order of
  -- entries with the same name (when values are given as an array) is
  -- retained.
  --
  -- This function overrides any existing header bearing the same name as those
  -- specified in the `headers` argument. Other headers remain unchanged.
  --
  -- @function kong.response.set_headers
  -- @phases rewrite, access, header_filter, response, admin_api
  -- @tparam table headers
  -- @return Nothing; throws an error on invalid input.
  -- @usage
  -- kong.response.set_headers({
  --   ["Bla"] = "boo",
  --   ["X-Foo"] = "foo3",
  --   ["Cache-Control"] = { "no-store", "no-cache" }
  -- })
  --
  -- -- Will add the following headers to the response, in this order:
  -- -- X-Bar: bar1
  -- -- Bla: boo
  -- -- Cache-Control: no-store
  -- -- Cache-Control: no-cache
  -- -- X-Foo: foo3
  function _RESPONSE.set_headers(headers)
    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    validate_headers(headers)

    for name, value in pairs(headers) do
      ngx.header[name] = normalize_multi_header(value)
    end
  end


  ---
  -- Returns the full body when the last chunk has been read.
  --
  -- Calling this function will start to buffer the body in
  -- an internal request context variable, and set the current
  -- chunk (`ngx.arg[1]`) to `nil` when the chunk is not the
  -- last one. Otherwise it returns the full buffered body.
  --
  -- @function kong.response.get_raw_body
  -- @phases `body_filter`
  -- @treturn string body The full body when the last chunk has been read,
  --                      otherwise returns `nil`
  -- @usage
  -- local body = kong.response.get_raw_body()
  -- if body then
  --   body = transform(body)
  --   kong.response.set_raw_body(body)
  -- end
  function _RESPONSE.get_raw_body()
    check_phase(PHASES.body_filter)

    local body_buffer
    local chunk = arg[1]
    local eof = arg[2]
    if eof then
      body_buffer = ngx.ctx.KONG_BODY_BUFFER
      if not body_buffer then
        return chunk
      end
    end

    if type(chunk) == "string" and chunk ~= "" then
      if not eof then
        body_buffer = ngx.ctx.KONG_BODY_BUFFER
      end

      if body_buffer then
        local n = body_buffer.n + 1
        body_buffer.n = n
        body_buffer[n] = chunk

      else
        body_buffer = {
          chunk,
          n = 1,
        }

        ngx.ctx.KONG_BODY_BUFFER = body_buffer
      end
    end

    if eof then
      if body_buffer then
        body_buffer = concat(body_buffer, "", 1, body_buffer.n)
      else
        body_buffer = ""
      end

      arg[1] = body_buffer
      return body_buffer
    end

    arg[1] = nil
    return nil
  end


  ---
  -- Sets the body of the response
  --
  -- The `body` argument must be a string and will not be processed in any way.
  -- This function cannot anymore change the `Content-Length` header if one was
  -- added. So if you decide to use this function, the `Content-Length` header
  -- should also be cleared, e.g. in `header_filter` phase.
  --
  -- @function kong.response.set_raw_body
  -- @phases `body_filter`
  -- @tparam string body The raw body
  -- @return Nothing; throws an error on invalid inputs.
  -- @usage
  -- kong.response.set_raw_body("Hello, world!")
  -- -- or
  -- local body = kong.response.get_raw_body()
  -- if body then
  --   body = transform(body)
  --   kong.response.set_raw_body(body)
  -- end
  function _RESPONSE.set_raw_body(body)
    check_phase(PHASES.body_filter)

    if type(body) ~= "string" then
      error("body must be a string", 2)
    end

    if body == "" then -- Needed by Nginx
      arg[1] = "\n"
    else
      arg[1] = body
    end

    arg[2] = true

    ngx.ctx.KONG_BODY_BUFFER = nil
  end


  local function is_grpc_request()
    local req_ctype = ngx.var.content_type
    return req_ctype
      and find(req_ctype, CONTENT_TYPE_GRPC, 1, true) == 1
      and ngx.req.http_version() == 2
  end

  local function send(status, body, headers)
    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    ngx.status = status

    local has_content_type
    local has_content_length
    if headers ~= nil then
      for name, value in pairs(headers) do
        ngx.header[name] = normalize_multi_header(value)
        if not has_content_type or not has_content_length then
          local lower_name = lower(name)
          if lower_name == "content-type"
          or lower_name == "content_type"
          then
            has_content_type = true
          elseif lower_name == "content-length"
              or lower_name == "content_length" then
            has_content_length = true
          end
        end
      end
    end

    local res_ctype = ngx.header[CONTENT_TYPE_NAME]

    local is_grpc
    local is_grpc_output
    if res_ctype then
      is_grpc = find(res_ctype, CONTENT_TYPE_GRPC, 1, true) == 1
      is_grpc_output = is_grpc
    else
      is_grpc = is_grpc_request()
    end

    local grpc_status
    if is_grpc and not ngx.header[GRPC_STATUS_NAME] then
      grpc_status = HTTP_TO_GRPC_STATUS[status]
      if not grpc_status then
        if status >= 500 and status <= 599 then
          grpc_status = HTTP_TO_GRPC_STATUS[500]
        elseif status >= 400 and status <= 499 then
          grpc_status = HTTP_TO_GRPC_STATUS[400]
        elseif status >= 200 and status <= 299 then
          grpc_status = HTTP_TO_GRPC_STATUS[200]
        else
          grpc_status = GRPC_STATUS_UNKNOWN
        end
      end

      ngx.header[GRPC_STATUS_NAME] = grpc_status
    end

    local json
    if type(body) == "table" then
      if is_grpc then
        if is_grpc_output then
          error("table body encoding with gRPC is not supported", 2)

        elseif type(body.message) == "string" then
          body = body.message

        else
          self.log.warn("body was removed because table body encoding with " ..
                        "gRPC is not supported")
          body = nil
        end

      else
        local err
        json, err = cjson.encode(body)
        if err then
          error(fmt("body encoding failed while flushing response: %s", err), 2)
        end
      end
    end

    local ctx = ngx.ctx

    local is_header_filter_phase = ctx.KONG_PHASE == PHASES.header_filter

    if json ~= nil then
      if not has_content_type then
        ngx.header[CONTENT_TYPE_NAME] = CONTENT_TYPE_JSON
      end

      if not has_content_length then
        ngx.header[CONTENT_LENGTH_NAME] = #json
      end

      if is_header_filter_phase then
        ngx.ctx.response_body = json

      else
        ngx.print(json)
      end

    elseif body ~= nil then
      if is_grpc and not is_grpc_output then
        ngx.header[CONTENT_LENGTH_NAME] = 0
        ngx.header[GRPC_MESSAGE_NAME] = body

        if is_header_filter_phase then
          ctx.response_body = ""

        else
          ngx.print() -- avoid default content
        end

      else
        if not has_content_length then
          ngx.header[CONTENT_LENGTH_NAME] = #body
        end

        if grpc_status and not ngx.header[GRPC_MESSAGE_NAME] then
          ngx.header[GRPC_MESSAGE_NAME] = GRPC_MESSAGES[grpc_status]
        end

        if is_header_filter_phase then
          ctx.response_body = body

        else
          ngx.print(body)
        end
      end

    else
      if not has_content_length then
        ngx.header[CONTENT_LENGTH_NAME] = 0
      end

      if grpc_status and not ngx.header[GRPC_MESSAGE_NAME] then
        ngx.header[GRPC_MESSAGE_NAME] = GRPC_MESSAGES[grpc_status]
      end

      if is_grpc then
        if is_header_filter_phase then
          ctx.response_body = ""

        else
          ngx.print() -- avoid default content
        end
      end
    end

    if is_header_filter_phase then
      return ngx.exit(ngx.OK)
    end

    return ngx.exit(status)
  end


  local function flush(ctx)
    ctx = ctx or ngx.ctx
    local response = ctx.delayed_response
    return send(response.status_code, response.content, response.headers)
  end

  if ngx and ngx.config.subsystem == 'http' then
    ---
    -- This function interrupts the current processing and produces a response.
    -- It is typical to see plugins using it to produce a response before Kong
    -- has a chance to proxy the request (e.g. an authentication plugin rejecting
    -- a request, or a caching plugin serving a cached response).
    --
    -- It is recommended to use this function in conjunction with the `return`
    -- operator, to better reflect its meaning:
    --
    -- ```lua
    -- return kong.response.exit(200, "Success")
    -- ```
    --
    -- Calling `kong.response.exit()` will interrupt the execution flow of
    -- plugins in the current phase. Subsequent phases will still be invoked.
    -- E.g. if a plugin called `kong.response.exit()` in the `access` phase, no
    -- other plugin will be executed in that phase, but the `header_filter`,
    -- `body_filter`, and `log` phases will still be executed, along with their
    -- plugins. Plugins should thus be programmed defensively against cases when
    -- a request was **not** proxied to the Service, but instead was produced by
    -- Kong itself.
    --
    -- The first argument `status` will set the status code of the response that
    -- will be seen by the client.
    --
    -- **In L4 proxy mode**, **only** the following status code are supported:
    --
    -- * 200 - OK
    -- * 400 - Bad request
    -- * 403 - Forbidden
    -- * 500 - Internal server error
    -- * 502 - Bad gateway
    -- * 503 - Service unavailable
    --
    -- For **L4 proxy mode** the `status` code provided is primarily for logging
    -- and statistical purpose, and is not visible to the client directly.
    --
    -- The second, optional, `body` argument will set the response body. If it is
    -- a string, no special processing will be done, and the body will be sent
    -- as-is.  It is the caller's responsibility to set the appropriate
    -- Content-Type header via the third argument.  As a convenience, `body` can
    -- be specified as a table; in which case, it will be JSON-encoded and the
    -- `application/json` Content-Type header will be set. On gRPC we cannot send
    -- the `body` with this function at the moment at least, so what it does
    -- instead is that it sends "body" in `grpc-message` header instead. If the
    -- body is a table it looks for a field `message` in it, and uses that as a
    -- `grpc-message` header. Though, if you have specified `Content-Type` header
    -- starting with `application/grpc`, the body will be sent.
    --
    -- **In L4 proxy mode**, `body` can only be `nil` or a string. Automatic JSON
    -- encoding is not available. When provided, depends on the value of `status`,
    -- the following will happen:
    --
    -- When `status` is 500, 502 or 503, then `body` will be logged in the Kong
    -- error log file. Otherwise `body` will be sent back to the L4 client.
    --
    -- The third, optional, `headers` argument can be a table specifying response
    -- headers to send. If specified, its behavior is similar to
    -- `kong.response.set_headers()`. This argument is ignored in L4 proxy mode.
    --
    -- Unless manually specified, this method will automatically set the
    -- Content-Length header in the produced response for convenience.
    -- @function kong.response.exit
    -- @phases preread, rewrite, access, admin_api, header_filter (only if `body` is nil)
    -- @tparam number status The status to be used
    -- @tparam[opt] table|string body The body to be used
    -- @tparam[opt] table headers The headers to be used
    -- @return Nothing; throws an error on invalid input.
    -- @usage
    -- return kong.response.exit(403, "Access Forbidden", {
    --   ["Content-Type"] = "text/plain",
    --   ["WWW-Authenticate"] = "Basic"
    -- })
    --
    -- ---
    --
    -- return kong.response.exit(403, [[{"message":"Access Forbidden"}]], {
    --   ["Content-Type"] = "application/json",
    --   ["WWW-Authenticate"] = "Basic"
    -- })
    --
    -- ---
    --
    -- return kong.response.exit(403, { message = "Access Forbidden" }, {
    --   ["WWW-Authenticate"] = "Basic"
    -- })
    --
    -- ---
    --
    -- -- In L4 proxy mode
    -- return kong.response.exit(200, "Success")
    --
    function _RESPONSE.exit(status, body, headers)
      if self.worker_events and ngx.get_phase() == "content" then
        self.worker_events.poll()
      end

      check_phase(rewrite_access_header)

      if ngx.headers_sent then
        error("headers have already been sent", 2)
      end

      if type(status) ~= "number" then
        error("code must be a number", 2)

      elseif status < MIN_STATUS_CODE or status > MAX_STATUS_CODE then
        error(fmt("code must be a number between %u and %u", MIN_STATUS_CODE, MAX_STATUS_CODE), 2)
      end

      if body ~= nil and type(body) ~= "string" and type(body) ~= "table" then
        error("body must be a nil, string or table", 2)
      end

      if headers ~= nil and type(headers) ~= "table" then
        error("headers must be a nil or table", 2)
      end

      if headers ~= nil then
        validate_headers(headers)
      end

      local ctx = ngx.ctx
      ctx.KONG_EXITED = true

      if ctx.delay_response and not ctx.delayed_response then
        ctx.delayed_response = {
          status_code = status,
          content     = body,
          headers     = headers,
        }

        ctx.delayed_response_callback = flush
        coroutine.yield()

      else
        return send(status, body, headers)
      end
    end

  else
    local VALID_CODES = {
      [200] = true,
      [400] = true,
      [403] = true,
      [500] = true,
      [502] = true,
      [503] = true,
      -- NOTE: when adding new code, change the documentation and error
      -- message raised below accordingly
      --
      -- Code are from http://lxr.nginx.org/source/src/stream/ngx_stream.h#0029
    }

    function _RESPONSE.exit(status, body, headers)
      if type(status) ~= "number" then
        error("code must be a number", 2)

      elseif not VALID_CODES[status] then
        error("unacceptable code, only 200, 400, 403, 500, 502 and 503 " ..
              "are accepted", 2)
      end

      if body ~= nil then
        if type(body) == "table" then
          local err
          body, err = cjson.encode(body)
          if err then
            error("invalid body: " .. err, 2)
          end
        end

        if type(body) ~= "string" then
          error("body must be a nil, string or table", 2)
        end
      end

      if body then
        if status < 400 then
          -- only sends body to the client for 200 status code
          local res, err = ngx.print(body)
          if not res then
            error("unable to send body to client: " .. err, 2)
          end

        else
          self.log.err("unable to proxy stream connection, " ..
                       "status: " .. status .. ", err: ", body)
        end
      end

      return ngx.exit(status)
    end
  end


  local function get_response_type(content_header)
    local type = CONTENT_TYPE_JSON

    if content_header ~= nil then
      local accept_values = split(content_header, ",")
      local max_quality = 0
      for _, value in ipairs(accept_values) do
        local mimetype_values = split(value, ";")
        local name
        local quality = 1
        for _, entry in ipairs(mimetype_values) do
          local m = ngx.re.match(entry, [[^\s*(\S+\/\S+)\s*$]], "ajo")
          if m then
            name = m[1]
          else
            m = ngx.re.match(entry, [[^\s*q=([0-9]*[\.][0-9]+)\s*$]], "ajoi")
            if m then
              quality = tonumber(m[1])
            end
          end
        end

        if name and quality > max_quality then
          type = utils.get_mime_type(name)
          max_quality = quality
        end
      end
    end

    return type
  end


  ---
  -- This function interrupts the current processing and produces an error
  -- response.
  --
  -- It is recommended to use this function in conjunction with the `return`
  -- operator, to better reflect its meaning:
  --
  -- ```lua
  -- return kong.response.error(500, "Error", {["Content-Type"] = "text/html"})
  -- ```
  --
  -- The first argument `status` will set the status code of the response that
  -- will be seen by the client. The status code must be of an error, i.e.
  -- >399.
  --
  -- The second, optional, `message` argument will set the message describing
  -- the error, which will be written in the body.
  --
  -- The third, optional, `headers` argument can be a table specifying response
  -- headers to send. If specified, its behavior is similar to
  -- `kong.response.set_headers()`.
  --
  -- This method will send the response formatted in JSON, XML, HTML or plain
  -- text. The actual format is chosen using one of the following options:
  -- - Manually specifying in `headers` argument using the `Content-Type`
  --   header.
  -- - Conform to the `Accept` header from the request.
  -- - If none of the above is found, fallback to JSON format.
  -- Content-Length header in the produced response for convenience.
  -- @function kong.response.error
  -- @phases rewrite, access, admin_api, header_filter (only if `body` is nil)
  -- @tparam number status The status to be used (>399)
  -- @tparam[opt] string message The error message to be used
  -- @tparam[opt] table headers The headers to be used
  -- @return Nothing; throws an error on invalid input.
  -- @usage
  -- return kong.response.error(403, "Access Forbidden", {
  --   ["Content-Type"] = "text/plain",
  --   ["WWW-Authenticate"] = "Basic"
  -- })
  --
  -- ---
  --
  -- return kong.response.error(403, "Access Forbidden")
  --
  -- ---
  --
  -- return kong.response.error(403)
  function _RESPONSE.error(status, message, headers)
    if self.worker_events and ngx.get_phase() == "content" then
      self.worker_events.poll()
    end

    check_phase(rewrite_access_header)

    if ngx.headers_sent then
      error("headers have already been sent", 2)
    end

    if type(status) ~= "number" then
      error("code must be a number", 2)

    elseif status < MIN_ERR_STATUS_CODE or status > MAX_STATUS_CODE then
      error(fmt("code must be a number between %u and %u", MIN_ERR_STATUS_CODE,
        MAX_STATUS_CODE), 2)
    end

    if message ~= nil then
      if type(message) == "table" then
        local err
        message, err = cjson.encode(message)
        if err then
          error("could not JSON encode the error message: " .. err, 2)
        end
      end

      if type(message) ~= "string" then
        error("message must be a nil, a string or a table", 2)
      end

    end

    if headers ~= nil and type(headers) ~= "table" then
      error("headers must be a nil or table", 2)
    end

    if headers ~= nil then
      validate_headers(headers)
    else
      headers = {}
    end

    local content_type_header = headers[CONTENT_TYPE_NAME]
    local content_type = content_type_header and content_type_header[1]
      or content_type_header

    if content_type_header == nil then
      if is_grpc_request() then
        content_type = CONTENT_TYPE_GRPC
      else
        content_type_header = ngx.req.get_headers()[ACCEPT_NAME]
        if type(content_type_header) == "table" then
          content_type_header = content_type_header[1]
        end
        content_type = get_response_type(content_type_header)
      end
    end

    headers[CONTENT_TYPE_NAME] = content_type

    local body
    if content_type ~= CONTENT_TYPE_GRPC then
      local actual_message = message or
                             HTTP_MESSAGES["s" .. status] or
                             fmt(HTTP_MESSAGES.default, status)
      body = fmt(utils.get_error_template(content_type), actual_message)
    end

    local ctx = ngx.ctx

    ctx.KONG_EXITED = true

    if ctx.delay_response and not ctx.delayed_response then
      ctx.delayed_response = {
        status_code = status,
        content     = body,
        headers     = headers,
      }

      ctx.delayed_response_callback = flush
      coroutine.yield()

    else
      return send(status, body, headers)
    end
  end

  return _RESPONSE
end


return {
  new = new,
}
