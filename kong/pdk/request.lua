--- Client request module
-- A set of functions to retrieve information about the incoming requests made
-- by clients.
--
-- @module kong.request


local cjson = require "cjson.safe".new()
local multipart = require "multipart"
local phase_checker = require "kong.pdk.private.phases"


local ngx = ngx
local sub = string.sub
local find = string.find
local lower = string.lower
local type = type
local error = error
local tonumber = tonumber
local check_phase = phase_checker.check
local check_not_phase = phase_checker.check_not


local PHASES = phase_checker.phases


cjson.decode_array_with_array_mt(true)


local function new(self)
  local _REQUEST = {}


  local MIN_HEADERS            = 1
  local MAX_HEADERS_DEFAULT    = 100
  local MAX_HEADERS            = 1000
  local MIN_QUERY_ARGS         = 1
  local MAX_QUERY_ARGS_DEFAULT = 100
  local MAX_QUERY_ARGS         = 1000
  local MIN_POST_ARGS          = 1
  local MAX_POST_ARGS_DEFAULT  = 100
  local MAX_POST_ARGS          = 1000

  local MIN_PORT               = 1
  local MAX_PORT               = 65535

  local CONTENT_TYPE           = "Content-Type"

  local CONTENT_TYPE_POST      = "application/x-www-form-urlencoded"
  local CONTENT_TYPE_JSON      = "application/json"
  local CONTENT_TYPE_FORM_DATA = "multipart/form-data"

  local X_FORWARDED_PROTO      = "X-Forwarded-Proto"
  local X_FORWARDED_HOST       = "X-Forwarded-Host"
  local X_FORWARDED_PORT       = "X-Forwarded-Port"


  ---
  -- Returns the scheme component of the request's URL. The returned value is
  -- normalized to lower-case form.
  --
  -- @function kong.request.get_scheme
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn string a string like `"http"` or `"https"`
  -- @usage
  -- -- Given a request to https://example.com:1234/v1/movies
  --
  -- kong.request.get_scheme() -- "https"
  function _REQUEST.get_scheme()
    check_phase(PHASES.request)

    return ngx.var.scheme
  end


  ---
  -- Returns the host component of the request's URL, or the value of the
  -- "Host" header. The returned value is normalized to lower-case form.
  --
  -- @function kong.request.get_host
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn string the host
  -- @usage
  -- -- Given a request to https://example.com:1234/v1/movies
  --
  -- kong.request.get_host() -- "example.com"
  function _REQUEST.get_host()
    check_phase(PHASES.request)

    return ngx.var.host
  end


  ---
  -- Returns the port component of the request's URL. The value is returned
  -- as a Lua number.
  --
  -- @function kong.request.get_port
  -- @phases certificate, rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn number the port
  -- @usage
  -- -- Given a request to https://example.com:1234/v1/movies
  --
  -- kong.request.get_port() -- 1234
  function _REQUEST.get_port()
    check_not_phase(PHASES.init_worker)

    return tonumber(ngx.var.server_port)
  end


  ---
  -- Returns the scheme component of the request's URL, but also considers
  -- `X-Forwarded-Proto` if it comes from a trusted source. The returned
  -- value is normalized to lower-case.
  --
  -- Whether this function considers `X-Forwarded-Proto` or not depends on
  -- several Kong configuration parameters:
  --
  -- * [trusted\_ips](https://getkong.org/docs/latest/configuration/#trusted_ips)
  -- * [real\_ip\_header](https://getkong.org/docs/latest/configuration/#real_ip_header)
  -- * [real\_ip\_recursive](https://getkong.org/docs/latest/configuration/#real_ip_recursive)
  --
  -- **Note**: support for the Forwarded HTTP Extension (RFC 7239) is not
  -- offered yet since it is not supported by ngx\_http\_realip\_module.
  --
  -- @function kong.request.get_forwarded_scheme
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn string the forwarded scheme
  -- @usage
  -- kong.request.get_forwarded_scheme() -- "https"
  function _REQUEST.get_forwarded_scheme()
    check_phase(PHASES.request)

    if self.ip.is_trusted(self.client.get_ip()) then
      local scheme = _REQUEST.get_header(X_FORWARDED_PROTO)
      if scheme then
        return lower(scheme)
      end
    end

    return _REQUEST.get_scheme()
  end


  ---
  -- Returns the host component of the request's URL or the value of the "host"
  -- header. Unlike `kong.request.get_host()`, this function will also consider
  -- `X-Forwarded-Host` if it comes from a trusted source. The returned value
  -- is normalized to lower-case.
  --
  -- Whether this function considers `X-Forwarded-Proto` or not depends on
  -- several Kong configuration parameters:
  --
  -- * [trusted\_ips](https://getkong.org/docs/latest/configuration/#trusted_ips)
  -- * [real\_ip\_header](https://getkong.org/docs/latest/configuration/#real_ip_header)
  -- * [real\_ip\_recursive](https://getkong.org/docs/latest/configuration/#real_ip_recursive)
  --
  -- **Note**: we do not currently offer support for Forwarded HTTP Extension
  -- (RFC 7239) since it is not supported by ngx_http_realip_module.
  --
  -- @function kong.request.get_forwarded_host
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn string the forwarded host
  -- @usage
  -- kong.request.get_forwarded_host() -- "example.com"
  function _REQUEST.get_forwarded_host()
    check_phase(PHASES.request)

    if self.ip.is_trusted(self.client.get_ip()) then
      local host = _REQUEST.get_header(X_FORWARDED_HOST)
      if host then
        local s = find(host, "@", 1, true)
        if s then
          host = sub(host, s + 1)
        end

        s = find(host, ":", 1, true)
        return s and lower(sub(host, 1, s - 1)) or lower(host)
      end
    end

    return _REQUEST.get_host()
  end


  ---
  -- Returns the port component of the request's URL, but also considers
  -- `X-Forwarded-Host` if it comes from a trusted source. The value
  -- is returned as a Lua number.
  --
  -- Whether this function considers `X-Forwarded-Proto` or not depends on
  -- several Kong configuration parameters:
  --
  -- * [trusted\_ips](https://getkong.org/docs/latest/configuration/#trusted_ips)
  -- * [real\_ip\_header](https://getkong.org/docs/latest/configuration/#real_ip_header)
  -- * [real\_ip\_recursive](https://getkong.org/docs/latest/configuration/#real_ip_recursive)
  --
  -- **Note**: we do not currently offer support for Forwarded HTTP Extension
  -- (RFC 7239) since it is not supported by ngx_http_realip_module.
  --
  -- @function kong.request.get_forwareded_port
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn number the forwared port
  -- @usage
  -- kong.request.get_forwarded_port() -- 1234
  function _REQUEST.get_forwarded_port()
    check_phase(PHASES.request)

    if self.ip.is_trusted(self.client.get_ip()) then
      local port = tonumber(_REQUEST.get_header(X_FORWARDED_PORT))
      if port and port >= MIN_PORT and port <= MAX_PORT then
        return port
      end

      local host = _REQUEST.get_header(X_FORWARDED_HOST)
      if host then
        local s = find(host, "@", 1, true)
        if s then
          host = sub(host, s + 1)
        end

        s = find(host, ":", 1, true)
        if s then
          port = tonumber(sub(host, s + 1))

          if port and port >= MIN_PORT and port <= MAX_PORT then
            return port
          end
        end
      end
    end

    return _REQUEST.get_port()
  end


  ---
  -- Returns the HTTP version used by the client in the request as a Lua
  -- number, returning values such as `1`, `1.1`, `2.0`, or `nil` for
  -- unrecognized values.
  --
  -- @function kong.request.get_http_version
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn number|nil the HTTP version as a Lua number
  -- @usage
  -- kong.request.get_http_version() -- 1.1
  function _REQUEST.get_http_version()
    check_phase(PHASES.request)

    return ngx.req.http_version()
  end


  ---
  -- Returns the HTTP method of the request. The value is normalized to
  -- upper-case.
  --
  -- @function kong.request.get_method
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn string the request method
  -- @usage
  -- kong.request.get_method() -- "GET"
  function _REQUEST.get_method()
    check_phase(PHASES.request)

    if ngx.ctx.KONG_UNEXPECTED and _REQUEST.get_http_version() < 2 then
      local req_line = ngx.var.request
      local idx = find(req_line, " ", 1, true)
      if idx then
        return sub(req_line, 1, idx - 1)
      end
    end

    return ngx.req.get_method()
  end


  ---
  -- Returns the path component of the request's URL. It is not normalized in
  -- any way and does not include the querystring.
  --
  -- @function kong.request.get_path
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn string the path
  -- @usage
  -- -- Given a request to https://example.com:1234/v1/movies?movie=foo
  --
  -- kong.request.get_path() -- "/v1/movies"
  function _REQUEST.get_path()
    check_phase(PHASES.request)

    local uri = ngx.var.request_uri or ""
    local s = find(uri, "?", 2, true)
    return s and sub(uri, 1, s - 1) or uri
  end


  ---
  -- Returns the path, including the querystring if any. No
  -- transformations/normalizations are done.
  --
  -- @function kong.request.get_path_with_query
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn string the path with the querystring
  -- @usage
  -- -- Given a request to https://example.com:1234/v1/movies?movie=foo
  --
  -- kong.request.get_path_with_query() -- "/v1/movies?movie=foo"
  function _REQUEST.get_path_with_query()
    check_phase(PHASES.request)
    return ngx.var.request_uri or ""
  end


  ---
  -- Returns the query component of the request's URL. It is not normalized in
  -- any way (not even URL-decoding of special characters) and does not
  -- include the leading `?` character.
  --
  -- @function kong.request.get_raw_query
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @return string the query component of the request's URL
  -- @usage
  -- -- Given a request to https://example.com/foo?msg=hello%20world&bla=&bar
  --
  -- kong.request.get_raw_query() -- "msg=hello%20world&bla=&bar"
  function _REQUEST.get_raw_query()
    check_phase(PHASES.request)

    return ngx.var.args or ""
  end


  ---
  -- Returns the value of the specified argument, obtained from the query
  -- arguments of the current request.
  --
  -- The returned value is either a `string`, a boolean `true` if an
  -- argument was not given a value, or `nil` if no argument with `name` was
  -- found.
  --
  -- If an argument with the same name is present multiple times in the
  -- querystring, this function will return the value of the first occurrence.
  --
  -- @function kong.request.get_query_arg
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @treturn string|boolean|nil the value of the argument
  -- @usage
  -- -- Given a request GET /test?foo=hello%20world&bar=baz&zzz&blo=&bar=bla&bar
  --
  -- kong.request.get_query_arg("foo") -- "hello world"
  -- kong.request.get_query_arg("bar") -- "baz"
  -- kong.request.get_query_arg("zzz") -- true
  -- kong.request.get_query_arg("blo") -- ""
  function _REQUEST.get_query_arg(name)
    check_phase(PHASES.request)

    if type(name) ~= "string" then
      error("query argument name must be a string", 2)
    end

    local arg_value = _REQUEST.get_query()[name]
    if type(arg_value) == "table" then
      return arg_value[1]
    end

    return arg_value
  end


  ---
  -- Returns the table of query arguments obtained from the querystring. Keys
  -- are query argument names. Values are either a string with the argument
  -- value, a boolean `true` if an argument was not given a value, or an array
  -- if an argument was given in the query string multiple times. Keys and
  -- values are unescaped according to URL-encoded escaping rules.
  --
  -- Note that a query string `?foo&bar` translates to two boolean `true`
  -- arguments, and `?foo=&bar=` translates to two string arguments containing
  -- empty strings.
  --
  -- By default, this function returns up to **100** arguments. The optional
  -- `max_args` argument can be specified to customize this limit, but must be
  -- greater than **1** and not greater than **1000**.
  --
  -- @function kong.request.get_query
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @tparam[opt] number max_args set a limit on the maximum number of parsed
  -- arguments
  -- @treturn table A table representation of the query string
  -- @usage
  -- -- Given a request GET /test?foo=hello%20world&bar=baz&zzz&blo=&bar=bla&bar
  --
  -- for k, v in pairs(kong.request.get_query()) do
  --   kong.log.inspect(k, v)
  -- end
  --
  -- -- Will print
  -- -- "foo" "hello world"
  -- -- "bar" {"baz", "bla", true}
  -- -- "zzz" true
  -- -- "blo" ""
  function _REQUEST.get_query(max_args)
    check_phase(PHASES.request)

    if max_args == nil then
      max_args = MAX_QUERY_ARGS_DEFAULT

    else
      if type(max_args) ~= "number" then
        error("max_args must be a number", 2)
      end

      if max_args < MIN_QUERY_ARGS then
        error("max_args must be >= " .. MIN_QUERY_ARGS, 2)
      end

      if max_args > MAX_QUERY_ARGS then
        error("max_args must be <= " .. MAX_QUERY_ARGS, 2)
      end
    end

    if ngx.ctx.KONG_UNEXPECTED and _REQUEST.get_http_version() < 2 then
      local req_line = ngx.var.request
      local qidx = find(req_line, "?", 1, true)
      if not qidx then
        return {}
      end

      local eidx = find(req_line, " ", qidx + 1, true)
      if not eidx then
        -- HTTP 414, req_line is too long
        return {}
      end

      return ngx.decode_args(sub(req_line, qidx + 1, eidx - 1), max_args)
    end

    return ngx.req.get_uri_args(max_args)
  end


  ---
  -- Returns the value of the specified request header.
  --
  -- The returned value is either a `string`, or can be `nil` if a header with
  -- `name` was not found in the request. If a header with the same name is
  -- present multiple times in the request, this function will return the value
  -- of the first occurrence of this header.
  --
  -- Header names in are case-insensitive and are normalized to lowercase, and
  -- dashes (`-`) can be written as underscores (`_`); that is, the header
  -- `X-Custom-Header` can also be retrieved as `x_custom_header`.
  --
  -- @function kong.request.get_header
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @tparam string name the name of the header to be returned
  -- @treturn string|nil the value of the header or nil if not present
  -- @usage
  -- -- Given a request with the following headers:
  --
  -- -- Host: foo.com
  -- -- X-Custom-Header: bla
  -- -- X-Another: foo bar
  -- -- X-Another: baz
  --
  -- kong.request.get_header("Host")            -- "foo.com"
  -- kong.request.get_header("x-custom-header") -- "bla"
  -- kong.request.get_header("X-Another")       -- "foo bar"
  function _REQUEST.get_header(name)
    check_phase(PHASES.request)

    if type(name) ~= "string" then
      error("header name must be a string", 2)
    end

    local header_value = _REQUEST.get_headers()[name]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  ---
  -- Returns a Lua table holding the request headers. Keys are header names.
  -- Values are either a string with the header value, or an array of strings
  -- if a header was sent multiple times. Header names in this table are
  -- case-insensitive and are normalized to lowercase, and dashes (`-`) can be
  -- written as underscores (`_`); that is, the header `X-Custom-Header` can
  -- also be retrieved as `x_custom_header`.
  --
  -- By default, this function returns up to **100** headers. The optional
  -- `max_headers` argument can be specified to customize this limit, but must
  -- be greater than **1** and not greater than **1000**.
  --
  -- @function kong.request.get_headers
  -- @phases rewrite, access, header_filter, body_filter, log, admin_api
  -- @tparam[opt] number max_headers set a limit on the maximum number of
  -- parsed headers
  -- @treturn table the request headers in table form
  -- @usage
  -- -- Given a request with the following headers:
  --
  -- -- Host: foo.com
  -- -- X-Custom-Header: bla
  -- -- X-Another: foo bar
  -- -- X-Another: baz
  -- local headers = kong.request.get_headers()
  --
  -- headers.host            -- "foo.com"
  -- headers.x_custom_header -- "bla"
  -- headers.x_another[1]    -- "foo bar"
  -- headers["X-Another"][2] -- "baz"
  function _REQUEST.get_headers(max_headers)
    check_phase(PHASES.request)

    if max_headers == nil then
      return ngx.req.get_headers(MAX_HEADERS_DEFAULT)
    end

    if type(max_headers) ~= "number" then
      error("max_headers must be a number", 2)

    elseif max_headers < MIN_HEADERS then
      error("max_headers must be >= " .. MIN_HEADERS, 2)

    elseif max_headers > MAX_HEADERS then
      error("max_headers must be <= " .. MAX_HEADERS, 2)
    end

    return ngx.req.get_headers(max_headers)
  end


  local before_content = phase_checker.new(PHASES.rewrite,
                                           PHASES.access,
                                           PHASES.error,
                                           PHASES.admin_api)


  ---
  -- Returns the plain request body.
  --
  -- If the body has no size (empty), this function returns an empty string.
  --
  -- If the size of the body is greater than the Nginx buffer size (set by
  -- `client_body_buffer_size`), this function will fail and return an error
  -- message explaining this limitation.
  --
  -- @function kong.request.get_raw_body
  -- @phases rewrite, access, admin_api
  -- @treturn string the plain request body
  -- @usage
  -- -- Given a body with payload "Hello, Earth!":
  --
  -- kong.request.get_raw_body():gsub("Earth", "Mars") -- "Hello, Mars!"
  function _REQUEST.get_raw_body()
    check_phase(before_content)

    ngx.req.read_body()

    local body = ngx.req.get_body_data()
    if not body then
      if ngx.req.get_body_file() then
        return nil, "request body did not fit into client body buffer, consider raising 'client_body_buffer_size'"

      else
        return ""
      end
    end

    return body
  end


  ---
  -- Returns the request data as a key/value table.
  -- A high-level convenience function.
  -- The body is parsed with the most appropriate format:
  --
  -- * If `mimetype` is specified:
  --   * Decodes the body with the requested content type (if supported).
  -- * If the request content type is `application/x-www-form-urlencoded`:
  --   * Returns the body as form-encoded.
  -- * If the request content type is `multipart/form-data`:
  --   * Decodes the body as multipart form data
  --     (same as `multipart(kong.request.get_raw_body(),
  --     kong.request.get_header("Content-Type")):get_all()` ).
  -- * If the request content type is `application/json`:
  --   * Decodes the body as JSON
  --     (same as `json.decode(kong.request.get_raw_body())`).
  --   * JSON types are converted to matching Lua types.
  -- * If none of the above, returns `nil` and an error message indicating the
  --   body could not be parsed.
  --
  -- The optional argument `mimetype` can be one of the following strings:
  --
  -- * `application/x-www-form-urlencoded`
  -- * `application/json`
  -- * `multipart/form-data`
  --
  -- The optional argument `max_args` can be used to set a limit on the number
  -- of form arguments parsed for `application/x-www-form-urlencoded` payloads.
  --
  -- The third return value is string containing the mimetype used to parsed
  -- the body (as per the `mimetype` argument), allowing the caller to identify
  -- what MIME type the body was parsed as.
  --
  -- @function kong.request.get_body
  -- @phases rewrite, access, admin_api
  -- @tparam[opt] string mimetype the MIME type
  -- @tparam[opt] number max_args set a limit on the maximum number of parsed
  -- arguments
  -- @treturn table|nil a table representation of the body
  -- @treturn string|nil an error message
  -- @treturn string|nil mimetype the MIME type used
  -- @usage
  -- local body, err, mimetype = kong.request.get_body()
  -- body.name -- "John Doe"
  -- body.age  -- "42"
  function _REQUEST.get_body(mimetype, max_args)
    check_phase(before_content)

    local content_type = mimetype or _REQUEST.get_header(CONTENT_TYPE)
    if not content_type then
      return nil, "missing content type"
    end

    local content_type_lower = lower(content_type)
    do
      local s = find(content_type_lower, ";", 1, true)
      if s then
        content_type_lower = sub(content_type_lower, 1, s - 1)
      end
    end

    if find(content_type_lower, CONTENT_TYPE_POST, 1, true) == 1 then
      if max_args ~= nil then
        if type(max_args) ~= "number" then
          error("max_args must be a number", 2)

        elseif max_args < MIN_POST_ARGS then
          error("max_args must be >= " .. MIN_POST_ARGS, 2)

        elseif max_args > MAX_POST_ARGS then
          error("max_args must be <= " .. MAX_POST_ARGS, 2)
        end
      end

      -- TODO: should we also compare content_length to client_body_buffer_size here?

      ngx.req.read_body()
      local pargs, err = ngx.req.get_post_args(max_args or MAX_POST_ARGS_DEFAULT)
      if not pargs then
        return nil, err, CONTENT_TYPE_POST
      end

      return pargs, nil, CONTENT_TYPE_POST

    elseif find(content_type_lower, CONTENT_TYPE_JSON, 1, true) == 1 then
      local body, err = _REQUEST.get_raw_body()
      if not body then
        return nil, err, CONTENT_TYPE_JSON
      end

      local json = cjson.decode(body)
      if type(json) ~= "table" then
        return nil, "invalid json body", CONTENT_TYPE_JSON
      end

      return json, nil, CONTENT_TYPE_JSON

    elseif find(content_type_lower, CONTENT_TYPE_FORM_DATA, 1, true) == 1 then
      local body, err = _REQUEST.get_raw_body()
      if not body then
        return nil, err, CONTENT_TYPE_FORM_DATA
      end

      -- TODO: multipart library doesn't support multiple fields with same name
      return multipart(body, content_type):get_all(), nil, CONTENT_TYPE_FORM_DATA

    else
      return nil, "unsupported content type '" .. content_type .. "'", content_type_lower
    end
  end


  return _REQUEST
end


return {
  new = new,
}
