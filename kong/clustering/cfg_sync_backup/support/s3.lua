local AWS = require("resty.aws")
local AWS_config = require("resty.aws.config")
local xml = require("pl.xml")
local xml_parse = xml.parse
local s3_instance
local re_match = ngx.re.match

local _M = {}

local empty = {}
local function endpoint_settings(config)
    local endpoint = config.third_party_endpoint or os.getenv("AWS_THIRD_PARTY_ENDPOINT")
    if endpoint then
        local m = assert(re_match(endpoint, [[^(?:(https?):\/\/)?([^:]+)(?::(\d+))?$]], "jo"), "invalid endpoint")
        local scheme = m[1] or "https"
        local tls = scheme == "https"
        return {
            scheme = scheme,
            tls = tls,
            endpoint = m[3],
            port = tonumber(m[2]) or (tls and 443 or 80),
        }
    else
        return empty
    end
end

function _M.init_worker()
    local global_config = AWS_config.global
    local aws_instance = assert(AWS(global_config))
    s3_instance = assert(aws_instance(endpoint_settings(global_config)))
end

function _M.new(gateway_version, plugin_version_hash, url)
    local self = {
        url = url,
        gateway_version = gateway_version,
        plugin_version_hash = plugin_version_hash,
    }
    local m = assert(re_match(url, [[^s3:\/\/([^\/]+)\/(.+)$]], "jo"), "invalid S3 URL")
    self.bucket = m[1]
    self.key = m[2] .. "/" .. gateway_version .. "/" .. plugin_version_hash .. ".json"
    return setmetatable(self, { __index = _M })
end

function _M:backup_config(config, config_hash)
    local res, err = s3_instance:putObject{
        Bucket = self.bucket,
        Key = self.key,
        Body = config,
        Metadata = {
            config_hash = config_hash,
        },
        ContentType = "application/json",
    }

    if not res then
        return nil, err
    end

    if not res.status == 200 then
        return nil, xml_parse(res.body, nil, true):child_with_name("Message")
    end
end

function _M:fetch_config()
    local res, err = s3_instance:getObject{
        Bucket = self.bucket,
        Key = self.key,
    }

    if not res then
        return nil, err
    end

    if not res.status == 200 then
        return nil, xml_parse(res.body, nil, true):child_with_name("Message")
    end

    return res.body, res.headers["x-amz-meta-config-hash"]
end

return _M