--- Shared proxy configuration schema and handling

local Schema = require "kong.db.schema"
local typedefs = require "kong.db.schema.typedefs"
local base64_encode = ngx.encode_base64

local HTTP_PROXY, HTTPS_PROXY do

  local url = require "socket.url"

  local function parse_proxy_env(name)
    name = name:upper()
    local proxy_url = os.getenv(name) or os.getenv(name:lower())
    if not proxy_url then
      return {}
    end
    proxy_url = proxy_url:lower()

    local url_t = url.parse(proxy_url)
    if not url_t.host then
      kong.log.err("Invalid proxy value for environment variable '", name, "'/'", name:lower(), "': ", proxy_url)
      return {}
    end

    if url_t.scheme ~= "http" then
      kong.log.err("Invalid proxy value for environment variable '", name, "'/'", name:lower(), "', only 'http' is supported: ", proxy_url)
      return {}
    end

    return {
      host = url_t.host,
      port = tonumber(url_t.port) or 80, -- default to 80, since we do not support https anyway
      scheme = url_t.scheme or "http",
      user = url_t.user,
      password = url_t.password,
    }
  end

  HTTP_PROXY = parse_proxy_env("HTTP_PROXY")
  HTTPS_PROXY = parse_proxy_env("HTTPS_PROXY")
end





local proxies = {}

do
  local scheme_def = Schema.define {
    -- scheme from Kong to proxy, only `http` is supported
    type = "string",
    one_of = { "http" },
    default = "http",
  }

  local creds_def = Schema.define {
    -- used for username and password
    type = "string",
    required = false,
    referenceable = true,
}

  proxies.schema = Schema.define {
    type = "record",
    fields = {
      { enable = {
        type = "string",
        required = true,
        one_of = { "none", "http", "https", "all" },
        default = "none",
      }},

      { http_host = typedefs.host },
      { http_port = typedefs.port },
      { http_scheme = scheme_def },
      { http_username = creds_def },
      { http_password = creds_def },

      { https_host = typedefs.host },
      { https_port = typedefs.port },
      { https_scheme = scheme_def },
      { https_username = creds_def },
      { https_password = creds_def },
    },
    entity_checks = {
      { mutually_required = { "http_host", "http_port", "http_scheme" }},
      { mutually_required = { "https_host", "https_port", "https_scheme" }},
    },
  }
end

do
  local cache = setmetatable({}, { __mode = "k" })


  -- returns the proxy url from the given input, falls back on the env variable
  -- or returns nil if neither is set
  local function proxy_url(scheme, host, port, env)
    if scheme then
      return ("%s://%s:%d"):format(scheme, host, port)

    elseif env.scheme then
      return ("%s://%s:%d"):format(env.scheme, env.host, env.port)

    else
      return nil
    end
  end


  local function auth_header(user, pwd, env)
    local euser = env.user
    local epwd = env.password

    if user == "" then user = nil end
    if pwd == "" then pwd = nil end
    if euser == "" then euser = nil end
    if epwd == "" then epwd = nil end

    if user or pwd then
      return "Basic " .. base64_encode((user or "") .. ":" .. (pwd or ""))

    elseif euser or epwd then
      return "Basic " .. base64_encode((euser or "") .. ":" .. (epwd or ""))

    else
      return nil
    end
  end


  local function create_proxy_opts(proxy_conf)
    local proxy_opts = {}

    if proxy_conf.enable == "http" or proxy_conf.enable == "all" then
      proxy_opts.http_proxy_authorization = auth_header(proxy_conf.http_username, proxy_conf.http_password, HTTP_PROXY)
      proxy_opts.http_proxy = proxy_url(proxy_conf.http_scheme, proxy_conf.http_host, proxy_conf.http_port, HTTP_PROXY)
      if not proxy_opts.http_proxy then
        kong.log.err("http-proxy enabled but not (properly) configured in plugin nor in HTTP_PROXY env variable")
        return kong.response.error(500)
      end
    end

    if proxy_conf.enable == "https" or proxy_conf.enable == "all" then
      proxy_opts.https_proxy_authorization = auth_header(proxy_conf.https_username, proxy_conf.https_password, HTTPS_PROXY)
      proxy_opts.https_proxy = proxy_url(proxy_conf.https_scheme, proxy_conf.https_host, proxy_conf.https_port, HTTPS_PROXY)
      if not proxy_opts.https_proxy then
        kong.log.err("https-proxy enabled but not (properly) configured in plugin nor in HTTPS_PROXY env variable")
        return kong.response.error(500)
      end
    end

    cache[proxy_conf] = proxy_opts
    return proxy_opts
  end


  --- Based on the shared config schema, returns the proxy-opts table for the
  -- lua-resty-http client.
  -- ** NOTE **: The returned table should be considered read-only!
  function proxies.get_proxy_opts(proxy_conf)
    return cache[proxy_conf] or create_proxy_opts(proxy_conf)
  end
end

return proxies
