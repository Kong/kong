local stringy = require "stringy"
local responses = require "kong.tools.responses"
local json_validator = require "kong.plugins.json-threat-protection.json_validator"
local BasePlugin = require "kong.plugins.base_plugin"

local JsonThreatProtectionHandler = BasePlugin:extend()

JsonThreatProtectionHandler.PRIORITY = 500

---------------
-- Constants --
---------------

local APPLICATION_JSON = "application/json"
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

function JsonThreatProtectionHandler:new()
    JsonThreatProtectionHandler.super.new(self, "JSON Threat Protection")
end

function JsonThreatProtectionHandler:access(config)
    JsonThreatProtectionHandler.super.access(self)

    local is_json = stringy.startswith(get_content_type(), APPLICATION_JSON)
    if is_json then
        ngx.req.read_body()
        local body = ngx.req.get_body_data()

        if not body then
            return responses.send_OK()
        end

        local result, message = json_validator.execute(body, config.container_depth, config.array_element_count, config.object_entry_count, config.object_entry_name_length, config.string_value_length)
        if result == true then
            return responses.send_HTTP_OK()
        else
            return responses.send_HTTP_BAD_REQUEST(message)
        end
    end

    return responses.send_HTTP_OK()
end

return JsonThreatProtectionHandler

