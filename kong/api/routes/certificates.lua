local endpoints   = require "kong.api.endpoints"
local arguments   = require "kong.api.arguments"
local utils       = require "kong.tools.utils"


local ngx = ngx
local kong = kong
local type = type
local find = string.find
local lower = string.lower
local unescape_uri = ngx.unescape_uri


local function prepare_params(self)
  local id = unescape_uri(self.params.certificates)
  local method = self.req.method
  local name
  if not utils.is_valid_uuid(id) then
    name = arguments.infer_value(id, kong.db.snis.schema.fields.name)

    local sni, _, err_t = kong.db.snis:select_by_name(name)
    if err_t then
      return endpoints.handle_error(err_t)
    end

    if sni then
      id = sni.certificate.id

    else
      if method ~= "PUT" then
        return kong.response.exit(404, { message = "SNI not found" })
      end

      id = utils.uuid()
    end
  end

  self.params.certificates = id
  self.params.name = name
end


local function prepare_args(self)
  local infer_snis
  do
    local content_type = ngx.var.content_type
    if content_type then
      content_type = lower(content_type)

      if find(content_type, "application/x-www-form-urlencoded", 1, true) == 1
      or find(content_type, "multipart/form-data",               1, true) == 1
      then
        infer_snis = true
      end
    end
  end

  local method = self.req.method

  local snis = self.args.post.snis
  local name = self.params.name

  if type(snis) == "table" then
    local found
    local count = #snis
    for i=1, count do
      if infer_snis then
        snis[i] = arguments.infer_value(snis[i], kong.db.snis.schema.fields.name)
      end

      if not found and name and name == snis[i] then
        found = true
      end
    end

    if not found and name and method == "PUT" then
      snis[count + 1] = name
    end

  elseif type(snis) == "string" then
    if infer_snis then
      snis = arguments.infer_value(snis, kong.db.snis.schema.fields.name)
    end

    if name and method == "PUT" and name ~= snis then
      snis = { snis, name }
    else
      snis = { snis }
    end
  end

  if not snis and method == "PUT" then
    snis = ngx.null
  end

  self.params.name = nil
  self.args.post.snis = snis
end


return {
  ["/certificates/:certificates"] = {
    before = prepare_params,

    -- override to include the snis list when getting an individual certificate
    GET = endpoints.get_entity_endpoint(kong.db.certificates.schema,
                                        nil, nil, "select_with_name_list"),

    PUT = function(self, _, _, parent)
      prepare_args(self)
      return parent()
    end,

    PATCH = function(self, _, _, parent)
      prepare_args(self)
      return parent()
    end
  },

  ["/certificates/:certificates/snis"] = {
    before = prepare_params,
  },

  ["/certificates/:certificates/snis/:snis"] = {
    before = prepare_params,
  },
}

