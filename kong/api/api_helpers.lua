local utils = require "kong.tools.utils"
local cjson = require "cjson"
local pl_pretty = require "pl.pretty"
local tablex = require "pl.tablex"
local app_helpers = require "lapis.application"
local arguments = require "kong.api.arguments"
local Errors = require "kong.db.errors"
local singletons = require "kong.singletons"

local ngx      = ngx
local sub      = string.sub
local find     = string.find
local type     = type
local pairs    = pairs
local ipairs   = ipairs

local _M = {}
local NO_ARRAY_INDEX_MARK = {}

-- Parses a form value, handling multipart/data values
-- @param `v` The value object
-- @return The parsed value
local function parse_value(v)
  return type(v) == "table" and v.content or v -- Handle multipart
end


-- given a string like "x[1].y", return an array of indices like {"x", 1, "y"}
-- the path parameter is an output-only param. the keys are added to it in order
local function key_to_path(key, path)
  -- try to match an array access like x[1].
  -- the left side of the [] is mandatory
  -- the array index can be omitted (the key will look like x[]).
  -- if that's the case we mark the path entry with a special key
  local left, array_index = key:match("^(.+)%[(%d*)]$")
  if left then
    key_to_path(left, path)
    path[#path + 1] = tonumber(array_index) or NO_ARRAY_INDEX_MARK
    return path
  end

  -- if no match, try a hash access like x.y (both x and y are mandatory)
  -- the left side of the dot is called left and the other side is right
  local left, right = key:match("^(.+)%.(.+)$")
  if left then
    key_to_path(left, path)
    key_to_path(right, path)
    return path
  end

  -- if no match found, append the whole key to the path as a single string
  path[#path + 1] = key
  return path
end

-- when NO_ARRAY_INDEX is encountered, replace it with the length of the node being parsed
local function transform_no_array_index_mark(path_entry, node)
  if path_entry == NO_ARRAY_INDEX_MARK then
    return #node + 1
  end
  return path_entry
end


-- Put nested keys in objects:
-- Normalize dotted keys in objects.
-- Example: {["key.value.sub"]=1234} becomes {key = {value = {sub=1234}}
-- @param `obj` Object to normalize
-- @return `normalized_object`
function _M.normalize_nested_params(obj)
  local new_obj = {}
  local is_array

  for k, v in pairs(obj) do
    is_array = false
    if type(v) == "table" then
      -- normalize arrays since Lapis parses ?key[1]=foo as {["1"]="foo"} instead of {"foo"}
      if utils.is_array(v) then
        is_array = true
        local arr = {}
        for _, arr_v in pairs(v) do arr[#arr+1] = arr_v end
        v = arr
      else
        v = _M.normalize_nested_params(v) -- recursive call on other table values
      end
    end

    v = parse_value(v)

    -- normalize sub-keys with hash or array accesses
    if type(k) == "string" then
      local path = key_to_path(k, {})
      local path_len = #path
      local node = new_obj
      local prev = new_obj
      local path_entry
      -- create any missing tables when dealing with x.foo[1].y = "bar"
      for i = 1, path_len - 1 do
        path_entry = transform_no_array_index_mark(path[i], node)
        node[path_entry] = node[path_entry] or {}
        prev = node
        node = node[path_entry]
      end

      -- on the last item of the path (the "y" in the example above)
      if path[path_len] == NO_ARRAY_INDEX_MARK and is_array then
        -- edge case: we are assigning an array to a no-array index mark: x[] = {1,2,3}
        -- on this case we backtrack one element (we use `prev` instead of `node`)
        -- and we set it to the array (v)
        -- this edge case is needed because Lapis builds params like that (flatten_params function)
        prev[path_entry or k] = v
      elseif type(node) == "table" then
        -- regular case: the last element is similar to the loop iteration.
        -- instead of a table, we set the value (v) on the last element
        node[transform_no_array_index_mark(path[path_len], node)] = v
      end
    else
      new_obj[k] = v -- nothing special with that key, simply attaching the value
    end
  end

  return new_obj
end


-- Remove functions from a schema definition so that
-- cjson can encode the schema.
local schema_to_jsonable
do
  local insert = table.insert
  local ipairs = ipairs
  local next = next

  local fdata_to_jsonable


  local function fields_to_jsonable(fields)
    local out = {}
    for _, field in ipairs(fields) do
      local fname = next(field)
      local fdata = field[fname]
      insert(out, { [fname] = fdata_to_jsonable(fdata, "no") })
    end
    setmetatable(out, cjson.array_mt)
    return out
  end


  -- Convert field data from schemas into something that can be
  -- passed to a JSON encoder.
  -- @tparam table fdata A Lua table with field data
  -- @tparam string is_array A three-state enum: "yes", "no" or "maybe"
  -- @treturn table A JSON-convertible Lua table
  fdata_to_jsonable = function(fdata, is_array)
    local out = {}
    local iter = is_array == "yes" and ipairs or pairs

    for k, v in iter(fdata) do
      if is_array == "maybe" and type(k) ~= "number" then
        is_array = "no"
      end

      if k == "schema" then
        out[k] = schema_to_jsonable(v)

      elseif type(v) == "table" then
        if k == "fields" and fdata.type == "record" then
          out[k] = fields_to_jsonable(v)

        elseif k == "default" and fdata.type == "array" then
          out[k] = fdata_to_jsonable(v, "yes")

        else
          out[k] = fdata_to_jsonable(v, "maybe")
        end

      elseif type(v) == "number" then
        if v ~= v then
          out[k] = "nan"
        elseif v == math.huge then
          out[k] = "inf"
        elseif v == -math.huge then
          out[k] = "-inf"
        else
          out[k] = v
        end

      elseif type(v) ~= "function" then
        out[k] = v
      end
    end
    if is_array == "yes" or is_array == "maybe" then
      setmetatable(out, cjson.array_mt)
    end
    return out
  end


  schema_to_jsonable = function(schema)
    local fields = fields_to_jsonable(schema.fields)
    return { fields = fields }
  end
  _M.schema_to_jsonable = schema_to_jsonable
end


local NEEDS_BODY = tablex.readonly({ PUT = 1, POST = 2, PATCH = 3 })


function _M.before_filter(self)
  if not NEEDS_BODY[ngx.req.get_method()] then
    return
  end

  local content_type = self.req.headers["content-type"]
  if not content_type then
    local content_length = self.req.headers["content-length"]
    if content_length == "0" then
      return
    end

    if not content_length then
      local _, err = ngx.req.socket()
      if err == "no body" then
        return
      end
    end

  elseif sub(content_type, 1, 16) == "application/json"                  or
         sub(content_type, 1, 19) == "multipart/form-data"               or
         sub(content_type, 1, 33) == "application/x-www-form-urlencoded" then
    return
  end

  return kong.response.exit(415)
end


local function parse_params(fn)
  return app_helpers.json_params(function(self, ...)
    if NEEDS_BODY[ngx.req.get_method()] then
      local content_type = self.req.headers["content-type"]
      if content_type then
        content_type = content_type:lower()

        if find(content_type, "application/json", 1, true) and not self.json then
          return kong.response.exit(400, { message = "Cannot parse JSON body" })

        elseif find(content_type, "application/x-www-form-urlencode", 1, true) then
          self.params = utils.decode_args(self.params)
        end
      end
    end

    self.params = _M.normalize_nested_params(self.params)

    local res, err = fn(self, ...)

    if err then
      kong.log.err(err)
      return ngx.exit(500)
    end

    if res == nil and ngx.status >= 200 then
      return ngx.exit(0)
    end

    return res
  end)
end


-- new DB
local function new_db_on_error(self)
  local err = self.errors[1]

  if type(err) ~= "table" then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if err.strategy then
    err.strategy = nil
  end

  if err.code == Errors.codes.SCHEMA_VIOLATION
  or err.code == Errors.codes.INVALID_PRIMARY_KEY
  or err.code == Errors.codes.FOREIGN_KEY_VIOLATION
  or err.code == Errors.codes.INVALID_OFFSET
  or err.code == Errors.codes.FOREIGN_KEYS_UNRESOLVED
  then
    return kong.response.exit(400, err)
  end

  if err.code == Errors.codes.NOT_FOUND then
    return kong.response.exit(404, err)
  end

  if err.code == Errors.codes.OPERATION_UNSUPPORTED then
    kong.log.err(err)
    return kong.response.exit(405, err)
  end

  if err.code == Errors.codes.PRIMARY_KEY_VIOLATION
  or err.code == Errors.codes.UNIQUE_VIOLATION
  then
    return kong.response.exit(409, err)
  end

  kong.log.err(err)
  return kong.response.exit(500, { message = "An unexpected error occurred" })
end


-- old DAO
local function on_error(self)
  local err = self.errors[1]

  if type(err) ~= "table" then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if err.name then
    return new_db_on_error(self)
  end

  if err.db then
    kong.log.err(err.message)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if err.unique then
    return kong.response.exit(409, err.tbl)
  end

  if err.foreign then
    return kong.response.exit(404, err.tbl or { message = "Not found" })
  end

  return kong.response.exit(400, err.tbl or err.message)
end


local handler_helpers = {
  yield_error = app_helpers.yield_error
}


function _M.attach_routes(app, routes)
  for route_path, methods in pairs(routes) do
    methods.on_error = methods.on_error or on_error

    for method_name, method_handler in pairs(methods) do
      local wrapped_handler = function(self)
        return method_handler(self, {}, handler_helpers)
      end

      methods[method_name] = parse_params(wrapped_handler)
    end

    app:match(route_path, route_path, app_helpers.respond_to(methods))
  end
end


function _M.attach_new_db_routes(app, routes)
  for route_path, definition in pairs(routes) do
    local schema  = definition.schema
    local methods = definition.methods

    methods.on_error = methods.on_error or new_db_on_error

    for method_name, method_handler in pairs(methods) do
      local wrapped_handler = function(self)
        self.args = arguments.load({
          schema  = schema,
          request = self.req,
        })

        return method_handler(self, singletons.db, handler_helpers)
      end

      methods[method_name] = parse_params(wrapped_handler)
    end

    app:match(route_path, route_path, app_helpers.respond_to(methods))
  end
end


function _M.default_route(self)
  local path = self.req.parsed_url.path:match("^(.*)/$")

  if path and self.app.router:resolve(path, self) then
    return

  elseif self.app.router:resolve(self.req.parsed_url.path .. "/", self) then
    return
  end

  return self.app.handle_404(self)
end



function _M.handle_404(self)
  return kong.response.exit(404, { message = "Not found" })
end


function _M.handle_error(self, err, trace)
  if err then
    if type(err) ~= "string" then
      err = pl_pretty.write(err)
    end
    if find(err, "don't know how to respond to", nil, true) then
      return kong.response.exit(405, { message = "Method not allowed" })
    end
  end

  ngx.log(ngx.ERR, err, "\n", trace)

  -- We just logged the error so no need to give it to responses and log it
  -- twice
  return kong.response.exit(500, { message = "An unexpected error occurred" })
end


return _M
