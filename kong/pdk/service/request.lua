---
-- Manipulation of the request to the Service
-- @module kong.service.request

local cjson = require "cjson.safe"
local checks = require "kong.pdk.private.checks"
local phase_checker = require "kong.pdk.private.phases"


local ngx = ngx
local table_insert = table.insert
local table_sort = table.sort
local table_concat = table.concat
local string_find = string.find
local string_sub = string.sub
local string_lower = string.lower
local normalize_header = checks.normalize_header
local normalize_multi_header = checks.normalize_multi_header
local validate_header = checks.validate_header
local validate_headers = checks.validate_headers
local check_phase = phase_checker.check


local PHASES = phase_checker.phases


local access_and_rewrite = phase_checker.new(PHASES.rewrite, PHASES.access)


---
-- Produce a lexicographically ordered querystring, given a table of values.
--
-- @param args A table where keys are strings and values are strings, booleans,
-- or an array of strings or booleans.
-- @treturn string|nil an URL-encoded query string, or nil if an error ocurred
-- @treturn string|nil and an error message if an error ocurred, or nil
local function make_ordered_args(args)
  local out = {}
  local t = {}
  for k, v in pairs(args) do
    if type(k) ~= "string" then
      return nil, "arg keys must be strings"
    end

    t[k] = v

    local pok, s = pcall(ngx.encode_args, t)
    if not pok then
      return nil, s
    end

    table_insert(out, s)
    t[k] = nil
  end
  table_sort(out)
  return table_concat(out, "&")
end


-- The service request module: functions for dealing with data to be sent
-- to the service, i.e. for connections made by Kong.
local function new(self)

  local request = {}

  -- TODO these constants should be shared with kong.request

  local CONTENT_TYPE           = "Content-Type"

  local CONTENT_TYPE_POST      = "application/x-www-form-urlencoded"
  local CONTENT_TYPE_JSON      = "application/json"
  local CONTENT_TYPE_FORM_DATA = "multipart/form-data"

  local MIN_HEADERS            = 1
  local MAX_HEADERS_DEFAULT    = 100
  local MAX_HEADERS            = 1000
  local MIN_QUERY_ARGS         = 1
  local MAX_QUERY_ARGS_DEFAULT = 100
  local MAX_QUERY_ARGS         = 1000

  ---
  -- Returns the scheme component of the request to the Service.
  -- The returned value is normalized to lower-case form.
  --
  -- @function kong.service.request.get_scheme
  -- @phases rewrite, access, header_filter, body_filter, log
  -- @treturn string a string like `"http"` or `"https"`
  -- @usage
  -- -- Given a proxy request to https://example.com:1234/v1/movies
  --
  -- kong.service.request.get_scheme() -- "https"
  request.get_scheme = function()
    check_phase(PHASES.request)

    return ngx.var.upstream_scheme
  end


  ---
  -- Sets the protocol of the request to the Service.
  -- @function kong.service.request.set_scheme
  -- @phases `access`
  -- @tparam string scheme The scheme to be used. Supported values are `"http"` or `"https"`
  -- @return Nothing; throws an error on invalid inputs.
  -- @usage
  -- kong.service.request.set_scheme("https")
  request.set_scheme = function(scheme)
    check_phase(PHASES.access)

    if type(scheme) ~= "string" then
      error("scheme must be a string", 2)
    end

    if scheme ~= "http" and scheme ~= "https" then
      error("invalid scheme: " .. scheme, 2)
    end

    ngx.var.upstream_scheme = scheme
  end


  ---
  -- Returns the host component of the request to the Service.
  -- The returned value is normalized to lower-case form.
  --
  -- @function kong.service.request.get_host
  -- @phases rewrite, access, header_filter, body_filter, log
  -- @treturn string the host
  -- @usage
  -- -- Given a proxy request to https://example.com:1234/v1/movies
  --
  -- kong.service.request.get_host() -- "example.com"
  request.get_host = function()
    check_phase(PHASES.request)

    if (ngx.ctx.balancer_data == nil) or (ngx.ctx.balancer_data.host == nil) then
        return ""
    end

    return string_lower(ngx.ctx.balancer_data.host)
  end


  ---
  -- Returns the port component of the request to the Service. The value is returned
  -- as a Lua number.
  --
  -- @function kong.service.request.get_port
  -- @phases certificate, rewrite, access, header_filter, body_filter, log
  -- @treturn number the port
  -- @usage
  -- -- Given a proxy request to https://example.com:1234/v1/movies
  --
  -- kong.service.request.get_port() -- 1234
  request.get_port = function()
    check_phase(PHASES.request)

    return tonumber(ngx.ctx.balancer_data.port)
  end


  ---
  -- Returns the path component of the request to the Service.
  -- It is not normalized in any way and does not include the querystring.
  --
  -- @function kong.service.request.get_path
  -- @phases rewrite, access, header_filter, body_filter, log
  -- @treturn string the path
  -- @usage
  -- -- Given a proxy request to https://example.com:1234/v1/movies?movie=foo
  --
  -- kong.service.request.get_path() -- "/v1/movies"
  request.get_path = function()
    check_phase(PHASES.request)

    local uri = ngx.var.upstream_uri
    local s = string_find(uri, "?", 2, true)
    return s and string_sub(uri, 1, s - 1) or uri
  end


  ---
  -- Sets the path component for the request to the service. It is not
  -- normalized in any way and should **not** include the querystring.
  -- @function kong.service.request.set_path
  -- @phases `access`
  -- @param path The path string. Example: "/v2/movies"
  -- @return Nothing; throws an error on invalid inputs.
  -- @usage
  -- kong.service.request.set_path("/v2/movies")
  request.set_path = function(path)
    check_phase(PHASES.access)

    if type(path) ~= "string" then
      error("path must be a string", 2)
    end

    if string_sub(path, 1, 1) ~= "/" then
      error("path must start with /", 2)
    end

    -- TODO: is this necessary in specific phases?
    -- ngx.req.set_uri(path)
    ngx.var.upstream_uri = path
  end


  ---
  -- Returns the query component of the request to the Service. It is not normalized in
  -- any way (not even URL-decoding of special characters) and does not
  -- include the leading `?` character.
  --
  -- @function kong.service.request.get_raw_query
  -- @phases rewrite, access, header_filter, body_filter, log
  -- @return string the query component of the request's URL
  -- @usage
  -- -- Given a request to https://example.com/foo?msg=hello%20world&bla=&bar
  --
  -- kong.service.request.get_raw_query() -- "msg=hello%20world&bla=&bar"
  request.get_raw_query = function()
    check_phase(PHASES.request)

    return ngx.var.args or ""
  end


  ---
  -- Sets the querystring of the request to the Service. The `query` argument is a
  -- string (without the leading `?` character), and will not be processed in any
  -- way.
  --
  -- For a higher-level function to set the query string from a Lua table of
  -- arguments, see `kong.service.request.set_query()`.
  -- @function kong.service.request.set_raw_query
  -- @phases `rewrite`, `access`
  -- @tparam string query The raw querystring. Example: "foo=bar&bla&baz=hello%20world"
  -- @return Nothing; throws an error on invalid inputs.
  -- @usage
  -- kong.service.request.set_raw_query("zzz&bar=baz&bar=bla&bar&blo=&foo=hello%20world")
  request.set_raw_query = function(query)
    check_phase(access_and_rewrite)

    if type(query) ~= "string" then
      error("query must be a string", 2)
    end

    ngx.req.set_uri_args(query)
  end


  do
    local accepted_methods = {
      ["GET"]       = ngx.HTTP_GET,
      ["HEAD"]      = ngx.HTTP_HEAD,
      ["PUT"]       = ngx.HTTP_PUT,
      ["POST"]      = ngx.HTTP_POST,
      ["DELETE"]    = ngx.HTTP_DELETE,
      ["OPTIONS"]   = ngx.HTTP_OPTIONS,
      ["MKCOL"]     = ngx.HTTP_MKCOL,
      ["COPY"]      = ngx.HTTP_COPY,
      ["MOVE"]      = ngx.HTTP_MOVE,
      ["PROPFIND"]  = ngx.HTTP_PROPFIND,
      ["PROPPATCH"] = ngx.HTTP_PROPPATCH,
      ["LOCK"]      = ngx.HTTP_LOCK,
      ["UNLOCK"]    = ngx.HTTP_UNLOCK,
      ["PATCH"]     = ngx.HTTP_PATCH,
      ["TRACE"]     = ngx.HTTP_TRACE,
    }


    ---
    -- Returns the HTTP method of the request to the Service.
    -- The value is normalized to upper-case.
    --
    -- @function kong.service.request.get_method
    -- @phases rewrite, access, header_filter, body_filter, log
    -- @treturn string the request method
    -- @usage
    -- kong.service.request.get_method() -- "GET"
    request.get_method = function()
      check_phase(PHASES.request)

      return ngx.req.get_method()
    end


    ---
    -- Sets the HTTP method of the request to the Service.
    --
    -- @function kong.service.request.set_method
    -- @phases `rewrite`, `access`
    -- @param method The method string, which should be given in all
    -- uppercase. Supported values are: `"GET"`, `"HEAD"`, `"PUT"`, `"POST"`,
    -- `"DELETE"`, `"OPTIONS"`, `"MKCOL"`, `"COPY"`, `"MOVE"`, `"PROPFIND"`,
    -- `"PROPPATCH"`, `"LOCK"`, `"UNLOCK"`, `"PATCH"`, `"TRACE"`.
    -- @return Nothing; throws an error on invalid inputs.
    -- @usage
    -- kong.service.request.set_method("DELETE")
    request.set_method = function(method)
      check_phase(access_and_rewrite)

      if type(method) ~= "string" then
        error("method must be a string", 2)
      end

      local method_id = accepted_methods[method]
      if not method_id then
        error("invalid method: " .. method, 2)
      end

      ngx.req.set_method(method_id)
    end
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
  -- @function kong.service.request.get_query
  -- @phases rewrite, access, header_filter, body_filter, log
  -- @tparam[opt] number max_args set a limit on the maximum number of parsed
  -- arguments
  -- @treturn table A table representation of the query string
  -- @usage
  -- -- Given a proxy request GET /test?foo=hello%20world&bar=baz&zzz&blo=&bar=bla&bar
  --
  -- for k, v in pairs(kong.service.request.get_query()) do
  --   kong.log.inspect(k, v)
  -- end
  --
  -- -- Will print
  -- -- "foo" "hello world"
  -- -- "bar" {"baz", "bla", true}
  -- -- "zzz" true
  -- -- "blo" ""
  request.get_query = function(max_args)
    check_phase(PHASES.request)

    if max_args == nil then
      return ngx.req.get_uri_args(MAX_QUERY_ARGS_DEFAULT)
    end

    if type(max_args) ~= "number" then
      error("max_args must be a number", 2)
    end

    if max_args < MIN_QUERY_ARGS then
      error("max_args must be >= " .. MIN_QUERY_ARGS, 2)
    end

    if max_args > MAX_QUERY_ARGS then
      error("max_args must be <= " .. MAX_QUERY_ARGS, 2)
    end

    return ngx.req.get_uri_args(max_args)
  end


  ---
  -- Returns the value of the specified argument, obtained from the query
  -- arguments of the current request to the Service.
  --
  -- The returned value is either a `string`, a boolean `true` if an
  -- argument was not given a value, or `nil` if no argument with `name` was
  -- found.
  --
  -- If an argument with the same name is present multiple times in the
  -- querystring, this function will return the value of the first occurrence.
  --
  -- @function kong.service.request.get_query_arg
  -- @phases rewrite, access, header_filter, body_filter, log
  -- @treturn string|boolean|nil the value of the argument
  -- @usage
  -- -- Given a proxy request GET /test?foo=hello%20world&bar=baz&zzz&blo=&bar=bla&bar
  --
  -- kong.service.request.get_query_arg("foo") -- "hello world"
  -- kong.service.request.get_query_arg("bar") -- "baz"
  -- kong.service.request.get_query_arg("zzz") -- true
  -- kong.service.request.get_query_arg("blo") -- ""
  request.get_query_arg = function(name)
    check_phase(PHASES.request)

    if type(name) ~= "string" then
      error("query argument name must be a string", 2)
    end

    local arg_value = request.get_query()[name]
    if type(arg_value) == "table" then
      return arg_value[1]
    end

    return arg_value
  end


  ---
  -- Set the querystring of the request to the Service.
  --
  -- Unlike `kong.service.request.set_raw_query()`, the `query` argument must be a
  -- table in which each key is a string (corresponding to an arguments name), and
  -- each value is either a boolean, a string or an array of strings or booleans.
  -- Additionally, all string values will be URL-encoded.
  --
  -- The resulting querystring will contain keys in their lexicographical order. The
  -- order of entries within the same key (when values are given as an array) is
  -- retained.
  --
  -- If further control of the querystring generation is needed, a raw querystring
  -- can be given as a string with `kong.service.request.set_raw_query()`.
  --
  -- @function kong.service.request.set_query
  -- @phases `rewrite`, `access`
  -- @tparam table args A table where each key is a string (corresponding to an
  --   argument name), and each value is either a boolean, a string or an array of
  --   strings or booleans. Any string values given are URL-encoded.
  -- @return Nothing; throws an error on invalid inputs.
  -- @usage
  -- kong.service.request.set_query({
  --   foo = "hello world",
  --   bar = {"baz", "bla", true},
  --   zzz = true,
  --   blo = ""
  -- })
  -- -- Will produce the following query string:
  -- -- bar=baz&bar=bla&bar&blo=&foo=hello%20world&zzz
  request.set_query = function(args)
    check_phase(access_and_rewrite)

    if type(args) ~= "table" then
      error("args must be a table", 2)
    end

    local querystring, err = make_ordered_args(args)
    if not querystring then
      error(err, 2) -- type error inside the table
    end

    ngx.req.set_uri_args(querystring)
  end


  ---
  -- Returns the value of the specified header of the request to the Service.
  --
  -- The returned value is either a `string`, or can be `nil` if a header with
  -- `name` is not found in the request. If a header with the same name is
  -- present multiple times in the request, this function will return the value
  -- of the first occurrence of this header.
  --
  -- Header names in are case-insensitive and are normalized to lowercase, and
  -- dashes (`-`) can be written as underscores (`_`); that is, the header
  -- `X-Custom-Header` can also be retrieved as `x_custom_header`.
  --
  -- @function kong.service.request.get_header
  -- @phases rewrite, access, header_filter, body_filter, log
  -- @tparam string name the name of the header to be returned
  -- @treturn string the value of the header
  -- @usage
  -- -- Given a proxy request with the following headers:
  --
  -- -- Host: foo.com
  -- -- X-Custom-Header: bla
  -- -- X-Another: foo bar
  -- -- X-Another: baz
  --
  -- kong.service.request.get_header("Host")            -- "foo.com"
  -- kong.service.request.get_header("x-custom-header") -- "bla"
  -- kong.service.request.get_header("X-Another")       -- "foo bar"
  request.get_header = function(name)
    check_phase(PHASES.request)

    if type(name) ~= "string" then
      error("header name must be a string", 2)
    end

    local header_value = request.get_headers()[name]
    if type(header_value) == "table" then
      return header_value[1]
    end

    return header_value
  end


  ---
  -- Returns a Lua table holding the headers of the request to the Service.
  -- Keys are header names.
  -- Values are either a string with the header value, or an array of strings
  -- if a header is present multiple times. Header names in this table are
  -- case-insensitive and are normalized to lowercase, and dashes (`-`) can be
  -- written as underscores (`_`); that is, the header `X-Custom-Header` can
  -- also be retrieved as `x_custom_header`.
  --
  -- By default, this function returns up to **100** headers. The optional
  -- `max_headers` argument can be specified to customize this limit, but must
  -- be greater than **1** and not greater than **1000**.
  --
  -- @function kong.service.request.get_headers
  -- @phases rewrite, access, header_filter, body_filter, log
  -- @tparam[opt] number max_headers set a limit on the maximum number of
  -- parsed headers
  -- @treturn table the request headers in table form
  -- @usage
  -- -- Given a proxy request with the following headers:
  --
  -- -- Host: foo.com
  -- -- X-Custom-Header: bla
  -- -- X-Another: foo bar
  -- -- X-Another: baz
  -- local headers = kong.service.request.get_headers()
  --
  -- headers.host            -- "foo.com"
  -- headers.x_custom_header -- "bla"
  -- headers.x_another[1]    -- "foo bar"
  -- headers["X-Another"][2] -- "baz"
  request.get_headers = function(max_headers)
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


  ---
  -- Sets a header in the request to the Service with the given value. Any existing header
  -- with the same name will be overridden.
  --
  -- If the `header` argument is `"host"` (case-insensitive), then this is
  -- will also set the SNI of the request to the Service.
  --
  -- @function kong.service.request.set_header
  -- @phases `rewrite`, `access`
  -- @tparam string header The header name. Example: "X-Foo"
  -- @tparam string|boolean|number value The header value. Example: "hello world"
  -- @return Nothing; throws an error on invalid inputs.
  -- @usage
  -- kong.service.request.set_header("X-Foo", "value")
  request.set_header = function(header, value)
    check_phase(access_and_rewrite)

    validate_header(header, value)

    if string_lower(header) == "host" then
      ngx.var.upstream_host = value
    end

    ngx.req.set_header(header, normalize_header(value))
  end

  ---
  -- Adds a request header with the given value to the request to the Service. Unlike
  -- `kong.service.request.set_header()`, this function will not remove any existing
  -- headers with the same name. Instead, several occurences of the header will be
  -- present in the request. The order in which headers are added is retained.
  --
  -- @function kong.service.request.add_header
  -- @phases `rewrite`, `access`
  -- @tparam string header The header name. Example: "Cache-Control"
  -- @tparam string|number|boolean value The header value. Example: "no-cache"
  -- @return Nothing; throws an error on invalid inputs.
  -- @usage
  -- kong.service.request.add_header("Cache-Control", "no-cache")
  -- kong.service.request.add_header("Cache-Control", "no-store")
  request.add_header = function(header, value)
    check_phase(access_and_rewrite)

    validate_header(header, value)

    if string_lower(header) == "host" then
      ngx.var.upstream_host = value
    end

    local headers = ngx.req.get_headers()[header]
    if type(headers) ~= "table" then
      headers = { headers }
    end

    table_insert(headers, normalize_header(value))

    ngx.req.set_header(header, headers)
  end


  ---
  -- Removes all occurrences of the specified header in the request to the Service.
  -- @function kong.service.request.clear_header
  -- @phases `rewrite`, `access`
  -- @tparam string header The header name. Example: "X-Foo"
  -- @return Nothing; throws an error on invalid inputs.
  --   The function does not throw an error if no header was removed.
  -- @usage
  -- kong.service.request.set_header("X-Foo", "foo")
  -- kong.service.request.add_header("X-Foo", "bar")
  -- kong.service.request.clear_header("X-Foo")
  -- -- from here onwards, no X-Foo headers will exist in the request
  request.clear_header = function(header)
    check_phase(access_and_rewrite)

    if type(header) ~= "string" then
      error("header must be a string", 2)
    end

    ngx.req.clear_header(header)
  end


  ---
  -- Sets the headers of the request to the Service. Unlike
  -- `kong.service.request.set_header()`, the `headers` argument must be a table in
  -- which each key is a string (corresponding to a header's name), and each value
  -- is a string, or an array of strings.
  --
  -- The resulting headers are produced in lexicographical order. The order of
  -- entries with the same name (when values are given as an array) is retained.
  --
  -- This function overrides any existing header bearing the same name as those
  -- specified in the `headers` argument. Other headers remain unchanged.
  --
  -- If the `"Host"` header is set (case-insensitive), then this is
  -- will also set the SNI of the request to the Service.
  -- @function kong.service.request.set_headers
  -- @phases `rewrite`, `access`
  -- @tparam table headers A table where each key is a string containing a header name
  --   and each value is either a string or an array of strings.
  -- @return Nothing; throws an error on invalid inputs.
  -- @usage
  -- kong.service.request.set_header("X-Foo", "foo1")
  -- kong.service.request.add_header("X-Foo", "foo2")
  -- kong.service.request.set_header("X-Bar", "bar1")
  -- kong.service.request.set_headers({
  --   ["X-Foo"] = "foo3",
  --   ["Cache-Control"] = { "no-store", "no-cache" },
  --   ["Bla"] = "boo"
  -- })
  --
  -- -- Will add the following headers to the request, in this order:
  -- -- X-Bar: bar1
  -- -- Bla: boo
  -- -- Cache-Control: no-store
  -- -- Cache-Control: no-cache
  -- -- X-Foo: foo3
  request.set_headers = function(headers)
    check_phase(access_and_rewrite)

    if type(headers) ~= "table" then
      error("headers must be a table", 2)
    end

    -- Check for type errors first

    validate_headers(headers)

    -- Now we can use ngx.req.set_header without pcall

    for k, v in pairs(headers) do
      if string_lower(k) == "host" then
        ngx.var.upstream_host = v
      end

      ngx.req.set_header(k, normalize_multi_header(v))
    end

  end


  ---
  -- Sets the body of the request to the Service.
  --
  -- The `body` argument must be a string and will not be processed in any way.
  -- This function also sets the `Content-Length` header appropriately. To set an
  -- empty body, one can give an empty string `""` to this function.
  --
  -- For a higher-level function to set the body based on the request content type,
  -- see `kong.service.request.set_body()`.
  -- @function kong.service.request.set_raw_body
  -- @phases `rewrite`, `access`
  -- @tparam string body The raw body
  -- @return Nothing; throws an error on invalid inputs.
  -- @usage
  -- kong.service.request.set_raw_body("Hello, world!")
  request.set_raw_body = function(body)
    check_phase(access_and_rewrite)

    if type(body) ~= "string" then
      error("body must be a string", 2)
    end

    -- TODO Can we get the body size limit configured for Kong and check for
    -- length based on that, and fail gracefully before attempting to set
    -- the body?

    -- Ensure client request body has been read.
    -- This function is a nop if body has already been read,
    -- and necessary to write the request to the service if it has not.
    ngx.req.read_body()

    ngx.req.set_body_data(body)
  end


  do
    local set_body_handlers = {

      [CONTENT_TYPE_POST] = function(args, mime)
        if type(args) ~= "table" then
          error("args must be a table", 3)
        end

        local querystring, err = make_ordered_args(args)
        if not querystring then
          error(err, 3) -- type error inside the table
        end

        return querystring, mime
      end,

      [CONTENT_TYPE_JSON] = function(args, mime)
        local encoded, err = cjson.encode(args)
        if not encoded then
          error(err, 3)
        end

        return encoded, mime
      end,

      [CONTENT_TYPE_FORM_DATA] = function(args, mime)
        local keys = {}

        local boundary
        local boundary_ok = false
        local at = string_find(mime, "boundary=", 1, true)
        if at then
          at = at + 9
          if string_sub(mime, at, at) == '"' then
            local till = string_find(mime, '"', at + 1, true)
            boundary = string_sub(mime, at + 1, till - 1)
          else
            boundary = string_sub(mime, at)
          end
          boundary_ok = true
        end

        -- This will only loop in the unlikely event that the
        -- boundary is not acceptable and needs to be regenerated.
        repeat

          if not boundary_ok then
            boundary = tostring(math.random(1e10))
            boundary_ok = true
          end

          local boundary_check = "\n--" .. boundary
          local i = 1
          for k, v in pairs(args) do
            if type(k) ~= "string" then
              error(("invalid key %q: got %s, " ..
                     "expected string"):format(k, type(k)), 3)
            end
            local tv = type(v)
            if tv ~= "string" and tv ~= "number" and tv ~= "boolean" then
              error(("invalid value %q: got %s, " ..
                     "expected string, number or boolean"):format(k, tv), 3)
            end
            keys[i] = k
            i = i + 1
            if string_find(v, boundary_check, 1, true) then
              boundary_ok = false
            end
          end

        until boundary_ok

        table_sort(keys)

        local out = {}
        local i = 1

        for _, k in ipairs(keys) do
          out[i] = "--"
          out[i + 1] = boundary
          out[i + 2] = "\r\n"
          out[i + 3] = 'Content-Disposition: form-data; name="'
          out[i + 4] = k
          out[i + 5] = '"\r\n\r\n'
          local v = args[k]
          out[i + 6] = v
          out[i + 7] = "\r\n"
          i = i + 8
        end
        out[i] = "--"
        out[i + 1] = boundary
        out[i + 2] = "--\r\n"

        local output = table.concat(out)

        return output, CONTENT_TYPE_FORM_DATA .. "; boundary=" .. boundary
      end,

    }


    ---
    -- Sets the body of the request to the Service. Unlike
    -- `kong.service.request.set_raw_body()`, the `args` argument must be a table, and
    -- will be encoded with a MIME type.  The encoding MIME type can be specified in
    -- the optional `mimetype` argument, or if left unspecified, will be chosen based
    -- on the `Content-Type` header of the client's request.
    --
    -- If the MIME type is `application/x-www-form-urlencoded`:
    --
    -- * Encodes the arguments as form-encoded: keys are produced in lexicographical
    --   order. The order of entries within the same key (when values are
    --   given as an array) is retained. Any string values given are URL-encoded.
    --
    -- If the MIME type is `multipart/form-data`:
    --
    -- * Encodes the arguments as multipart form data.
    --
    -- If the MIME type is `application/json`:
    --
    -- * Encodes the arguments as JSON (same as
    --   `kong.service.request.set_raw_body(json.encode(args))`)
    -- * Lua types are converted to matching JSON types.mej
    --
    -- If none of the above, returns `nil` and an error message indicating the
    -- body could not be encoded.
    --
    -- The optional argument `mimetype` can be one of:
    --
    -- * `application/x-www-form-urlencoded`
    -- * `application/json`
    -- * `multipart/form-data`
    --
    -- If the `mimetype` argument is specified, the `Content-Type` header will be
    -- set accordingly in the request to the Service.
    --
    -- If further control of the body generation is needed, a raw body can be given as
    -- a string with `kong.service.request.set_raw_body()`.
    --
    -- @function kong.service.request.set_body
    -- @phases `rewrite`, `access`
    -- @tparam table args A table with data to be converted to the appropriate format
    -- and stored in the body.
    -- @tparam[opt] string mimetype can be one of:
    -- @treturn boolean|nil `true` on success, `nil` otherwise
    -- @treturn string|nil `nil` on success, an error message in case of error.
    -- Throws an error on invalid inputs.
    -- @usage
    -- kong.service.set_header("application/json")
    -- local ok, err = kong.service.request.set_body({
    --   name = "John Doe",
    --   age = 42,
    --   numbers = {1, 2, 3}
    -- })
    --
    -- -- Produces the following JSON body:
    -- -- { "name": "John Doe", "age": 42, "numbers":[1, 2, 3] }
    --
    -- local ok, err = kong.service.request.set_body({
    --   foo = "hello world",
    --   bar = {"baz", "bla", true},
    --   zzz = true,
    --   blo = ""
    -- }, "application/x-www-form-urlencoded")
    --
    -- -- Produces the following body:
    -- -- bar=baz&bar=bla&bar&blo=&foo=hello%20world&zzz
    request.set_body = function(args, mime)
      check_phase(access_and_rewrite)

      if type(args) ~= "table" then
        error("args must be a table", 2)
      end
      if mime and type(mime) ~= "string" then
        error("mime must be a string", 2)
      end
      if not mime then
        mime = ngx.req.get_headers()[CONTENT_TYPE]
        if not mime then
          return nil, "content type was neither explicitly given " ..
                      "as an argument or received as a header"
        end
      end

      local boundaryless_mime = mime
      local s = string_find(mime, ";", 1, true)
      if s then
        boundaryless_mime = string_sub(mime, 1, s - 1)
      end

      local handler_fn = set_body_handlers[boundaryless_mime]
      if not handler_fn then
        error("unsupported content type " .. mime, 2)
      end

      -- Ensure client request body has been read.
      -- This function is a nop if body has already been read,
      -- and necessary to write the request to the service if it has not.
      ngx.req.read_body()

      local body, content_type = handler_fn(args, mime)

      ngx.req.set_body_data(body)
      ngx.req.set_header(CONTENT_TYPE, content_type)

      return true
    end

  end

  return request
end


return {
  new = new,
}
