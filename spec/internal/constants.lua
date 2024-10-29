-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

-- contants used by helpers.lua
local CONSTANTS = {
  BIN_PATH = "bin/kong",
  TEST_CONF_PATH = os.getenv("KONG_SPEC_TEST_CONF_PATH") or "spec/kong_tests.conf",
  CUSTOM_PLUGIN_PATH = "./spec/fixtures/custom_plugins/?.lua",

  -- XXX EE custom plugins for enterprise tests
  CUSTOM_EE_PLUGIN_PATH = "./spec-ee/fixtures/custom_plugins/?.lua;./spec-ee/fixtures/custom_plugins/?/init.lua;./?/init.lua",

  CUSTOM_VAULT_PATH = "./spec/fixtures/custom_vaults/?.lua;./spec/fixtures/custom_vaults/?/init.lua",
  DNS_MOCK_LUA_PATH = "./spec/fixtures/mocks/lua-resty-dns/?.lua",
  GO_PLUGIN_PATH = "./spec/fixtures/go",
  GRPC_TARGET_SRC_PATH = "./spec/fixtures/grpc/target/",
  MOCK_UPSTREAM_PROTOCOL = "http",
  MOCK_UPSTREAM_SSL_PROTOCOL = "https",
  MOCK_UPSTREAM_HOST = "127.0.0.1",
  MOCK_UPSTREAM_HOSTNAME = "localhost",
  MOCK_UPSTREAM_PORT = 15555,
  MOCK_UPSTREAM_SSL_PORT = 15556,
  MOCK_UPSTREAM_STREAM_PORT = 15557,
  MOCK_UPSTREAM_STREAM_SSL_PORT = 15558,
  GRPCBIN_HOST = os.getenv("KONG_SPEC_TEST_GRPCBIN_HOST") or "localhost",
  GRPCBIN_PORT = tonumber(os.getenv("KONG_SPEC_TEST_GRPCBIN_PORT")) or 9000,
  GRPCBIN_SSL_PORT = tonumber(os.getenv("KONG_SPEC_TEST_GRPCBIN_SSL_PORT")) or 9001,
  MOCK_GRPC_UPSTREAM_PROTO_PATH = "./spec/fixtures/grpc/hello.proto",
  ZIPKIN_HOST = os.getenv("KONG_SPEC_TEST_ZIPKIN_HOST") or "localhost",
  ZIPKIN_PORT = tonumber(os.getenv("KONG_SPEC_TEST_ZIPKIN_PORT")) or 9411,
  OTELCOL_HOST = os.getenv("KONG_SPEC_TEST_OTELCOL_HOST") or "localhost",
  OTELCOL_HTTP_PORT = tonumber(os.getenv("KONG_SPEC_TEST_OTELCOL_HTTP_PORT")) or 4318,
  OTELCOL_ZPAGES_PORT = tonumber(os.getenv("KONG_SPEC_TEST_OTELCOL_ZPAGES_PORT")) or 55679,
  OTELCOL_FILE_EXPORTER_PATH = os.getenv("KONG_SPEC_TEST_OTELCOL_FILE_EXPORTER_PATH") or "./tmp/otel/file_exporter.json",
  REDIS_HOST = os.getenv("KONG_SPEC_TEST_REDIS_HOST") or "localhost",
  REDIS_PORT = tonumber(os.getenv("KONG_SPEC_TEST_REDIS_PORT") or 6379),
  REDIS_SSL_PORT = tonumber(os.getenv("KONG_SPEC_TEST_REDIS_SSL_PORT") or 6380),
  REDIS_AUTH_PORT = tonumber(os.getenv("KONG_SPEC_TEST_REDIS_AUTH_PORT") or 6385),
  REDIS_SSL_SNI = os.getenv("KONG_SPEC_TEST_REDIS_SSL_SNI") or "test-redis.example.com",
  TEST_COVERAGE_MODE = os.getenv("KONG_COVERAGE"),
  TEST_COVERAGE_TIMEOUT = 30,

  -- consistent with path set in .github/workflows/build_and_test.yml and build/dockerfiles/deb.pongo.Dockerfile
  -- XXX EE
  OLD_VERSION_KONG_PATH = os.getenv("KONG_SPEC_TEST_OLD_VERSION_KONG_PATH") or "/usr/local/share/lua/5.1/kong/kong-ee-old",

  BLACKHOLE_HOST = "10.255.255.255",
  KONG_VERSION = require("kong.meta")._VERSION,
}


return CONSTANTS
