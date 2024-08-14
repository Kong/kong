-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local xmlua   = require "xmlua"
local http    = require "resty.http"
local xpath   = require "kong.plugins.saml.utils.xpath"
local tablex  = require "pl.tablex"
local redis_helper = require "spec.helpers.redis_helper"

local helpers = require "spec.helpers"
local split   = require("kong.tools.utils").split
local keycloak_api = require "spec-ee.fixtures.keycloak_api".new()

local keycloak_config    = keycloak_api.config
local PLUGIN_NAME        = "saml"
local USERNAME           = "samluser1"
local PASSWORD           = "pass1234#"
local KEYCLOAK_HOST      = keycloak_config.host_name
local KEYCLOAK_PORT      = tonumber(keycloak_config.port)
local REALM_PATH         = keycloak_config.realm_path
local SESSION_SECRET     = "iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii"

local IDP_DESCRIPTOR_URL = "http://" .. KEYCLOAK_HOST .. ":" .. KEYCLOAK_PORT .. REALM_PATH .. "/protocol/saml/descriptor"
local IDP_SSO_URL        = "http://" .. KEYCLOAK_HOST .. ":" .. KEYCLOAK_PORT .. REALM_PATH .. "/protocol/saml"

local ISSUER_URL         = "http://keycloaksamldemo"

local REDIS_HOST          = helpers.redis_host
local REDIS_PORT          = helpers.redis_port
local REDIS_USER_VALID    = "saml-user"
local REDIS_PASSWORD      = "secret"
local REDIS_CLUSTER_NODES = require "spec-ee.helpers".redis_cluster_nodes
local REDIS_SENTINEL_NODES = require "spec-ee.helpers".redis_sentinel_nodes
local MEMCACHED_HOST      = os.getenv("KONG_SPEC_TEST_MEMCACHED_HOST") or "memcached"
local MEMCACHED_PORT      = tonumber(os.getenv("KONG_SPEC_TEST_MEMCACHED_PORT_11211")) or 11211


-- Updates the cookie stored in `current_cookies` (k-v pairs) in-place
-- according to the Set-Cookie header `set_cookie_headers`
-- and return an array of cookies that is consumable by lua-resty-http
local function extract_and_update_cookies(current_cookies, set_cookie_headers)
  local function make_cookie_str(coo)
    local ret = {}
    for k, v in pairs(coo) do
      table.insert(ret, k .. "=" .. v)
    end

    return ret
  end

  current_cookies = current_cookies or {}
  if not set_cookie_headers then
    return make_cookie_str(current_cookies)
  end

  for i, cookie in ipairs(set_cookie_headers) do
    cookie = unpack(split(cookie, ";"))
    local key, value = unpack(split(cookie, "="))
    current_cookies[key] = value
  end

  return make_cookie_str(current_cookies)
end

local extract_from_html

do
  local function re_first_group(text, re)
    local match = ngx.re.match(text, re)
    if match then
      return match[1]
    end
  end

  local ENTITIES = {
    lt = "<",
    gt = ">",
    amp = "&",
    quot = '"',
    apos = "'",
  }

  local function decode_html_entities(string)
    return ngx.re.gsub(string, "&([a-z]+);", function(match) return ENTITIES[match[1]] or "" end)
  end

  extract_from_html = function(html, re)
    return decode_html_entities(re_first_group(html, re))
  end
end


local function find_form_field_value(html, field_name)
  return extract_from_html(html, 'name="' .. field_name .. '" value="(.*?)"')
end


local function find_form_action(html)
  return extract_from_html(html, [[action="(.*?)"]])
end


local function sp_init_flow(res, username, password)
  local body = res:read_body()
  assert.equal(200, res.status)
  assert.is_not_nil(body)
  local sso_url = find_form_action(body)
  local saml_assertion = find_form_field_value(body, "SAMLRequest")
  local relay_state = find_form_field_value(body, "RelayState")
  local client = http.new()
  local login_page, err = client:request_uri(sso_url, {
      method  = "POST",
      headers = {
        -- impersonate as browser
        ["Content-Type"] = "application/x-www-form-urlencoded",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36", -- luacheck: ignore
        ["Host"] = KEYCLOAK_HOST .. ":" .. KEYCLOAK_PORT,
      },
      body = "SAMLRequest=" .. ngx.escape_uri(saml_assertion) .. "&RelayState=" .. ngx.escape_uri(relay_state),
  })
  assert.is_nil(err)
  assert.equal(302, login_page.status)

  local cookies = {}

  -- after sending login data to the login action page, expect a redirect
  local upstream_url = login_page.headers["Location"]
  local login_page_redirect, err = client:request_uri(upstream_url, {
      headers = {
        -- send session cookie
        Cookie = extract_and_update_cookies(cookies, login_page.headers["Set-Cookie"])
      }
  })
  assert.is_nil(err)
  assert.equal(200, login_page_redirect.status)
  assert.is_not_nil(login_page_redirect.body)

  body = login_page_redirect.body
  local login_url = find_form_action(body)
  local login_res, err = client:request_uri(login_url, {
      method = "POST",
      headers = {
        -- impersonate as browser
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/93.0.4577.63 Safari/537.36", --luacheck: ignore
        -- due to form_data
        ["Content-Type"] = "application/x-www-form-urlencoded",
        -- send session cookie
        Cookie = extract_and_update_cookies(cookies, login_page.headers["Set-Cookie"])
      },
      body = "username=" .. username .. "&password=" .. password,
  })
  assert.is_nil(err)
  assert.equal(200, login_res.status)
  assert.is_not_nil(login_res.body)

  return find_form_field_value(login_res.body, "SAMLResponse"), find_form_field_value(login_res.body, "RelayState")
end


local function retrieve_cert_from_idp()
  local client = http.new()
  local res, err = client:request_uri(IDP_DESCRIPTOR_URL, { method = "GET" })
  assert.is_nil(err)
  assert.equal(200, res.status, "non 200 response from keycloak was: " .. res.body)
  local body = xmlua.XML.parse(res.body)
  local cert = xpath.evaluate(body, "/md:EntityDescriptor/md:IDPSSODescriptor/md:KeyDescriptor/dsig:KeyInfo/dsig:X509Data/dsig:X509Certificate/text()")
  assert.is_truthy(cert)
  return cert
end


for _, strategy in helpers.all_strategies() do
  for _, session_storage in ipairs {"memcached", "redis", "cookie", "redis_cluster", "redis_sentinel"} do
    describe(PLUGIN_NAME .. ": #" .. strategy .. "_" .. session_storage, function()
        local redis


        setup(function()
            redis = redis_helper.connect(REDIS_HOST, REDIS_PORT)
            redis_helper.add_admin_user(redis, REDIS_USER_VALID, REDIS_PASSWORD)
        end)

        teardown(function()
            redis_helper.remove_user(redis, REDIS_USER_VALID)
        end)

        local proxy_client

        lazy_setup(function()
            local db_strategy = strategy ~= "off" and strategy or nil
            local bp = helpers.get_db_utils(db_strategy, {
                "routes",
                "services",
                "plugins",
                                                      }, {
                PLUGIN_NAME, "ctx-checker-last",
            })

            local service = bp.services:insert {
              name = PLUGIN_NAME,
              path = "/anything"
            }

            local anon = bp.consumers:insert {
              username = "anonymous"
            }

            bp.consumers:insert {
              username = "samluser1@konghq.com",
            }

            local route_anon = bp.routes:insert {
              service = service,
              paths   = { "/anon" },
            }

            local route_non_anon = bp.routes:insert {
              service = service,
              paths   = { "/non-anon" },
            }

            bp.plugins:insert({
              name     = "ctx-checker-last",
              route = { id = route_non_anon.id },
              config   = {
                ctx_check_field = "authenticated_consumer",
              }
            })

            local idp_cert = retrieve_cert_from_idp()

            local function plugin_config(params)
              if session_storage == "redis_cluster" then
                return tablex.merge(
                  {
                    session_secret = SESSION_SECRET,
                    session_redis_cluster_nodes = REDIS_CLUSTER_NODES,
                    session_storage = "redis",
                    validate_assertion_signature = false,
                    issuer    = ISSUER_URL,
                    assertion_consumer_path = "/consume",
                    idp_sso_url = IDP_SSO_URL,
                    nameid_format = "EmailAddress",
                    idp_certificate = idp_cert,
                  },
                  params or {},
                  true
                )
              elseif session_storage == "redis_sentinel" then
                return tablex.merge(
                  {
                    session_secret = SESSION_SECRET,
                    redis = {
                      sentinel_nodes = REDIS_SENTINEL_NODES,
                      sentinel_role = "master",
                      sentinel_master = "mymaster"
                    },
                    session_storage = "redis",
                    validate_assertion_signature = false,
                    issuer    = ISSUER_URL,
                    assertion_consumer_path = "/consume",
                    idp_sso_url = IDP_SSO_URL,
                    nameid_format = "EmailAddress",
                    idp_certificate = idp_cert,
                  },
                  params or {},
                  true
                )
              end
              return tablex.merge(
                {
                  session_secret = SESSION_SECRET,
                  session_redis_host = REDIS_HOST,
                  session_redis_port = REDIS_PORT,
                  session_redis_username = REDIS_USER_VALID,
                  session_redis_password = REDIS_PASSWORD,
                  session_memcached_host = MEMCACHED_HOST,
                  session_memcached_port = MEMCACHED_PORT,
                  session_storage = session_storage,
                  validate_assertion_signature = false,
                  issuer    = ISSUER_URL,
                  assertion_consumer_path = "/consume",
                  idp_sso_url = IDP_SSO_URL,
                  nameid_format = "EmailAddress",
                  idp_certificate = idp_cert,
                },
                params or {},
                true
              )
            end

            bp.plugins:insert {
              route   = route_anon,
              name    = PLUGIN_NAME,
              config  = plugin_config({
                anonymous = anon.id,
              }),
            }

            bp.plugins:insert {
              route   = route_non_anon,
              name    = PLUGIN_NAME,
              config  = plugin_config(),
            }

            local cookie_route = bp.routes:insert {
              paths   = { "/cookie-tst" },
            }

            bp.plugins:insert {
              route = cookie_route,
              name = PLUGIN_NAME,
              config = plugin_config({
                session_cookie_http_only = false,
                session_cookie_domain = "example.org",
                session_cookie_path = "/test",
                session_cookie_same_site = "Default",
                session_cookie_secure = true,
              }),
            }

            local bad_cookie_route = bp.routes:insert {
              paths   = { "/cookie-tst-bad" },
            }

            bp.plugins:insert {
              route = bad_cookie_route,
              name = PLUGIN_NAME,
              config = plugin_config({
                session_redis_password = "this is not the redis password",
                session_cookie_http_only = false,
                session_cookie_domain = "example.org",
                session_cookie_path = "/test",
                session_cookie_same_site = "Default",
                session_cookie_secure = true,
              }),
            }

            assert(helpers.start_kong({
                  database   = db_strategy,
                  nginx_conf = "spec/fixtures/custom_nginx.template",
                  plugins    = "bundled,ctx-checker-last," .. PLUGIN_NAME,
            }))
        end)

        lazy_teardown(function()
            helpers.stop_kong()
        end)

        before_each(function()
            proxy_client = helpers.proxy_client()
        end)

        after_each(function()
            if proxy_client then
              proxy_client:close()
            end
        end)

        if session_storage == "redis" or session_storage == "redis_cluster" then
          it("aborts the login flow when the redis configuration is incorrect", function()
            local res = proxy_client:get("/cookie-tst-bad", {
              headers = {
                ["Host"] = "kong",
                ["Accept"] = "text/html"
              }
            })

            local saml_response, relay_state = sp_init_flow(res, USERNAME, PASSWORD)
            local response = proxy_client:post("/cookie-tst-bad/consume", {
              headers = {
                ["Host"] = "kong",
                ["Content-Type"] = "application/x-www-form-urlencoded",
              },
              body = "SAMLResponse=" .. ngx.escape_uri(saml_response) .. "&RelayState=" .. ngx.escape_uri(relay_state),
            })
            assert.equal(500, response.status)
          end)
        end

        it("correctly configures cookie attributes", function()
          local res = proxy_client:get("/cookie-tst", {
              headers = {
                ["Host"] = "kong",
                ["Accept"] = "text/html"
              }
          })

          local saml_response, relay_state = sp_init_flow(res, USERNAME, PASSWORD)
          local response, err = proxy_client:post("/cookie-tst/consume", {
              headers = {
                ["Host"] = "kong",
                ["Content-Type"] = "application/x-www-form-urlencoded",
              },
              body = "SAMLResponse=" .. ngx.escape_uri(saml_response) .. "&RelayState=" .. ngx.escape_uri(relay_state),
          })
          assert.is_nil(err)
          assert.equal(302, response.status)
          local cookie = response.headers["Set-Cookie"]
          assert.is_not_nil(cookie)
          assert.does_not.match("HttpOnly", cookie)
          assert.matches("Domain=example.org", cookie)
          assert.matches("Path=/test", cookie)
          assert.matches("SameSite=Default", cookie)
          assert.matches("Secure", cookie)
        end)

        it("SP request with anonymous consumer is successful", function()
            local res = proxy_client:get("/anon", {
                headers = {
                  ["Host"] = "kong",
                  ["Accept"] = "text/html",
                }
            })
            local saml_response, relay_state = sp_init_flow(res, USERNAME, PASSWORD)
            local response, err = proxy_client:post("/anon/consume", {
                headers = {
                  ["Host"] = "kong",
                  ["Content-Type"] = "application/x-www-form-urlencoded",
                },
                body = "SAMLResponse=" .. ngx.escape_uri(saml_response) .. "&RelayState=" .. ngx.escape_uri(relay_state),
            })
            assert.is_nil(err)
            assert.equal(302, response.status)

        end)

        it("SP request with consumer is successful", function()
            local res = proxy_client:get("/non-anon", {
                headers = {
                  ["Host"] = "kong",
                  ["Accept"] = "text/html",
                }
            })
            local saml_response, relay_state = sp_init_flow(res, USERNAME, PASSWORD)
            local response, err = proxy_client:post("/non-anon/consume", {
                headers = {
                  ["Host"] = "kong",
                  ["Content-Type"] = "application/x-www-form-urlencoded",
                },
                body = "SAMLResponse=" .. ngx.escape_uri(saml_response) .. "&RelayState=" .. ngx.escape_uri(relay_state),
            })
            assert.is_nil(err)
            assert.equal(302, response.status)

        end)

        it("check authenticated_consumer ctx when SP request with consumer is successful", function()
          local res = proxy_client:get("/non-anon", {
              headers = {
                ["Host"] = "kong",
                ["Accept"] = "text/html",
              }
          })
          local saml_response, relay_state = sp_init_flow(res, USERNAME, PASSWORD)
          local response, err = proxy_client:post("/non-anon/consume", {
              headers = {
                ["Host"] = "kong",
                ["Content-Type"] = "application/x-www-form-urlencoded",
              },
              body = "SAMLResponse=" .. ngx.escape_uri(saml_response) .. "&RelayState=" .. ngx.escape_uri(relay_state),
          })
          assert.is_nil(err)
          assert.equal(302, response.status)
          local redirect_uri = response.headers["Location"]
          assert.not_nil(redirect_uri)
          local cookie = response.headers["Set-Cookie"]

          -- reinit proxy_client
          proxy_client:close()
          proxy_client = helpers.proxy_client()

          local redirect_res, err = proxy_client:get(redirect_uri, {
            headers = {
              ["Host"] = "kong",
              ["Accept"] = "text/html",
              ["Cookie"] = cookie,
            }
          })

          assert.is_nil(err)
          assert.equal(200, redirect_res.status)
          assert.matches("samluser1", redirect_res.headers["ctx-checker-last-authenticated-consumer"])
      end)

        it("invalid SAMLResponse posted to /consume callback results in 400 error", function()
            local response, err = proxy_client:post("/anon/consume", {
                headers = {
                  ["Content-Type"] = "application/x-www-form-urlencoded",
                },
                body = "SAMLResponse=not_valid",
            })
            assert.is_nil(err)
            assert.equal(400, response.status)

        end)

        it("SP request with missing consumer is rejected", function()
            local res = proxy_client:get("/non-anon", {
                headers = {
                  ["Host"] = "kong",
                  ["Accept"] = "text/html",
                }
            })
            local saml_response, relay_state = sp_init_flow(res, "samluser2", "pass1234#")
            local response, err = proxy_client:post("/non-anon/consume", {
                headers = {
                  ["Content-Type"] = "application/x-www-form-urlencoded",
                },
                body = "SAMLResponse=" .. ngx.escape_uri(saml_response) .. "&RelayState=" .. ngx.escape_uri(relay_state),
            })

            assert.is_nil(err)
            assert.equal(302, response.status)
        end)

        it("POST data is preserved during IdP interaction", function()
            local res = proxy_client:post("/non-anon", {
                headers = {
                  ["Host"] = "kong",
                  ["Accept"] = "text/html",
                  ["Content-type"] = "application/x-www-form-urlencoded",
                },
                body = {
                  this = "is",
                  some = "body",
                },
            })
            local saml_response, relay_state = sp_init_flow(res, "samluser2", "pass1234#")
            local res, err = proxy_client:post("/non-anon/consume", {
                headers = {
                  ["Content-Type"] = "application/x-www-form-urlencoded",
                },
                body = "SAMLResponse=" .. ngx.escape_uri(saml_response) .. "&RelayState=" .. ngx.escape_uri(relay_state),
            })

            assert.is_nil(err)
            assert.equal(200, res.status)
            local body = res:read_body()
            assert.equal("is", find_form_field_value(body, "this"))
            assert.equal("body", find_form_field_value(body, "some"))
        end)

        it("POST request with unsupported encoding is rejected", function()
            local res = proxy_client:post("/non-anon", {
                headers = {
                  ["Host"] = "kong",
                  ["Accept"] = "text/html",
                  ["Content-type"] = "multipart/form-data",
                },
                body = {
                  this = "is",
                  some = "body",
                },
            })
            assert.equal(415, res.status)
        end)

        it("API request with no session is rejected as unauthorized", function()
            local res = proxy_client:get("/non-anon", {
                headers = {
                  ["Host"] = "kong",
                  ["Accept"] = "application/json",
                }
            })
            assert.equal(401, res.status)
        end)
    end)
  end
end
