-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers = require "spec.helpers"

local fixtures = {
  dns_mock = helpers.dns_mock.new(),
  http_mock = {
    graphql_ratelimiting_advanced_plugin = [[

      server {
          server_name mock_graphql_service;
          listen 10002 ssl;
> if ssl_cert[1] then
> for i = 1, #ssl_cert do
          ssl_certificate     $(ssl_cert[i]);
          ssl_certificate_key $(ssl_cert_key[i]);
> end
> else
          ssl_certificate ${{SSL_CERT}};
          ssl_certificate_key ${{SSL_CERT_KEY}};
> end
          ssl_protocols TLSv1.1 TLSv1.2 TLSv1.3;

          location ~ "/graphql" {
            content_by_lua_block {
              ngx.req.read_body()
              local echo = ngx.req.get_body_data()
              local schema = require "spec.fixtures.schema-json-01"
              local response_body = '{"data": ' .. schema .. '}'
              ngx.status = 200
              ngx.header["Content-Length"] = #response_body + 1
              ngx.say(response_body)
            }
          }
      }

    ]]
  },
}


fixtures.dns_mock:A {
  name = "graphql.service.local.domain",
  address = "127.0.0.1",
}

return fixtures
