local ngx = ngx
local kong = kong
local ipairs = ipairs
local null = ngx.null
local string_format = string.format


local function each_service(entity)
  local options = {
    workspace = null,
  }

  local iter = entity:each(1000, options)
  local function iterator()
    local element, err = iter()
    if err then return nil, err end
    if element == nil then return end
    if element.ca_certificates and #element.ca_certificates > 0 then return element, nil end
    return iterator()
  end

  return iterator
end


local function verify_references(id)
  -- services
  for service, err in each_service(kong.db.services) do
    if err then
      kong.log.err("could not load services: ", err)
      return
    end

    for _, v in ipairs(service.ca_certificates) do
      if v == id then
        kong.log.notice(string_format("ca_certificate: %s is still referenced from service: %s", id, service.id))

        return kong.response.exit(400, {
          name = "foreign key violation",
          fields = { ["@referenced_by"] = "services" },
          message = "an existing 'services' entity references this 'ca_certificates' entity"
        })
      end
    end
  end
end

return {
  ["/ca_certificates/:ca_certificates"] = {
    DELETE = function(self, db, helpers, parent)
      verify_references(self.params.ca_certificates)

      return parent()
    end,
  },
}
