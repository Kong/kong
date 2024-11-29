-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local helpers     = require "spec.helpers"
local conf_loader = require "kong.conf_loader"

-- unsets kong license env vars and returns a function to restore their values
-- on test teardown
--
-- replace distributions_constants.lua to mock a GA release distribution
local function setup_distribution()
  local kld = os.getenv("KONG_LICENSE_DATA")
  helpers.unsetenv("KONG_LICENSE_DATA")

  local klp = os.getenv("KONG_LICENSE_PATH")
  helpers.unsetenv("KONG_LICENSE_PATH")

  local tmp_filename = "/tmp/distributions_constants.lua"
  assert(helpers.file.copy("kong/enterprise_edition/distributions_constants.lua", tmp_filename, true))
  assert(helpers.file.copy("spec-ee/fixtures/mock_distributions_constants.lua", "kong/enterprise_edition/distributions_constants.lua", true))

  return function()
    if kld then
      helpers.setenv("KONG_LICENSE_DATA", kld)
    end

    if klp then
      helpers.setenv("KONG_LICENSE_PATH", klp)
    end

    if helpers.path.exists(tmp_filename) then
      -- restore and delete backup
      assert(helpers.file.copy(tmp_filename, "kong/enterprise_edition/distributions_constants.lua", true))
      assert(helpers.file.delete(tmp_filename))
    end
  end
end

describe("Admin API #off", function()
  describe("should GET the license report", function()
    local client, reset_distribution

    lazy_setup(function()
      reset_distribution = setup_distribution()
      helpers.unsetenv("KONG_LICENSE_DATA")

      assert(conf_loader(nil, {
        plugins = "bundled,aws-lambda,kafka-upstream",
      }))

      assert(helpers.start_kong {
        database = "off",
        plugins = "bundled,aws-lambda,kafka-upstream",
        license_path = "spec-ee/fixtures/mock_license.json",
      })
      client = helpers.admin_client(10000)
    end)

    lazy_teardown(function()
      if client then
        client:close()
      end
      helpers.stop_kong()
      reset_distribution()
    end)

    it("/license/report response", function()
      local res, err = assert(client:send {
        method = "POST",
        path = "/config",
        body = {
          config = [[
          _transform: false
          _format_version: '3.0'
          workspaces:
          - config:
              portal_reset_email: ~
              portal_application_request_email: ~
              portal_application_status_email: ~
              portal_reset_success_email: ~
              portal_emails_from: ~
              portal: false
              portal_emails_reply_to: ~
              portal_smtp_admin_emails: ~
              portal_session_conf: ~
              portal_cors_origins: ~
              portal_auth: ~
              portal_auth_conf: ~
              meta: ~
              portal_token_exp: ~
              portal_invite_email: ~
              portal_developer_meta_fields: '[{"label":"Full Name","title":"full_name","validator":{"required":true,"type":"string"}}]'
              portal_access_request_email: ~
              portal_auto_approve: ~
              portal_approved_email: ~
              portal_is_legacy: ~
            comment: ~
            updated_at: 1704773152
            created_at: 1704773152
            name: default
            meta:
              thumbnail: ~
              color: ~
            id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
          parameters:
          - key: cluster_id
            created_at: ~
            updated_at: 1704771873
            value: fd4e6233-c813-45f3-b632-44e35feeb567
          consumers:
          - username: consumer1
          - username: consumer2
          - username: consumer3
            type: 1 # Non-proxy consumer shouldn't be counted
          services:
          - host: example.com
            port: 80
            created_at: 1704773152
            updated_at: 1704773152
            connect_timeout: 60000
            tags: ~
            read_timeout: 60000
            retries: 5
            write_timeout: 60000
            enabled: true
            tls_verify_depth: ~
            protocol: http
            client_certificate: ~
            ws_id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
            ca_certificates: ~
            tls_verify: ~
            name: service-1
            path: ~
            id: 118bc0c0-7d1d-4736-9777-9b394bab0f53
          routes:
          - created_at: 1704773152
            updated_at: 1704773152
            strip_path: true
            snis: ~
            request_buffering: true
            response_buffering: true
            name: ~
            headers: ~
            service: 118bc0c0-7d1d-4736-9777-9b394bab0f53
            ws_id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
            sources: ~
            preserve_host: false
            path_handling: v0
            destinations: ~
            tags: ~
            hosts:
            - lambda1.test
            regex_priority: 0
            methods: ~
            protocols:
            - http
            - https
            paths: ~
            https_redirect_status_code: 426
            id: 43113c2f-f4c3-4562-8f0f-2296c22114f3
          - created_at: 1704773152
            updated_at: 1704773152
            strip_path: true
            snis: ~
            request_buffering: true
            response_buffering: true
            name: ~
            headers: ~
            service: ~
            ws_id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
            sources: ~
            preserve_host: false
            path_handling: v0
            destinations: ~
            tags: ~
            hosts:
            - lambda2.test
            regex_priority: 0
            methods: ~
            protocols:
            - http
            - https
            paths: ~
            https_redirect_status_code: 426
            id: b9927982-594d-4758-9d27-9b3571ffbbfa
          - created_at: 1704773152
            updated_at: 1704773152
            strip_path: true
            snis: ~
            request_buffering: true
            response_buffering: true
            name: ~
            headers: ~
            service: ~
            ws_id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
            sources: ~
            preserve_host: false
            path_handling: v0
            destinations: ~
            tags: ~
            hosts:
            - lambda3.test
            regex_priority: 0
            methods: ~
            protocols:
            - http
            - https
            paths: ~
            https_redirect_status_code: 426
            id: f158f714-32c5-4942-9bd0-e58045971f8f
          plugins:
          - enabled: true
            consumer_group: ~
            id: 0da233fa-6154-4080-8d68-88b567725476
            instance_name: ~
            updated_at: 1704773152
            config:
              host: ~
              port: 10001
              disable_https: false
              unhandled_status: ~
              forward_request_method: false
              forward_request_uri: false
              forward_request_headers: false
              forward_request_body: false
              aws_key: mock-key
              is_proxy_integration: false
              aws_secret: mock-secret
              awsgateway_compatible: false
              aws_assume_role_arn: ~
              skip_large_bodies: true
              aws_role_session_name: kong
              base64_encode_body: true
              aws_region: us-east-1
              function_name: kongLambdaTest
              aws_imds_protocol_version: v1
              timeout: 60000
              log_type: Tail
              invocation_type: Event
              proxy_url: ~
              qualifier: ~
              keepalive: 60000
            ws_id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
            route: b9927982-594d-4758-9d27-9b3571ffbbfa
            tags: ~
            consumer: ~
            protocols:
            - grpc
            - grpcs
            - http
            - https
            ordering: ~
            name: aws-lambda
            created_at: 1704773152
            service: ~
          - enabled: true
            consumer_group: ~
            id: 34a344ba-1d32-40f0-825a-9b3a6a1c3449
            instance_name: ~
            updated_at: 1704773152
            config:
              host: ~
              port: 10001
              disable_https: false
              unhandled_status: ~
              forward_request_method: false
              forward_request_uri: false
              forward_request_headers: false
              forward_request_body: false
              aws_key: mock-key
              is_proxy_integration: false
              aws_secret: mock-secret
              awsgateway_compatible: false
              aws_assume_role_arn: ~
              skip_large_bodies: true
              aws_role_session_name: kong
              base64_encode_body: true
              aws_region: us-east-1
              function_name: kongLambdaTest
              aws_imds_protocol_version: v1
              timeout: 60000
              log_type: Tail
              invocation_type: Event
              proxy_url: ~
              qualifier: ~
              keepalive: 60000
            ws_id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
            route: 43113c2f-f4c3-4562-8f0f-2296c22114f3
            tags: ~
            consumer: ~
            protocols:
            - grpc
            - grpcs
            - http
            - https
            ordering: ~
            name: aws-lambda
            created_at: 1704773152
            service: ~
          - enabled: true
            consumer_group: ~
            id: 5a61a982-49d6-43ac-93aa-0f5eedac101c
            instance_name: ~
            updated_at: 1704773152
            config:
              host: ~
              port: 10001
              disable_https: false
              unhandled_status: ~
              forward_request_method: false
              forward_request_uri: false
              forward_request_headers: false
              forward_request_body: false
              aws_key: mock-key
              is_proxy_integration: false
              aws_secret: mock-secret
              awsgateway_compatible: false
              aws_assume_role_arn: ~
              skip_large_bodies: true
              aws_role_session_name: kong
              base64_encode_body: true
              aws_region: us-east-1
              function_name: kongLambdaTest
              aws_imds_protocol_version: v1
              timeout: 60000
              log_type: Tail
              invocation_type: Event
              proxy_url: ~
              qualifier: ~
              keepalive: 60000
            ws_id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
            route: f158f714-32c5-4942-9bd0-e58045971f8f
            tags: ~
            consumer: ~
            protocols:
            - grpc
            - grpcs
            - http
            - https
            ordering: ~
            name: aws-lambda
            created_at: 1704773152
            service: ~
          - enabled: true
            ws_id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
            consumer_group: ~
            created_at: 1704773153
            updated_at: 1704773153
            config:
              bootstrap_servers:
              - host: mock-host
                port: 9092
              producer_request_timeout: 2000
              topic: sync_topic
              producer_request_limits_messages_per_request: 200
              producer_request_retries_max_attempts: 10
              keepalive_enabled: false
              authentication:
                password: ~
                user: ~
                mechanism: ~
                strategy: ~
                tokenauth: ~
              producer_async: false
              producer_async_flush_timeout: 1000
              producer_async_buffering_limits_messages_in_memory: 50000
              forward_method: false
              producer_request_limits_bytes_per_request: 1048576
              forward_uri: false
              producer_request_retries_backoff_timeout: 100
              forward_headers: false
              timeout: 10000
              forward_body: true
              keepalive: 60000
              cluster_name: zuSFFStcgpc13xYCdc6rZREGdnPqmGG8
              security:
                ssl: ~
                certificate_id: ~
              producer_request_acks: 1
            service: ~
            route: f158f714-32c5-4942-9bd0-e58045971f8f
            tags: ~
            consumer: ~
            protocols:
            - grpc
            - grpcs
            - http
            - https
            instance_name: ~
            ordering: ~
            name: kafka-upstream
            id: 5afcc904-6c7b-4a58-8f20-3ca0eccb3383
          - enabled: true
            ws_id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
            consumer_group: ~
            created_at: 1704773153
            updated_at: 1704773153
            config:
              bootstrap_servers:
              - host: mock-host
                port: 9092
              producer_request_timeout: 2000
              topic: sync_topic
              producer_request_limits_messages_per_request: 200
              producer_request_retries_max_attempts: 10
              keepalive_enabled: false
              authentication:
                password: ~
                user: ~
                mechanism: ~
                strategy: ~
                tokenauth: ~
              producer_async: false
              producer_async_flush_timeout: 1000
              producer_async_buffering_limits_messages_in_memory: 50000
              forward_method: false
              producer_request_limits_bytes_per_request: 1048576
              forward_uri: false
              producer_request_retries_backoff_timeout: 100
              forward_headers: false
              timeout: 10000
              forward_body: true
              keepalive: 60000
              cluster_name: 7xzdA5TV4Jpa0VYYuyPewpq8XWu9SDwu
              security:
                ssl: ~
                certificate_id: ~
              producer_request_acks: 1
            service: ~
            route: b9927982-594d-4758-9d27-9b3571ffbbfa
            tags: ~
            consumer: ~
            protocols:
            - grpc
            - grpcs
            - http
            - https
            instance_name: ~
            ordering: ~
            name: kafka-upstream
            id: 67a2df1b-83f1-4196-b8ce-e63210f52762
          - enabled: true
            ws_id: dbcffecd-e11a-4b38-a28a-7799fd4d398c
            consumer_group: ~
            created_at: 1704773152
            updated_at: 1704773152
            config:
              bootstrap_servers:
              - host: mock-host
                port: 9092
              producer_request_timeout: 2000
              topic: sync_topic
              producer_request_limits_messages_per_request: 200
              producer_request_retries_max_attempts: 10
              keepalive_enabled: false
              authentication:
                password: ~
                user: ~
                mechanism: ~
                strategy: ~
                tokenauth: ~
              producer_async: false
              producer_async_flush_timeout: 1000
              producer_async_buffering_limits_messages_in_memory: 50000
              forward_method: false
              producer_request_limits_bytes_per_request: 1048576
              forward_uri: false
              producer_request_retries_backoff_timeout: 100
              forward_headers: false
              timeout: 10000
              forward_body: true
              keepalive: 60000
              cluster_name: 0GoP1fQk6FnvvCGqVU5JCCFqGyYAlyDq
              security:
                ssl: ~
                certificate_id: ~
              producer_request_acks: 1
            service: ~
            route: 43113c2f-f4c3-4562-8f0f-2296c22114f3
            tags: ~
            consumer: ~
            protocols:
            - grpc
            - grpcs
            - http
            - https
            instance_name: ~
            ordering: ~
            name: kafka-upstream
            id: f36b9f54-82f0-460e-89e9-34897c455b38
              ]],
        },
        headers = {
          ["Content-Type"] = "application/json"
        }
      })

      assert.is_nil(err)
      assert.response(res).has.status(201)

      res, err = client:send({
        method = "GET",
        path = "/license/report",
      })

      assert.is_nil(err)
      assert.res_status(200, res)

      local report = assert.response(res).has.jsonbody()

      assert.not_nil(report.license.license_key, "missing license_key")
      assert.not_nil(report.license.license_expiration_date, "missing license_expiration_date")
      assert.not_nil(report.timestamp, "missing timestamp")
      assert.not_nil(report.checksum, "missing checksum")
      assert.not_nil(report.deployment_info, "missing deployment_info")
      assert.not_nil(report.plugins_count, "missing plugins_count")
      assert.equals(1, report.services_count)
      assert.equals(2, report.consumers_count)
      assert.equals(3, report.routes_count)
      assert.equals(0, report.rbac_users)
      assert.equals(1, report.plugins_count.unique_route_lambdas)
      assert.equals(1, report.plugins_count.unique_route_kafkas)
      assert.equals(3, report.plugins_count.tiers.enterprise["kafka-upstream"])
      assert.equals(3, report.plugins_count.tiers.free["aws-lambda"])
    end)
  end)
end)
