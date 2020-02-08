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
local preread_and_balancer = phase_checker.new(PHASES.preread, PHASES.balancer)


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


  ---
  -- Enables buffered proxying that allows plugins to access service body and
  -- response headers at the same time
  -- @function kong.service.request.enable_buffering
  -- @phases `rewrite`, `access`
  -- @return Nothing
  -- @usage
  -- kong.service.request.enable_buffering()
  request.enable_buffering = function()
    check_phase(access_and_rewrite)

    if ngx.req.http_version() >= 2 then
      error("buffered proxying cannot currently be enabled with http/" ..
            ngx.req.http_version() .. ", please use http/1.x instead", 2)
    end


    self.ctx.core.buffered_proxying = true
  end

  ---
  -- Sets the protocol to use when proxying the request to the Service.
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
    -- Sets the HTTP method for the request to the service.
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


  if ngx.config.subsystem == "stream" then
    local disable_proxy_ssl = require("resty.kong.tls").disable_proxy_ssl

    ---
    -- Disables the TLS handshake to upstream for [ngx\_stream\_proxy\_module](https://nginx.org/en/docs/stream/ngx_stream_proxy_module.html).
    -- Effectively this overrides [proxy\_ssl](https://nginx.org/en/docs/stream/ngx_stream_proxy_module.html#proxy_ssl) directive to `off` setting
    -- for the current stream session.
    --
    -- Note that once this function has been called it is not possible to re-enable TLS handshake for the current session.
    --
    -- @function kong.service.request.disable_tls
    -- @phases `preread`, `balancer`
    -- @treturn boolean|nil `true` if the operation succeeded, `nil` if an error occurred
    -- @treturn string|nil An error message describing the error if there was one.
    -- @usage
    -- local ok, err = kong.service.request.disable_tls()
    -- if not ok then
    --   -- do something with error
    -- end
    request.disable_tls = function()
      check_phase(preread_and_balancer)

      return disable_proxy_ssl()
    end
  end

  return request
end


return {
  new = new,
}
