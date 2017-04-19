local stringy = require "stringy"
local responses = require "kong.tools.responses"
local xml_validator = require "kong.plugins.xml-threat-protection.xml_validator"
local BasePlugin = require "kong.plugins.base_plugin"

local XmlTheatProtectionHandler = BasePlugin:extend()

XmlTheatProtectionHandler.PRIORITY = 500

---------------
-- Constants --
---------------

local APPLICATION_XML = "application/xml"
local CONTENT_TYPE = "content-type"

----------------------
-- Utility function --
----------------------

local function get_content_type()
    local header_value = ngx.req.get_headers()[CONTENT_TYPE]
    if header_value then
        return stringy.strip(header_value):lower()
    end
    return nil
end

---------------------------
-- Plugin implementation --
---------------------------

function XmlTheatProtectionHandler:new()
    XmlTheatProtectionHandler.super.new(self, "XML Threat Protection")
end

function XmlTheatProtectionHandler:access(config)
    XmlTheatProtectionHandler.super.access(self)

    local is_xml = stringy.startswith(get_content_type(), APPLICATION_XML)
    if is_xml then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()

        if not body then
            return responses.send_OK()
        end

        local result, message = xml_validator.execute(body,
            config.name_limits_element,
            config.name_limits_attribute,
            config.name_limits_namespace_prefix,
            config.name_limits_processing_instruction_target,
            config.structure_limits_node_depth,
            config.structure_limits_attribute_count_per_element,
            config.structure_limits_namespace_count_per_element,
            config.structure_limits_child_count,
            config.value_limits_text,
            config.value_limits_attribute,
            config.value_limits_namespace_uri,
            config.value_limits_comment,
            config.value_limits_processing_instruction_data)

        if result == true then
            return responses.send_HTTP_OK()
        else
            return responses.send_HTTP_BAD_REQUEST(message)
        end
    end

    return responses.send_HTTP_OK()
end

return XmlTheatProtectionHandler

