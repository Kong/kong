local client = require "kong.plugins.acme.client"
local handler = require "kong.plugins.acme.handler"
local http = require "resty.http"

local x509 = require "resty.openssl.x509"

local function find_plugin()
  for plugin, err in kong.db.plugins:each(1000) do
    if err then
      return nil, err
    end

    if plugin.name == "acme" then
      return plugin
    end
  end
end

local function to_hex(s)
  s = s:gsub("(.)", function(s) return string.format("%02X:", string.byte(s)) end)
  -- strip last ":"
  return string.sub(s, 1, #s-1)
end

local function bn_to_hex(bn)
  local s = bn:to_hex():gsub("(..)", function (s) return s..":" end)
  -- strip last ":"
  return string.sub(s, 1, #s-1)
end

local function parse_certkey(certkey)
  local cert = x509.new(certkey.cert)
  local key = cert:get_pubkey()

  local subject_name = cert:get_subject_name()
  local host = subject_name:find("CN")
  local issuer_name = cert:get_issuer_name()
  local issuer_cn = issuer_name:find("CN")

  return {
    digest = to_hex(cert:digest()),
    host = host.blob,
    issuer_cn = issuer_cn.blob,
    not_before = os.date("%Y-%m-%d %H:%M:%S", cert:get_not_before()),
    not_after = os.date("%Y-%m-%d %H:%M:%S", cert:get_not_after()),
    valid = cert:get_not_before() < ngx.time() and cert:get_not_after() > ngx.time(),
    serial_number = bn_to_hex(cert:get_serial_number()),
    pubkey_type = key:get_key_type().sn,
  }
end

return {
  ["/acme"] = {
    POST = function(self)
      local plugin, err = find_plugin()
      if err then
        return kong.response.exit(500, { message = err })
      elseif not plugin then
        return kong.response.exit(404)
      end
      local conf = plugin.config

      local host = self.params.host
      if not host or type(host) ~= "string" then
        return kong.response.exit(400, { message = "host must be provided and containing a single domain" })
      end

      -- we don't allow port for security reason in test_only mode
      if string.find(host, ":") ~= nil then
        return kong.response.exit(400, { message = "port is not allowed in host" })
      end

      -- string "true" automatically becomes boolean true from lapis
      if self.params.test_http_challenge_flow == true then
        local domains_matcher = handler.build_domain_matcher(conf.domains)
        if not domains_matcher or not domains_matcher[host] then
          return kong.response.exit(400, { message = "problem found running sanity check for " .. host ..
                ": host is not included in plugin config.domains"})
        end

        local check_path = string.format("http://%s/.well-known/acme-challenge/", host)
        local httpc = http.new()
        local res, err = httpc:request_uri(check_path .. "x")
        if not err then
          if ngx.re.match(res.body, "no Route matched with those values") then
            err = check_path .. "* doesn't map to a Route in Kong; " ..
                  "please refer to docs on how to create dummy Route and Service"
          elseif res.body ~= "Not found\n" then
            err = "unexpected response: \"" .. (res.body or "<nil>") .. "\""
            if res.status ~= 404 then
              err = err .. string.format(", unexpected status code: %d", res.status)
            end
          else
            return kong.response.exit(200, { message = "sanity test for host " .. host .. " passed"})
          end
        end
        return kong.response.exit(400, { message = "problem found running sanity check for " .. host .. ": " .. err})
      end

      local _, err = client.update_certificate(conf, host, nil)
      if err then
        return kong.response.exit(500, { message = "failed to update certificate: " .. err })
      end
      err = client.store_renew_config(conf, host)
      if err then
        return kong.response.exit(500, { message = "failed to store renew config: " .. err })
      end
      local msg = "certificate for host " .. host .. " is created"
      return kong.response.exit(201, { message = msg })
    end,

    PATCH = function()
      ngx.timer.at(0, client.renew_certificate)
      return kong.response.exit(202, { message = "Renewal process started successfully" })
    end,
  },

  ["/acme/certificates"] = {
    GET = function(self)
      local plugin, err = find_plugin()
      if err then
        return kong.response.exit(500, { message = err })
      elseif not plugin then
        return kong.response.exit(404)
      end

      local conf = plugin.config
      local renew_hosts, err = client.load_renew_hosts(conf)
      if err then
        return kong.response.exit(500, { message = err })
      end

      local data = {}
      local idx = 1
      for i, host in ipairs(renew_hosts) do
        local certkey, err = client.load_certkey(conf, host)
        if err then
          return kong.response.exit(500, { message = err })
        end
        if not certkey then
          kong.log.warn("[acme]", host, " is defined in renew_config but its cert and key is missing")
        else
          certkey = parse_certkey(certkey)
          if not self.params.invalid_only or not certkey.valid then
            data[idx] = certkey
            idx = idx + 1
          end
        end
      end
      return kong.response.exit(200, { data = data })
    end,
  },

  ["/acme/certificates/:ceritificates"] = {
    GET = function(self)
      local plugin, err = find_plugin()
      if err then
        return kong.response.exit(500, { message = err })
      elseif not plugin then
        return kong.response.exit(404)
      end

      local conf = plugin.config
      local host = self.params.ceritificates
      local certkey, err = client.load_certkey(conf, host)
      if err then
        return kong.response.exit(500, { message = err })
      end
      if not certkey then
        return kong.response.exit(404, { message = "Certificate for host " .. host .. "not found in storage" })
      end
      return kong.response.exit(200, { data = parse_certkey(certkey) })
    end,
  },
}
