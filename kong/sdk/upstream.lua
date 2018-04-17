local cjson = require "cjson.safe"
local multipart = require "multipart"


local ngx = ngx


--------------------------------------------------------------------------------
-- Produce a lexicographically ordered querystring, given a table of values.
--
-- @param args A table where keys are strings and values are strings, booleans,
-- or an array of strings or booleans.
-- @return an URL-encoded query string, or nil and an error message
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

    table.insert(out, s)
    t[k] = nil
  end
  table.sort(out)
  return table.concat(out, "&")
end


-- The upstream request module: functions for dealing with data to be sent
-- to the upstream service, i.e. for connections made by Kong.
local function new(sdk, upstream, major_version)


  -- TODO these constants should be shared with kong.sdk.request

  local CONTENT_TYPE           = "Content-Type"

  local CONTENT_TYPE_POST      = "application/x-www-form-urlencoded"
  local CONTENT_TYPE_JSON      = "application/json"
  local CONTENT_TYPE_FORM_DATA = "multipart/form-data"


  ------------------------------------------------------------------------------
  -- Sets the protocol to use when proxying the request to the
  -- upstream service.
  --
  -- @param scheme Protocol to use. Supported values are `"http"` and `"https"`.
  -- @return `true` if successful, or nil and an error string.
  upstream.set_scheme = function(scheme)
    if type(scheme) ~= "string" then
      error("scheme must be a string", 2)
    end

    if scheme ~= "http" and scheme ~= "https" then
      return nil, "invalid scheme: " .. scheme
    end

    ngx.var.upstream_scheme = scheme

    return true
  end


  ------------------------------------------------------------------------------
  -- Sets the target host for the upstream service to which Kong will
  -- proxy the request. The `Host` header is also set accordingly.
  --
  -- @param host Host name to set. Example: "example.com"
  -- @return `true` if successful, or nil and an error string.
  upstream.set_host = function(host)
    if type(host) ~= "string" then
      error("host must be a string", 2)
    end

    ngx.req.set_header("Host", host)
    ngx.var.upstream_host = host
    ngx.ctx.balancer_address.host = host

    return true
  end


  ------------------------------------------------------------------------------
  -- Sets the target port for the upstream service to which Kong will
  -- proxy the request.
  --
  -- @param port A port number between 0 and 65535.
  -- @return `true` if successful, or nil and an error string.
  upstream.set_port = function(port)
    if type(port) ~= "number" or math.floor(port) ~= port then
      error("port must be an integer", 2)
    end

    if port < 0 or port > 65535 then
      return nil, "port must be an integer between 0 and 65535: given " .. port
    end

    ngx.ctx.balancer_address.port = port

    return true
  end


  ------------------------------------------------------------------------------
  -- Sets the path component for the upstream request. It is not normalized in
  -- any way and should not include the querystring.
  --
  -- @param path The path string. Example: "/v2/movies"
  -- @return `true` if successful, or nil and an error string.
  upstream.set_path = function(path)
    if type(path) ~= "string" then
      error("path must be a string", 2)
    end

    if path:sub(1,1) ~= "/" then
      return nil, "path must start with /"
    end

    -- TODO: is this necessary in specific phases?
    -- ngx.req.set_uri(path)
    ngx.var.upstream_uri = path

    return true
  end


  ------------------------------------------------------------------------------
  -- Sets the querystring for the upstream request. Input argument is a
  -- raw string that is not processed in any way.
  --
  -- For a higher-level function for setting the query string from a Lua table
  -- of arguments, see `kong.upstream.set_query_args`.
  --
  -- @param query The raw querystring. Example: "foo=bar&bla&baz=hello%20world"
  -- @return `true` if successful, or nil and an error string.
  upstream.set_query = function(query)
    if type(query) ~= "string" then
      error("query must be a string", 2)
    end

    ngx.req.set_uri_args(query)

    return true
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


    ----------------------------------------------------------------------------
    -- Sets the HTTP method for the request that Kong will make to
    -- the upstream service.
    --
    -- @param method The method string, which should be given in all
    -- uppercase. Supported values are: `"GET"`, `"HEAD"`, `"PUT"`, `"POST"`,
    -- `"DELETE"`, `"OPTIONS"`, `"MKCOL"`, `"COPY"`, `"MOVE"`, `"PROPFIND"`,
    -- `"PROPPATCH"`, `"LOCK"`, `"UNLOCK"`, `"PATCH"`, `"TRACE"`.
    -- @return `true` on success or `nil` followed by an error message
    -- in case of an unsupported method string.
    upstream.set_method = function(method)
      if type(method) ~= "string" then
        error("method must be a string", 2)
      end

      local method_id = accepted_methods[method]
      if not method_id then
        return nil, "invalid method: " .. method
      end

      ngx.req.set_method(method_id)

      return true
    end
  end


  ------------------------------------------------------------------------------
  -- Defines a `application/x-www-form-urlencoded` body with a table of
  -- arguments for a POST request.
  --
  -- Keys are produced in lexicographical order. The order of entries within the
  -- same key (when values are given as an array) is retained.
  --
  -- @param args A table where each key is a string (corresponding to an
  -- argument name), and each value is either a boolean, a string or an array of
  -- strings or booleans. Any string values given are URL-encoded.
  -- @return `true` on success or nil followed by an error message in case of
  -- errors.
  upstream.set_post_args = function(args)
    if type(args) ~= "table" then
      error("args must be a table", 2)
    end

    local querystring, err = make_ordered_args(args)
    if not querystring then
      error(err, 2) -- type error inside the table
    end

    ngx.req.read_body()
    ngx.req.set_body_data(querystring)
    ngx.req.set_header(CONTENT_TYPE, CONTENT_TYPE_POST)

    return true
  end


  ------------------------------------------------------------------------------
  -- Defines a query string for the upstream request, given a table of
  -- arguments.
  --
  -- Keys are produced in lexicographical order. The order of entries within the
  -- same key (when values are given as an array) is retained.
  --
  -- If further control of the querystring generation is needed, a raw
  -- querystring can be given as a string with `kong.upstream.set_query`.
  --
  -- @param args A table where each key is a string (corresponding to an
  -- argument name), and each value is either a boolean, a string or an array of
  -- strings or booleans. Any string values given are URL-encoded.
  -- @return `true` on success or nil followed by an error message in case of
  -- errors.
  upstream.set_query_args = function(args)
    if type(args) ~= "table" then
      error("args must be a table", 2)
    end

    local querystring, err = make_ordered_args(args)
    if not querystring then
      error(err, 2) -- type error inside the table
    end

    ngx.req.set_uri_args(querystring)

    return true
  end


  ------------------------------------------------------------------------------
  -- Sets a request header to the given value. It overrides any existing ones:
  -- if one or more headers are already set with header name, they are removed.
  --
  -- The `Host` header has special treatment internally, and setting it is
  -- equivalent to calling `kong.upstream.set_host`.
  --
  -- @param header The header name. Example: "X-Foo"
  -- @param value The header value. Example: "hello world"
  -- @return `true` on success or nil followed by an error message in case of
  -- errors.
  upstream.set_header = function(header, value)
    if type(header) ~= "string" then
      error("header must be a string", 2)
    end
    if type(value) ~= "string" then
      error("value must be a string", 2)
    end

    if header:lower() == "host" then
      return upstream.set_host(value)
    end

    ngx.req.set_header(header, value ~= "" and value or " ")

    return true
  end


  ------------------------------------------------------------------------------
  -- Adds a request header with the given value to the upstream request, without
  -- removing any existing headers with the same name. The order in which
  -- headers are added is retained.
  --
  -- The Host header is treated in a special way, and behaves the same as
  -- `upstream.set_host`.
  --
  -- @param header The header name. Example: "Cache-Control"
  -- @param value The header value. Example: "no-cache"
  -- @return `true` on success or nil followed by an error message in case of
  -- errors.
  upstream.add_header = function(header, value)
    if type(header) ~= "string" then
      error("header must be a string", 2)
    end
    if type(value) ~= "string" then
      error("value must be a string", 2)
    end

    if header:lower() == "host" then
      return upstream.set_host(value)
    end

    local headers = ngx.req.get_headers()[header]
    if type(headers) ~= "table" then
      headers = { headers }
    end

    table.insert(headers, value ~= "" and value or " ")

    ngx.req.set_header(header, headers)

    return true
  end


  ------------------------------------------------------------------------------
  -- Removes any occurrences of the given header.
  --
  -- @param header The header name. Example: "X-Foo"
  -- @return `true` on no errors, or nil followed by an error message in case of
  -- errors. It will return `true` even if no header was removed.
  upstream.clear_header = function(header)
    if type(header) ~= "string" then
      error("header must be a string", 2)
    end

    ngx.req.clear_header(header)

    return true
  end


  ------------------------------------------------------------------------------
  -- Sets multiple headers at once.
  --
  -- Headers are produced in lexicographical order. The order of entries within
  -- the same header (when values are given as an array) is retained.
  --
  -- It overrides any existing headers for the given keys: if one or more
  -- headers are already set with a header name, they are removed. Headers that
  -- are not referenced as keys of the `headers` table remain untouched.
  --
  -- The `Host` header has special treatment internally, and setting it is
  -- equivalent to calling `kong.upstream.set_host`.
  --
  -- If further control on the order of headers is needed, these should be
  -- added one by one using `kong.upstream.set_header` and
  -- `kong.upstream.add_header`.
  --
  -- @param headers A table where each key is a string containing a header name
  -- and each value is either a string or an array of strings.
  -- @return `true` on success or `nil` followed by an error message in case of
  -- errors.
  upstream.set_headers = function(headers)
    if type(headers) ~= "table" then
      error("headers must be a table", 2)
    end

    -- Check for type errors first

    for k, v in pairs(headers) do
      local typek = type(k)
      if typek ~= "string" then
        return nil, ("invalid key %q: got %s, expected string"):format(k, typek)
      end

      local typev = type(v)

      if typev == "table" then

        for _, vv in ipairs(v) do
          local typevv = type(vv)
          if typevv ~= "string" then
            return nil, ("invalid value in array %q: got %s, " ..
                         "expected string"):format(k, typevv)
          end
        end

      elseif typev ~= "string" then

        return nil, ("invalid value in %q: got %s, " ..
                     "expected string"):format(k, typev)
      end
    end

    -- Now we can use ngx.req.set_header without pcall

    for k, v in pairs(headers) do
      if k:lower() == "host" then
        upstream.set_host(v)
      else
        ngx.req.set_header(k, v ~= "" and v or " ")
      end
    end

    return true
  end


  ------------------------------------------------------------------------------
  -- Sets the raw body for the upstream request. Input argument is a
  -- raw string that is not processed in any way. Sets the `Content-Length`
  -- header appropriately. To set an empty body, use an empty string (`""`).
  --
  -- For a higher-level function for setting the body based on the request
  -- content type, see `kong.upstream.set_body_args`.
  --
  -- @param body The raw body, as a string.
  -- @return `true` on success or `nil` followed by an error message in case of
  -- errors.
  upstream.set_body = function(body)
    if type(body) ~= "string" then
      error("body must be a string", 2)
    end

    -- TODO Can we get the body size limit configured for Kong and check for
    -- length based on that, and fail gracefully before attempting to set
    -- the body?

    ngx.req.read_body()
    ngx.req.set_body_data(body)

    return true
  end


  do
    local set_body_args_handlers = {

      [CONTENT_TYPE_POST] = upstream.set_post_args,

      [CONTENT_TYPE_JSON] = function(args)
        local encoded, err = cjson.encode(args)
        if not encoded then
          return nil, err
        end

        ngx.req.set_body_data(encoded)
        ngx.req.set_header(CONTENT_TYPE, CONTENT_TYPE_JSON)
        return true
      end,

      [CONTENT_TYPE_FORM_DATA] = function(args)
        local data = multipart()

        local keys = {}
        local i = 1
        for k, v in pairs(args) do
          if type(k) ~= "string" then
            return nil, ("invalid key %q: got %s, " ..
                         "expected string"):format(k, type(k))
          end
          if type(v) ~= "string" then
            return nil, ("invalid value %q: got %s, " ..
                         "expected string"):format(k, type(v))
          end
          keys[i] = k
          i = i + 1
        end

        table.sort(keys)

        for _, k in pairs(keys) do
          local v = args[k]
          data:set_simple(k, v)
        end

        local encoded = data:tostring()

        ngx.req.set_body_data(encoded)
        ngx.req.set_header(CONTENT_TYPE, CONTENT_TYPE_FORM_DATA)
        return true
      end,

    }

    ----------------------------------------------------------------------------
    -- Sets the body for the upstream request, encoding it based on the
    -- `mimetype` argument (or the `Content-Type` header of the request
    -- if the `mimetype` argument is not given).
    --
    -- * if the request content type is `application/x-www-form-urlencoded`:
    --   * encodes the form arguments (same as `kong.upstream.set_post_args()`)
    -- * if the request content type is `multipart/form-data`:
    --   * encodes the multipart form data
    -- * if the request content type is `application/json`:
    --   * encodes the request as JSON
    --     (same as `kong.upstream.set_body(json.encode(args))`)
    --   * JSON types are converted to matching Lua types
    -- * If none of the above, it returns `nil` and an error message.
    --
    -- If further control of the body generation is needed, a raw body
    -- can be given as a string with `kong.upstream.set_body`.
    --
    -- @param args a table with data to be converted to the appropriate format
    -- and stored in the body.
    -- @param mime if given, it should be in the same format as the
    -- value returned by `kong.request.get_body_args`. The `Content-Type` header
    -- will be updated to match the appropriate type.
    -- @return `true` on success or `nil` followed by an error message in case of
    -- errors.
    upstream.set_body_args = function(args, mime)
      if type(args) ~= "table" then
        error("args must be a table", 2)
      end
      if mime and type(mime) ~= "string" then
        error("mime must be a string", 2)
      end

      ngx.req.read_body()

      if not mime then
        mime = ngx.req.get_headers()[CONTENT_TYPE]
        local s = mime:find(";", 1, true)
        if s then
          mime = mime:sub(1, s - 1)
        end
      end

      local set_body_fn = set_body_args_handlers[mime]
      if not set_body_fn then
        return nil, "unsupported content type " .. mime
      end

      return set_body_fn(args)
    end
  end

end


return {
  namespace = "upstream",
  new = new,
}
