local helpers = require "spec.helpers"

local fixtures = {
  dns_mock = helpers.dns_mock.new(),
  http_mock = {
    lambda_plugin = [[

      server {
          server_name mock_aws_lambda;
          listen 10001 ssl;
> if ssl_cert[1] then
> for i = 1, #ssl_cert do
          ssl_certificate     $(ssl_cert[i]);
          ssl_certificate_key $(ssl_cert_key[i]);
> end
> else
          ssl_certificate ${{SSL_CERT}};
          ssl_certificate_key ${{SSL_CERT_KEY}};
> end
          ssl_protocols TLSv1.2 TLSv1.3;

          location ~ "/2015-03-31/functions/(?:[^/])*/invocations" {
              content_by_lua_block {
                local function x()
                  local function say(res, status)
                    ngx.header["x-amzn-RequestId"] = "foo"

                    if string.match(ngx.var.uri, "functionWithUnhandledError") then
                      ngx.header["X-Amz-Function-Error"] = "Unhandled"
                    end

                    ngx.status = status

                    if string.match(ngx.var.uri, "functionWithBadJSON") then
                      local badRes = "{\"foo\":\"bar\""
                      ngx.header["Content-Length"] = #badRes + 1
                      ngx.say(badRes)

                    elseif string.match(ngx.var.uri, "functionWithNoResponse") then
                      ngx.header["Content-Length"] = 0

                    elseif string.match(ngx.var.uri, "functionWithBase64EncodedResponse") then
                      ngx.header["Content-Type"] = "application/json"
                      ngx.say("{\"statusCode\": 200, \"body\": \"dGVzdA==\", \"isBase64Encoded\": true}")

                    elseif string.match(ngx.var.uri, "functionWithNotBase64EncodedResponse") then
                      ngx.header["Content-Type"] = "application/json"
                      ngx.say("{\"statusCode\": 200, \"body\": \"dGVzdA=\", \"isBase64Encoded\": false}")

                    elseif string.match(ngx.var.uri, "functionWithIllegalBase64EncodedResponse") then
                      ngx.say("{\"statusCode\": 200, \"body\": \"dGVzdA=\", \"isBase64Encoded\": \"abc\"}")

                    elseif string.match(ngx.var.uri, "functionWithMultiValueHeadersResponse") then
                      ngx.header["Content-Type"] = "application/json"
                      ngx.say("{\"statusCode\": 200, \"headers\": { \"Age\": \"3600\"}, \"multiValueHeaders\": {\"Access-Control-Allow-Origin\": [\"site1.com\", \"site2.com\"]}}")

                    elseif string.match(ngx.var.uri, "functionEcho") then
                      require("spec.fixtures.mock_upstream").send_default_json_response()

                    elseif string.match(ngx.var.uri, "functionWithTransferEncodingHeader") then
                      ngx.say("{\"statusCode\": 200, \"headers\": { \"Transfer-Encoding\": \"chunked\", \"transfer-encoding\": \"chunked\"}}")

                    elseif string.match(ngx.var.uri, "functionWithLatency") then
                      -- additional latency
                      ngx.sleep(2)
                      ngx.say("{\"statusCodge\": 200, \"body\": \"dGVzdA=\", \"isBase64Encoded\": false}")

                    elseif string.match(ngx.var.uri, "functionWithEmptyArray") then
                      ngx.header["Content-Type"] = "application/json"
                      local str = "{\"statusCode\": 200, \"testbody\": [], \"isBase64Encoded\": false}"
                      ngx.say(str)

                    elseif string.match(ngx.var.uri, "plainStreaming") then
                      ngx.header["Content-Type"] = "application/vnd.amazon.eventstream"
                      ngx.header["x-amzn-Remapped-Content-Type"] = "application/octet-stream"
                      local hex_str = "000000760000005a980e72ec0b3a6576656e742d7479706507000c5061796c6f61644368756e6b0d3a636f6e74656e742d747970650700186170706c69636174696f6e2f6f637465742d73747265616d0d3a6d6573736167652d747970650700056576656e7448656c6c6f20776f726c642033971fd8000000760000005a980e72ec0b3a6576656e742d7479706507000c5061796c6f61644368756e6b0d3a636f6e74656e742d747970650700186170706c69636174696f6e2f6f637465742d73747265616d0d3a6d6573736167652d747970650700056576656e7466726f6d204c616d62646121fe88eff400000066000000541f56c8690b3a6576656e742d7479706507000e496e766f6b65436f6d706c6574650d3a636f6e74656e742d747970650700106170706c69636174696f6e2f6a736f6e0d3a6d6573736167652d747970650700056576656e747b7d7006d467"
                      for byte in hex_str:gmatch'%x%x' do
                        ngx.say(string.char(tonumber(byte,16)))
                      end

                    elseif string.match(ngx.var.uri, "httpIntegrationStreaming") then
                      ngx.header["Content-Type"] = "application/vnd.amazon.eventstream"
                      ngx.header["x-amzn-Remapped-Content-Type"] = "application/vnd.awslambda.http-integration-response"
                      local hex_str = "000000fc0000005a6358dadf0b3a6576656e742d7479706507000c5061796c6f61644368756e6b0d3a636f6e74656e742d747970650700186170706c69636174696f6e2f6f637465742d73747265616d0d3a6d6573736167652d747970650700056576656e747b22737461747573436f6465223a3430332c2268656164657273223a7b22436f6e74656e742d54797065223a22746578742f68746d6c222c22637573746f6d2d686561646572223a226f75746572207370616365227d2c22636f6f6b696573223a5b226c616e67756167653d787878222c227468656d653d616263225d7d000000000000000048656c6c6f20776f726c64207147d735000000760000005a980e72ec0b3a6576656e742d7479706507000c5061796c6f61644368756e6b0d3a636f6e74656e742d747970650700186170706c69636174696f6e2f6f637465742d73747265616d0d3a6d6573736167652d747970650700056576656e7466726f6d204c616d62646121fe88eff400000066000000541f56c8690b3a6576656e742d7479706507000e496e766f6b65436f6d706c6574650d3a636f6e74656e742d747970650700106170706c69636174696f6e2f6a736f6e0d3a6d6573736167652d747970650700056576656e747b7d7006d467"
                      for byte in hex_str:gmatch'%x%x' do
                        ngx.say(string.char(tonumber(byte,16)))
                      end


                    elseif type(res) == 'string' then
                      ngx.header["Content-Length"] = #res + 1
                      ngx.say(res)

                    else
                      ngx.req.discard_body()
                      ngx.header['Content-Length'] = 0
                    end

                    ngx.exit(0)
                  end

                  ngx.sleep(.2) -- mock some network latency

                  local invocation_type = ngx.var.http_x_amz_invocation_type
                  if invocation_type == 'Event' then
                    say(nil, 202)

                  elseif invocation_type == 'DryRun' then
                    say(nil, 204)
                  end

                  local qargs = ngx.req.get_uri_args()
                  ngx.req.read_body()
                  local request_body = ngx.req.get_body_data()
                  if request_body == nil then
                    local body_file = ngx.req.get_body_file()
                    if body_file then
                      ngx.log(ngx.DEBUG, "reading file cached to disk: ",body_file)
                      local file = io.open(body_file, "rb")
                      request_body = file:read("*all")
                      file:close()
                    end
                  end
                  print(request_body)
                  local args = require("cjson").decode(request_body)

                  say(request_body, 200)
                end
                local ok, err = pcall(x)
                if not ok then
                  ngx.log(ngx.ERR, "Mock error: ", err)
                end
              }
          }
      }

    ]]
  },
}

fixtures.stream_mock = {
  lambda_proxy = [[
    server {
      listen 13128;

      content_by_lua_block {
        require("spec.fixtures.forward-proxy-server").connect()
      }
    }
  ]],
}

fixtures.dns_mock:A {
  name = "lambda.us-east-1.amazonaws.com",
  address = "127.0.0.1",
}

return fixtures
