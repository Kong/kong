-- This software is copyright Kong Inc. and its licensors.
-- Use of the software is subject to the agreement between your organization
-- and Kong Inc. If there is no such agreement, use is governed by and
-- subject to the terms of the Kong Master Software License Agreement found
-- at https://konghq.com/enterprisesoftwarelicense/.
-- [ END OF LICENSE 0867164ffc95e54f04670b5169c09574bdbd9bba ]

local cjson = require("cjson")
local tablex = require("pl.tablex")

local TESTS = {
  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        certificates = {
          {
            cert = "-----BEGIN CERTIFICATE-----\
MIICIzCCAYSgAwIBAgIUUMiD8e3GDZ+vs7XBmdXzMxARUrgwCgYIKoZIzj0EAwIw\
IzENMAsGA1UECgwES29uZzESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTIyMTIzMDA0\
MDcwOFoXDTQyMTIyNTA0MDcwOFowIzENMAsGA1UECgwES29uZzESMBAGA1UEAwwJ\
bG9jYWxob3N0MIGbMBAGByqGSM49AgEGBSuBBAAjA4GGAAQBxSldGzzRAtjt825q\
Uwl+BNgxecswnvbQFLiUDqJjVjCfs/B53xQfV97ddxsRymES2viC2kjAm1Ete4TH\
CQmVltUBItHzI77HB+UsfqHoUdjl3lC/HC1yDSPBp5wd9eRRSagdl0eiJwnB9lof\
MEnmOQLg177trb/YPz1vcCCZj7ikhzCjUzBRMB0GA1UdDgQWBBSUI6+CKqKFz/Te\
ZJppMNl/Dh6d9DAfBgNVHSMEGDAWgBSUI6+CKqKFz/TeZJppMNl/Dh6d9DAPBgNV\
HRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA4GMADCBiAJCAZL3qX21MnGtQcl9yOMr\
hNR54VrDKgqLR+ChU7/358n/sK/sVOjmrwVyQ52oUyqaQlfBQS2EufQVO/01+2sx\
86gzAkIB/4Ilf4RluN2/gqHYlVEDRZzsqbwVJBHLeNKsZBSJkhNNpJBwa2Ndl9/i\
u2tDk0KZFSAvRnqRAo9iDBUkIUI1ahA=\
-----END CERTIFICATE-----",
            key = "-----BEGIN EC PRIVATE KEY-----\
MIHcAgEBBEIARPKnAYLB54bxBvkDfqV4NfZ+Mxl79rlaYRB6vbWVwFpy+E2pSZBR\
doCy1tHAB/uPo+QJyjIK82Zwa3Kq0i1D2QigBwYFK4EEACOhgYkDgYYABAHFKV0b\
PNEC2O3zbmpTCX4E2DF5yzCe9tAUuJQOomNWMJ+z8HnfFB9X3t13GxHKYRLa+ILa\
SMCbUS17hMcJCZWW1QEi0fMjvscH5Sx+oehR2OXeUL8cLXINI8GnnB315FFJqB2X\
R6InCcH2Wh8wSeY5AuDXvu2tv9g/PW9wIJmPuKSHMA==\
-----END EC PRIVATE KEY-----",
            tags = {
              "certificate-01",
            },
          },
          {
            cert = "-----BEGIN CERTIFICATE-----\
MIICIzCCAYSgAwIBAgIUUMiD8e3GDZ+vs7XBmdXzMxARUrgwCgYIKoZIzj0EAwIw\
IzENMAsGA1UECgwES29uZzESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTIyMTIzMDA0\
MDcwOFoXDTQyohnoooooooooooooooooooooooooooooooooooooooooooasdfa\
Uwl+BNgxecswnvbQFLiUDqJjVjCfs/B53xQfV97ddxsRymES2viC2kjAm1Ete4TH\
CQmVltUBItHzI77AAAAAAAAAAAAAAAC/HC1yDSBBBBBBBBBBBBBdl0eiJwnB9lof\
MEnmOQLg177trb/AAAAAAAAAAAAAAACjUzBRMBBBBBBBBBBBBBBUI6+CKqKFz/Te\
ZJppMNl/Dh6d9DAAAAAAAAAAAAAAAASUI6+CKqBBBBBBBBBBBBB/Dh6d9DAPBgNV\
HRMBAf8EBTADAQHAAAAAAAAAAAAAAAMCA4GMADBBBBBBBBBBBBB1MnGtQcl9yOMr\
hNR54VrDKgqLR+CAAAAAAAAAAAAAAAjmrwVyQ5BBBBBBBBBBBBBEufQVO/01+2sx\
86gzAkIB/4Ilf4RluN2/gqHYlVEDRZzsqbwVJBHLeNKsZBSJkhNNpJBwa2Ndl9/i\
u2tDk0KZFSAvRnqRAo9iDBUkIUI1ahA=\
-----END CERTIFICATE-----",
            key = "-----BEGIN EC PRIVATE KEY-----\
MIHcAgEBBEIARPKnAYLB54bxBvkDfqV4NfZ+Mxl79rlaYRB6vbWVwFpy+E2pSZBR\
doCy1tHAB/uPo+QJyjIK82Zwa3Kq0i1D2QigBwYFK4EEACOhgYkDgYYABAHFKV0b\
PNEC2O3zbmpTCX4E2DF5yzCe9tAUuJQOomNWMJ+z8HnfFB9X3t13GxHKYRLa+ILa\
SMCbUS17hMcJCZWW1QEi0fMjvscH5Sx+oehR2OXeUL8cLXINI8GnnB315FFJqB2X\
R6InCcH2Wh8wSeY5AuDXvu2tv9g/PW9wIJmPuKSHMA==\
-----END EC PRIVATE KEY-----",
            tags = {
              "certificate-02",
            },
          },
        },
        consumers = {
          {
            tags = {
              "consumer-01",
            },
            username = "valid_user",
          },
          {
            not_allowed = true,
            tags = {
              "consumer-02",
            },
            username = "bobby_in_json_body",
          },
          {
            tags = {
              "consumer-03",
            },
            username = "super_valid_user",
          },
          {
            basicauth_credentials = {
              {
                password = "hard2guess",
                tags = {
                  "basicauth_credentials-01",
                  "consumer-04",
                },
                username = "superduper",
              },
              {
                extra_field = "NO!",
                password = "12354",
                tags = {
                  "basicauth_credentials-02",
                  "consumer-04",
                },
                username = "dont-add-extra-fields-yo",
              },
            },
            tags = {
              "consumer-04",
            },
            username = "credentials",
          },
        },
        plugins = {
          {
            config = {
              http_endpoint = "invalid::#//url",
            },
            name = "http-log",
            tags = {
              "global_plugin-01",
            },
          },
        },
        services = {
          {
            host = "localhost",
            name = "nope",
            port = 1234,
            protocol = "nope",
            routes = {
              {
                hosts = {
                  "test",
                },
                methods = {
                  "GET",
                },
                name = "valid.route",
                protocols = {
                  "http",
                  "https",
                },
                tags = {
                  "route_service-01",
                  "service-01",
                },
              },
              {
                name = "nope.route",
                protocols = {
                  "tcp",
                },
                tags = {
                  "route_service-02",
                  "service-01",
                },
              },
            },
            tags = {
              "service-01",
            },
          },
          {
            host = "localhost",
            name = "mis-matched",
            path = "/path",
            protocol = "tcp",
            routes = {
              {
                hosts = {
                  "test",
                },
                methods = {
                  "GET",
                },
                name = "invalid",
                protocols = {
                  "http",
                  "https",
                },
                tags = {
                  "route_service-03",
                  "service-02",
                },
              },
            },
            tags = {
              "service-02",
            },
          },
          {
            name = "okay",
            routes = {
              {
                hosts = {
                  "test",
                },
                methods = {
                  "GET",
                },
                name = "probably-valid",
                plugins = {
                  {
                    config = {
                      not_endpoint = "anything",
                    },
                    name = "http-log",
                    tags = {
                      "route_service_plugin-01",
                      "route_service-04",
                      "service-03",
                    },
                  },
                },
                protocols = {
                  "http",
                  "https",
                },
                tags = {
                  "route_service-04",
                  "service-03",
                },
              },
            },
            tags = {
              "service-03",
            },
            url = "http://localhost:1234",
          },
          {
            name = "bad-service-plugins",
            plugins = {
              {
                config = {},
                name = "i-dont-exist",
                tags = {
                  "service_plugin-01",
                  "service-04",
                },
              },
              {
                config = {
                  deeply = {
                    nested = {
                      undefined = true,
                    },
                  },
                  port = 1234,
                },
                name = "tcp-log",
                tags = {
                  "service_plugin-02",
                  "service-04",
                },
              },
            },
            tags = {
              "service-04",
            },
            url = "http://localhost:1234",
          },
          {
            client_certificate = {
              cert = "",
              key = "",
              tags = {
                "service_client_certificate-01",
                "service-05",
              },
            },
            name = "bad-client-cert",
            tags = {
              "service-05",
            },
            url = "https://localhost:1234",
          },
          {
            id = 123456,
            name = "invalid-id",
            tags = {
              "service-06",
              "invalid-id",
            },
            url = "https://localhost:1234",
          },
          {
            name = "invalid-tags",
            tags = {
              "service-07",
              "invalid-tags",
              {
                1,
                2,
                3,
              },
              true,
            },
            url = "https://localhost:1234",
          },
          {
            name = "",
            tags = {
              "service-08",
              "invalid_service_name-01",
            },
            url = "https://localhost:1234",
          },
          {
            name = 1234,
            tags = {
              "service-09",
              "invalid_service_name-02",
            },
            url = "https://localhost:1234",
          },
        },
        upstreams = {
          {
            hash_on = "ip",
            name = "ok",
            tags = {
              "upstream-01",
            },
          },
          {
            hash_on = "ip",
            healthchecks = {
              active = {
                concurrency = -1,
                healthy = {
                  interval = 0,
                  successes = 0,
                },
                http_path = "/",
                https_sni = "example.com",
                https_verify_certificate = true,
                timeout = 1,
                type = "http",
                unhealthy = {
                  http_failures = 0,
                  interval = 0,
                },
              },
            },
            host_header = 123,
            name = "bad",
            tags = {
              "upstream-02",
            },
          },
          {
            name = "ok-bad-targets",
            tags = {
              "upstream-03",
            },
            targets = {
              {
                tags = {
                  "upstream_target-01",
                  "upstream-03",
                },
                target = "127.0.0.1:99",
              },
              {
                tags = {
                  "upstream_target-02",
                  "upstream-03",
                },
                target = "hostname:1.0",
              },
            },
          },
        },
        vaults = {
          {
            config = {
              prefix = "SSL_",
            },
            name = "env",
            prefix = "test",
            tags = {
              "vault-01",
            },
          },
          {
            config = {
              prefix = "SSL_",
            },
            name = "vault-not-installed",
            prefix = "env",
            tags = {
              "vault-02",
              "vault-not-installed",
            },
          },
        },
      },
      err_t = {
        certificates = {
          nil,
          {
            cert = "invalid certificate: x509.new: error:688010A:asn1 encoding routines:asn1_item_embed_d2i:nested asn1 error:asn1/tasn_dec.c:349:",
          },
        },
        consumers = {
          nil,
          {
            not_allowed = "unknown field",
          },
          nil,
          {
            basicauth_credentials = {
              nil,
              {
                extra_field = "unknown field",
              },
            },
          },
        },
        plugins = {
          {
            config = {
              http_endpoint = "missing host in url",
            },
          },
        },
        services = {
          {
            protocol = "expected one of: grpc, grpcs, http, https, tcp, tls, tls_passthrough, udp",
            routes = {
              nil,
              {
                ["@entity"] = {
                  "must set one of 'sources', 'destinations', 'snis' when 'protocols' is 'tcp', 'tls' or 'udp'",
                },
              },
            },
          },
          {
            ["@entity"] = {
              "failed conditional validation given value of field 'protocol'",
            },
            path = "value must be null",
          },
          {
            routes = {
              {
                plugins = {
                  {
                    config = {
                      http_endpoint = "required field missing",
                      not_endpoint = "unknown field",
                    },
                  },
                },
              },
            },
          },
          {
            plugins = {
              {
                name = "plugin 'i-dont-exist' not enabled; add it to the 'plugins' configuration property",
              },
              {
                config = {
                  deeply = "unknown field",
                  host = "required field missing",
                },
              },
            },
          },
          {
            client_certificate = {
              cert = "length must be at least 1",
              key = "length must be at least 1",
            },
          },
          {
            id = "expected a string",
          },
          {
            tags = {
              nil,
              nil,
              "expected a string",
              "expected a string",
            },
          },
          {
            name = "length must be at least 1",
          },
          {
            name = "expected a string",
          },
        },
        upstreams = {
          nil,
          {
            healthchecks = {
              active = {
                concurrency = "value should be between 1 and 2147483648",
              },
            },
            host_header = "expected a string",
          },
          {
            targets = {
              nil,
              {
                target = "Invalid target ('hostname:1.0'); not a valid hostname or ip address",
              },
            },
          },
        },
        vaults = {
          nil,
          {
            name = "vault 'vault-not-installed' is not installed",
          },
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {},
        flattened_errors = {
          {
            entity = {
              config = {
                prefix = "SSL_",
              },
              name = "vault-not-installed",
              prefix = "env",
              tags = {
                "vault-02",
                "vault-not-installed",
              },
            },
            entity_name = "vault-not-installed",
            entity_tags = {
              "vault-02",
              "vault-not-installed",
            },
            entity_type = "vault",
            errors = {
              {
                field = "name",
                message = "vault 'vault-not-installed' is not installed",
                type = "field",
              },
            },
          },
          {
            entity = {
              tags = {
                "upstream_target-02",
                "upstream-03",
              },
              target = "hostname:1.0",
            },
            entity_tags = {
              "upstream_target-02",
              "upstream-03",
            },
            entity_type = "target",
            errors = {
              {
                field = "target",
                message = "Invalid target ('hostname:1.0'); not a valid hostname or ip address",
                type = "field",
              },
            },
          },
          {
            entity = {
              hash_on = "ip",
              healthchecks = {
                active = {
                  concurrency = -1,
                  healthy = {
                    interval = 0,
                    successes = 0,
                  },
                  http_path = "/",
                  https_sni = "example.com",
                  https_verify_certificate = true,
                  timeout = 1,
                  type = "http",
                  unhealthy = {
                    http_failures = 0,
                    interval = 0,
                  },
                },
              },
              host_header = 123,
              name = "bad",
              tags = {
                "upstream-02",
              },
            },
            entity_name = "bad",
            entity_tags = {
              "upstream-02",
            },
            entity_type = "upstream",
            errors = {
              {
                field = "host_header",
                message = "expected a string",
                type = "field",
              },
              {
                field = "healthchecks.active.concurrency",
                message = "value should be between 1 and 2147483648",
                type = "field",
              },
            },
          },
          {
            entity = {
              name = 1234,
              tags = {
                "service-09",
                "invalid_service_name-02",
              },
              url = "https://localhost:1234",
            },
            entity_tags = {
              "service-09",
              "invalid_service_name-02",
            },
            entity_type = "service",
            errors = {
              {
                field = "name",
                message = "expected a string",
                type = "field",
              },
            },
          },
          {
            entity = {
              name = "",
              tags = {
                "service-08",
                "invalid_service_name-01",
              },
              url = "https://localhost:1234",
            },
            entity_tags = {
              "service-08",
              "invalid_service_name-01",
            },
            entity_type = "service",
            errors = {
              {
                field = "name",
                message = "length must be at least 1",
                type = "field",
              },
            },
          },
          {
            entity = {
              name = "invalid-tags",
              tags = {
                "service-07",
                "invalid-tags",
                {
                  1,
                  2,
                  3,
                },
                true,
              },
              url = "https://localhost:1234",
            },
            entity_name = "invalid-tags",
            entity_type = "service",
            errors = {
              {
                field = "tags.4",
                message = "expected a string",
                type = "field",
              },
              {
                field = "tags.3",
                message = "expected a string",
                type = "field",
              },
            },
          },
          {
            entity = {
              id = 123456,
              name = "invalid-id",
              tags = {
                "service-06",
                "invalid-id",
              },
              url = "https://localhost:1234",
            },
            entity_name = "invalid-id",
            entity_tags = {
              "service-06",
              "invalid-id",
            },
            entity_type = "service",
            errors = {
              {
                field = "id",
                message = "expected a string",
                type = "field",
              },
            },
          },
          {
            entity = {
              cert = "",
              key = "",
              tags = {
                "service_client_certificate-01",
                "service-05",
              },
            },
            entity_tags = {
              "service_client_certificate-01",
              "service-05",
            },
            entity_type = "certificate",
            errors = {
              {
                field = "key",
                message = "length must be at least 1",
                type = "field",
              },
              {
                field = "cert",
                message = "length must be at least 1",
                type = "field",
              },
            },
          },
          {
            entity = {
              config = {},
              name = "i-dont-exist",
              tags = {
                "service_plugin-01",
                "service-04",
              },
            },
            entity_name = "i-dont-exist",
            entity_tags = {
              "service_plugin-01",
              "service-04",
            },
            entity_type = "plugin",
            errors = {
              {
                field = "name",
                message = "plugin 'i-dont-exist' not enabled; add it to the 'plugins' configuration property",
                type = "field",
              },
            },
          },
          {
            entity = {
              config = {
                deeply = {
                  nested = {
                    undefined = true,
                  },
                },
                port = 1234,
              },
              name = "tcp-log",
              tags = {
                "service_plugin-02",
                "service-04",
              },
            },
            entity_name = "tcp-log",
            entity_tags = {
              "service_plugin-02",
              "service-04",
            },
            entity_type = "plugin",
            errors = {
              {
                field = "config.host",
                message = "required field missing",
                type = "field",
              },
              {
                field = "config.deeply",
                message = "unknown field",
                type = "field",
              },
            },
          },
          {
            entity = {
              config = {
                not_endpoint = "anything",
              },
              name = "http-log",
              tags = {
                "route_service_plugin-01",
                "route_service-04",
                "service-03",
              },
            },
            entity_name = "http-log",
            entity_tags = {
              "route_service_plugin-01",
              "route_service-04",
              "service-03",
            },
            entity_type = "plugin",
            errors = {
              {
                field = "config.not_endpoint",
                message = "unknown field",
                type = "field",
              },
              {
                field = "config.http_endpoint",
                message = "required field missing",
                type = "field",
              },
            },
          },
          {
            entity = {
              host = "localhost",
              name = "mis-matched",
              path = "/path",
              protocol = "tcp",
              tags = {
                "service-02",
              },
            },
            entity_name = "mis-matched",
            entity_tags = {
              "service-02",
            },
            entity_type = "service",
            errors = {
              {
                field = "path",
                message = "value must be null",
                type = "field",
              },
              {
                message = "failed conditional validation given value of field 'protocol'",
                type = "entity",
              },
            },
          },
          {
            entity = {
              name = "nope.route",
              protocols = {
                "tcp",
              },
              tags = {
                "route_service-02",
                "service-01",
              },
            },
            entity_name = "nope.route",
            entity_tags = {
              "route_service-02",
              "service-01",
            },
            entity_type = "route",
            errors = {
              {
                message = "must set one of 'sources', 'destinations', 'snis' when 'protocols' is 'tcp', 'tls' or 'udp'",
                type = "entity",
              },
            },
          },
          {
            entity = {
              host = "localhost",
              name = "nope",
              port = 1234,
              protocol = "nope",
              tags = {
                "service-01",
              },
            },
            entity_name = "nope",
            entity_tags = {
              "service-01",
            },
            entity_type = "service",
            errors = {
              {
                field = "protocol",
                message = "expected one of: grpc, grpcs, http, https, tcp, tls, tls_passthrough, udp",
                type = "field",
              },
            },
          },
          {
            entity = {
              config = {
                http_endpoint = "invalid::#//url",
              },
              name = "http-log",
              tags = {
                "global_plugin-01",
              },
            },
            entity_name = "http-log",
            entity_tags = {
              "global_plugin-01",
            },
            entity_type = "plugin",
            errors = {
              {
                field = "config.http_endpoint",
                message = "missing host in url",
                type = "field",
              },
            },
          },
          {
            entity = {
              extra_field = "NO!",
              password = "12354",
              tags = {
                "basicauth_credentials-02",
                "consumer-04",
              },
              username = "dont-add-extra-fields-yo",
            },
            entity_tags = {
              "basicauth_credentials-02",
              "consumer-04",
            },
            entity_type = "basicauth_credential",
            errors = {
              {
                field = "extra_field",
                message = "unknown field",
                type = "field",
              },
            },
          },
          {
            entity = {
              not_allowed = true,
              tags = {
                "consumer-02",
              },
              username = "bobby_in_json_body",
            },
            entity_tags = {
              "consumer-02",
            },
            entity_type = "consumer",
            errors = {
              {
                field = "not_allowed",
                message = "unknown field",
                type = "field",
              },
            },
          },
          {
            entity = {
              cert = "-----BEGIN CERTIFICATE-----\
MIICIzCCAYSgAwIBAgIUUMiD8e3GDZ+vs7XBmdXzMxARUrgwCgYIKoZIzj0EAwIw\
IzENMAsGA1UECgwES29uZzESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTIyMTIzMDA0\
MDcwOFoXDTQyohnoooooooooooooooooooooooooooooooooooooooooooasdfa\
Uwl+BNgxecswnvbQFLiUDqJjVjCfs/B53xQfV97ddxsRymES2viC2kjAm1Ete4TH\
CQmVltUBItHzI77AAAAAAAAAAAAAAAC/HC1yDSBBBBBBBBBBBBBdl0eiJwnB9lof\
MEnmOQLg177trb/AAAAAAAAAAAAAAACjUzBRMBBBBBBBBBBBBBBUI6+CKqKFz/Te\
ZJppMNl/Dh6d9DAAAAAAAAAAAAAAAASUI6+CKqBBBBBBBBBBBBB/Dh6d9DAPBgNV\
HRMBAf8EBTADAQHAAAAAAAAAAAAAAAMCA4GMADBBBBBBBBBBBBB1MnGtQcl9yOMr\
hNR54VrDKgqLR+CAAAAAAAAAAAAAAAjmrwVyQ5BBBBBBBBBBBBBEufQVO/01+2sx\
86gzAkIB/4Ilf4RluN2/gqHYlVEDRZzsqbwVJBHLeNKsZBSJkhNNpJBwa2Ndl9/i\
u2tDk0KZFSAvRnqRAo9iDBUkIUI1ahA=\
-----END CERTIFICATE-----",
              key = "-----BEGIN EC PRIVATE KEY-----\
MIHcAgEBBEIARPKnAYLB54bxBvkDfqV4NfZ+Mxl79rlaYRB6vbWVwFpy+E2pSZBR\
doCy1tHAB/uPo+QJyjIK82Zwa3Kq0i1D2QigBwYFK4EEACOhgYkDgYYABAHFKV0b\
PNEC2O3zbmpTCX4E2DF5yzCe9tAUuJQOomNWMJ+z8HnfFB9X3t13GxHKYRLa+ILa\
SMCbUS17hMcJCZWW1QEi0fMjvscH5Sx+oehR2OXeUL8cLXINI8GnnB315FFJqB2X\
R6InCcH2Wh8wSeY5AuDXvu2tv9g/PW9wIJmPuKSHMA==\
-----END EC PRIVATE KEY-----",
              tags = {
                "certificate-02",
              },
            },
            entity_tags = {
              "certificate-02",
            },
            entity_type = "certificate",
            errors = {
              {
                field = "cert",
                message = "invalid certificate: x509.new: error:688010A:asn1 encoding routines:asn1_item_embed_d2i:nested asn1 error:asn1/tasn_dec.c:349:",
                type = "field",
              },
            },
          },
        },
        message = "declarative config is invalid: {}",
        name = "invalid declarative configuration",
      },
    },
  },

  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        upstreams = {
          {
            hash_on = "ip",
            healthchecks = {
              active = {
                concurrency = -1,
                healthy = {
                  interval = 0,
                  successes = 0,
                },
                http_path = "/",
                https_sni = "example.com",
                https_verify_certificate = true,
                timeout = 1,
                type = "http",
                unhealthy = {
                  http_failures = 0,
                  interval = 0,
                },
              },
            },
            host_header = 123,
            name = "bad",
            tags = {
              "upstream-01",
            },
          },
        },
      },
      err_t = {
        upstreams = {
          {
            healthchecks = {
              active = {
                concurrency = "value should be between 1 and 2147483648",
              },
            },
            host_header = "expected a string",
          },
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {},
        flattened_errors = {
          {
            entity = {
              hash_on = "ip",
              healthchecks = {
                active = {
                  concurrency = -1,
                  healthy = {
                    interval = 0,
                    successes = 0,
                  },
                  http_path = "/",
                  https_sni = "example.com",
                  https_verify_certificate = true,
                  timeout = 1,
                  type = "http",
                  unhealthy = {
                    http_failures = 0,
                    interval = 0,
                  },
                },
              },
              host_header = 123,
              name = "bad",
              tags = {
                "upstream-01",
              },
            },
            entity_name = "bad",
            entity_tags = {
              "upstream-01",
            },
            entity_type = "upstream",
            errors = {
              {
                field = "host_header",
                message = "expected a string",
                type = "field",
              },
              {
                field = "healthchecks.active.concurrency",
                message = "value should be between 1 and 2147483648",
                type = "field",
              },
            },
          },
        },
        message = "declarative config is invalid: {}",
        name = "invalid declarative configuration",
      },
    },
  },

  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        services = {
          {
            client_certificate = {
              cert = "",
              key = "",
              tags = {
                "service_client_certificate-01",
                "service-01",
              },
            },
            name = "bad-client-cert",
            plugins = {
              {
                config = {},
                name = "i-do-not-exist",
                tags = {
                  "service_plugin-01",
                },
              },
            },
            routes = {
              {
                hosts = {
                  "test",
                },
                paths = {
                  "/",
                },
                plugins = {
                  {
                    config = {
                      a = {
                        b = {
                          c = "def",
                        },
                      },
                    },
                    name = "http-log",
                    tags = {
                      "route_service_plugin-01",
                    },
                  },
                },
                protocols = {
                  "http",
                },
                tags = {
                  "service_route-01",
                },
              },
              {
                hosts = {
                  "invalid",
                },
                paths = {
                  "/",
                },
                protocols = {
                  "nope",
                },
                tags = {
                  "service_route-02",
                },
              },
            },
            tags = {
              "service-01",
            },
            url = "https://localhost:1234",
          },
        },
      },
      err_t = {
        services = {
          {
            client_certificate = {
              cert = "length must be at least 1",
              key = "length must be at least 1",
            },
            plugins = {
              {
                name = "plugin 'i-do-not-exist' not enabled; add it to the 'plugins' configuration property",
              },
            },
            routes = {
              {
                plugins = {
                  {
                    config = {
                      a = "unknown field",
                      http_endpoint = "required field missing",
                    },
                  },
                },
              },
              {
                protocols = "unknown type: nope",
              },
            },
          },
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {},
        flattened_errors = {
          {
            entity = {
              config = {},
              name = "i-do-not-exist",
              tags = {
                "service_plugin-01",
              },
            },
            entity_name = "i-do-not-exist",
            entity_tags = {
              "service_plugin-01",
            },
            entity_type = "plugin",
            errors = {
              {
                field = "name",
                message = "plugin 'i-do-not-exist' not enabled; add it to the 'plugins' configuration property",
                type = "field",
              },
            },
          },
          {
            entity = {
              cert = "",
              key = "",
              tags = {
                "service_client_certificate-01",
                "service-01",
              },
            },
            entity_tags = {
              "service_client_certificate-01",
              "service-01",
            },
            entity_type = "certificate",
            errors = {
              {
                field = "key",
                message = "length must be at least 1",
                type = "field",
              },
              {
                field = "cert",
                message = "length must be at least 1",
                type = "field",
              },
            },
          },
          {
            entity = {
              config = {
                a = {
                  b = {
                    c = "def",
                  },
                },
              },
              name = "http-log",
              tags = {
                "route_service_plugin-01",
              },
            },
            entity_name = "http-log",
            entity_tags = {
              "route_service_plugin-01",
            },
            entity_type = "plugin",
            errors = {
              {
                field = "config.http_endpoint",
                message = "required field missing",
                type = "field",
              },
              {
                field = "config.a",
                message = "unknown field",
                type = "field",
              },
            },
          },
          {
            entity = {
              hosts = {
                "invalid",
              },
              paths = {
                "/",
              },
              protocols = {
                "nope",
              },
              tags = {
                "service_route-02",
              },
            },
            entity_tags = {
              "service_route-02",
            },
            entity_type = "route",
            errors = {
              {
                field = "protocols",
                message = "unknown type: nope",
                type = "field",
              },
            },
          },
        },
        message = "declarative config is invalid: {}",
        name = "invalid declarative configuration",
      },
    },
  },

  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        consumers = {
          {
            basicauth_credentials = {
              {
                id = "089091f4-cb8b-48f5-8463-8319097be716",
                password = "pwd",
                tags = {
                  "consumer-01-credential-01",
                },
                username = "user-01",
              },
              {
                id = "b1443d61-ccd9-4359-b82a-f37515442295",
                password = "pwd",
                tags = {
                  "consumer-01-credential-02",
                },
                username = "user-11",
              },
              {
                id = "2603d010-edbe-4713-94ef-145e281cbf4c",
                password = "pwd",
                tags = {
                  "consumer-01-credential-03",
                },
                username = "user-02",
              },
              {
                id = "760cf441-613c-48a2-b377-36aebc9f9ed0",
                password = "pwd",
                tags = {
                  "consumer-01-credential-04",
                },
                username = "user-11",
              },
            },
            id = "cdac30ee-cd7e-465c-99b6-84f3e4e17015",
            tags = {
              "consumer-01",
            },
            username = "consumer-01",
          },
          {
            basicauth_credentials = {
              {
                id = "d0cd1919-bb07-4c85-b407-f33feb74f6e2",
                password = "pwd",
                tags = {
                  "consumer-02-credential-01",
                },
                username = "user-99",
              },
            },
            id = "c0c021f5-dae1-4031-bcf6-42e3c4d9ced9",
            tags = {
              "consumer-02",
            },
            username = "consumer-02",
          },
          {
            basicauth_credentials = {
              {
                id = "7e8bcd10-cdcd-41f1-8c4d-9790d34aa67d",
                password = "pwd",
                tags = {
                  "consumer-03-credential-01",
                },
                username = "user-01",
              },
              {
                id = "7fe186bd-44e5-4b97-854d-85a24929889d",
                password = "pwd",
                tags = {
                  "consumer-03-credential-02",
                },
                username = "user-33",
              },
              {
                id = "6547c325-5332-41fc-a954-d4972926cdb5",
                password = "pwd",
                tags = {
                  "consumer-03-credential-03",
                },
                username = "user-02",
              },
              {
                id = "e091a955-9ee1-4403-8d0a-a7f1f8bafaca",
                password = "pwd",
                tags = {
                  "consumer-03-credential-04",
                },
                username = "user-33",
              },
            },
            id = "9acb0270-73aa-4968-b9e4-a4924e4aced5",
            tags = {
              "consumer-03",
            },
            username = "consumer-03",
          },
        },
      },
      err_t = {
        consumers = {
          {
            basicauth_credentials = {
              nil,
              nil,
              nil,
              "uniqueness violation: 'basicauth_credentials' entity with username set to 'user-11' already declared",
            },
          },
          nil,
          {
            basicauth_credentials = {
              "uniqueness violation: 'basicauth_credentials' entity with username set to 'user-01' already declared",
              nil,
              "uniqueness violation: 'basicauth_credentials' entity with username set to 'user-02' already declared",
              "uniqueness violation: 'basicauth_credentials' entity with username set to 'user-33' already declared",
            },
          },
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {},
        flattened_errors = {
          {
            entity = {
              consumer = {
                id = "9acb0270-73aa-4968-b9e4-a4924e4aced5",
              },
              id = "7e8bcd10-cdcd-41f1-8c4d-9790d34aa67d",
              password = "pwd",
              tags = {
                "consumer-03-credential-01",
              },
              username = "user-01",
            },
            entity_id = "7e8bcd10-cdcd-41f1-8c4d-9790d34aa67d",
            entity_tags = {
              "consumer-03-credential-01",
            },
            entity_type = "basicauth_credential",
            errors = {
              {
                message = "uniqueness violation: 'basicauth_credentials' entity with username set to 'user-01' already declared",
                type = "entity",
              },
            },
          },
          {
            entity = {
              consumer = {
                id = "9acb0270-73aa-4968-b9e4-a4924e4aced5",
              },
              id = "6547c325-5332-41fc-a954-d4972926cdb5",
              password = "pwd",
              tags = {
                "consumer-03-credential-03",
              },
              username = "user-02",
            },
            entity_id = "6547c325-5332-41fc-a954-d4972926cdb5",
            entity_tags = {
              "consumer-03-credential-03",
            },
            entity_type = "basicauth_credential",
            errors = {
              {
                message = "uniqueness violation: 'basicauth_credentials' entity with username set to 'user-02' already declared",
                type = "entity",
              },
            },
          },
          {
            entity = {
              consumer = {
                id = "9acb0270-73aa-4968-b9e4-a4924e4aced5",
              },
              id = "e091a955-9ee1-4403-8d0a-a7f1f8bafaca",
              password = "pwd",
              tags = {
                "consumer-03-credential-04",
              },
              username = "user-33",
            },
            entity_id = "e091a955-9ee1-4403-8d0a-a7f1f8bafaca",
            entity_tags = {
              "consumer-03-credential-04",
            },
            entity_type = "basicauth_credential",
            errors = {
              {
                message = "uniqueness violation: 'basicauth_credentials' entity with username set to 'user-33' already declared",
                type = "entity",
              },
            },
          },
          {
            entity = {
              consumer = {
                id = "cdac30ee-cd7e-465c-99b6-84f3e4e17015",
              },
              id = "760cf441-613c-48a2-b377-36aebc9f9ed0",
              password = "pwd",
              tags = {
                "consumer-01-credential-04",
              },
              username = "user-11",
            },
            entity_id = "760cf441-613c-48a2-b377-36aebc9f9ed0",
            entity_tags = {
              "consumer-01-credential-04",
            },
            entity_type = "basicauth_credential",
            errors = {
              {
                message = "uniqueness violation: 'basicauth_credentials' entity with username set to 'user-11' already declared",
                type = "entity",
              },
            },
          },
        },
        message = "declarative config is invalid: {}",
        name = "invalid declarative configuration",
      },
    },
  },

  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        services = {
          {
            host = "localhost",
            id = "0175e0e8-3de9-56b4-96f1-b12dcb4b6691",
            name = "nope",
            port = 1234,
            protocol = "nope",
            tags = {
              "service-01",
            },
          },
        },
      },
      err_t = {
        services = {
          {
            protocol = "expected one of: grpc, grpcs, http, https, tcp, tls, tls_passthrough, udp",
          },
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {},
        flattened_errors = {
          {
            entity = {
              host = "localhost",
              id = "0175e0e8-3de9-56b4-96f1-b12dcb4b6691",
              name = "nope",
              port = 1234,
              protocol = "nope",
              tags = {
                "service-01",
              },
            },
            entity_id = "0175e0e8-3de9-56b4-96f1-b12dcb4b6691",
            entity_name = "nope",
            entity_tags = {
              "service-01",
            },
            entity_type = "service",
            errors = {
              {
                field = "protocol",
                message = "expected one of: grpc, grpcs, http, https, tcp, tls, tls_passthrough, udp",
                type = "field",
              },
            },
          },
        },
        message = "declarative config is invalid: {}",
        name = "invalid declarative configuration",
      },
    },
  },

  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        services = {
          {
            host = "localhost",
            id = "cb019421-62c2-47a8-b714-d7567b114037",
            name = "test",
            port = 1234,
            protocol = "nope",
            routes = {
              {
                super_duper_invalid = true,
                tags = {
                  "route-01",
                },
              },
            },
            tags = {
              "service-01",
            },
          },
        },
      },
      err_t = {
        services = {
          {
            protocol = "expected one of: grpc, grpcs, http, https, tcp, tls, tls_passthrough, udp",
            routes = {
              {
                ["@entity"] = {
                  "must set one of 'methods', 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'https'",
                },
                super_duper_invalid = "unknown field",
              },
            },
          },
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {},
        flattened_errors = {
          {
            entity = {
              service = {
                id = "cb019421-62c2-47a8-b714-d7567b114037",
              },
              super_duper_invalid = true,
              tags = {
                "route-01",
              },
            },
            entity_tags = {
              "route-01",
            },
            entity_type = "route",
            errors = {
              {
                field = "super_duper_invalid",
                message = "unknown field",
                type = "field",
              },
              {
                message = "must set one of 'methods', 'hosts', 'headers', 'paths', 'snis' when 'protocols' is 'https'",
                type = "entity",
              },
            },
          },
          {
            entity = {
              host = "localhost",
              id = "cb019421-62c2-47a8-b714-d7567b114037",
              name = "test",
              port = 1234,
              protocol = "nope",
              tags = {
                "service-01",
              },
            },
            entity_id = "cb019421-62c2-47a8-b714-d7567b114037",
            entity_name = "test",
            entity_tags = {
              "service-01",
            },
            entity_type = "service",
            errors = {
              {
                field = "protocol",
                message = "expected one of: grpc, grpcs, http, https, tcp, tls, tls_passthrough, udp",
                type = "field",
              },
            },
          },
        },
        message = "declarative config is invalid: {}",
        name = "invalid declarative configuration",
      },
    },
  },

  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        services = {
          {
            id = 1234,
            name = false,
            tags = {
              "service-01",
              {
                1.5,
              },
            },
            url = "http://localhost:1234",
          },
        },
      },
      err_t = {
        services = {
          {
            id = "expected a string",
            name = "expected a string",
            tags = {
              nil,
              "expected a string",
            },
          },
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {},
        flattened_errors = {
          {
            entity = {
              id = 1234,
              name = false,
              tags = {
                "service-01",
                {
                  1.5,
                },
              },
              url = "http://localhost:1234",
            },
            entity_type = "service",
            errors = {
              {
                field = "tags.2",
                message = "expected a string",
                type = "field",
              },
              {
                field = "name",
                message = "expected a string",
                type = "field",
              },
              {
                field = "id",
                message = "expected a string",
                type = "field",
              },
            },
          },
        },
        message = "declarative config is invalid: {}",
        name = "invalid declarative configuration",
      },
    },
  },

  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        abnormal_extra_field = 123,
        services = {
          {
            host = "localhost",
            name = "nope",
            port = 1234,
            protocol = "nope",
            routes = {
              {
                hosts = {
                  "test",
                },
                methods = {
                  "GET",
                },
                name = "valid.route",
                protocols = {
                  "http",
                  "https",
                },
                tags = {
                  "route_service-01",
                  "service-01",
                },
              },
              {
                name = "nope.route",
                protocols = {
                  "tcp",
                },
                tags = {
                  "route_service-02",
                  "service-01",
                },
              },
            },
            tags = {
              "service-01",
            },
          },
          {
            host = "localhost",
            name = "mis-matched",
            path = "/path",
            protocol = "tcp",
            routes = {
              {
                hosts = {
                  "test",
                },
                methods = {
                  "GET",
                },
                name = "invalid",
                protocols = {
                  "http",
                  "https",
                },
                tags = {
                  "route_service-03",
                  "service-02",
                },
              },
            },
            tags = {
              "service-02",
            },
          },
          {
            name = "okay",
            routes = {
              {
                hosts = {
                  "test",
                },
                methods = {
                  "GET",
                },
                name = "probably-valid",
                plugins = {
                  {
                    config = {
                      not_endpoint = "anything",
                    },
                    name = "http-log",
                    tags = {
                      "route_service_plugin-01",
                      "route_service-04",
                      "service-03",
                    },
                  },
                },
                protocols = {
                  "http",
                  "https",
                },
                tags = {
                  "route_service-04",
                  "service-03",
                },
              },
            },
            tags = {
              "service-03",
            },
            url = "http://localhost:1234",
          },
        },
      },
      err_t = {
        abnormal_extra_field = "unknown field",
        services = {
          {
            protocol = "expected one of: grpc, grpcs, http, https, tcp, tls, tls_passthrough, udp",
            routes = {
              nil,
              {
                ["@entity"] = {
                  "must set one of 'sources', 'destinations', 'snis' when 'protocols' is 'tcp', 'tls' or 'udp'",
                },
              },
            },
          },
          {
            ["@entity"] = {
              "failed conditional validation given value of field 'protocol'",
            },
            path = "value must be null",
          },
          {
            routes = {
              {
                plugins = {
                  {
                    config = {
                      http_endpoint = "required field missing",
                      not_endpoint = "unknown field",
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {
          abnormal_extra_field = "unknown field",
        },
        flattened_errors = {
          {
            entity = {
              config = {
                not_endpoint = "anything",
              },
              name = "http-log",
              tags = {
                "route_service_plugin-01",
                "route_service-04",
                "service-03",
              },
            },
            entity_name = "http-log",
            entity_tags = {
              "route_service_plugin-01",
              "route_service-04",
              "service-03",
            },
            entity_type = "plugin",
            errors = {
              {
                field = "config.not_endpoint",
                message = "unknown field",
                type = "field",
              },
              {
                field = "config.http_endpoint",
                message = "required field missing",
                type = "field",
              },
            },
          },
          {
            entity = {
              host = "localhost",
              name = "mis-matched",
              path = "/path",
              protocol = "tcp",
              tags = {
                "service-02",
              },
            },
            entity_name = "mis-matched",
            entity_tags = {
              "service-02",
            },
            entity_type = "service",
            errors = {
              {
                field = "path",
                message = "value must be null",
                type = "field",
              },
              {
                message = "failed conditional validation given value of field 'protocol'",
                type = "entity",
              },
            },
          },
          {
            entity = {
              name = "nope.route",
              protocols = {
                "tcp",
              },
              tags = {
                "route_service-02",
                "service-01",
              },
            },
            entity_name = "nope.route",
            entity_tags = {
              "route_service-02",
              "service-01",
            },
            entity_type = "route",
            errors = {
              {
                message = "must set one of 'sources', 'destinations', 'snis' when 'protocols' is 'tcp', 'tls' or 'udp'",
                type = "entity",
              },
            },
          },
          {
            entity = {
              host = "localhost",
              name = "nope",
              port = 1234,
              protocol = "nope",
              tags = {
                "service-01",
              },
            },
            entity_name = "nope",
            entity_tags = {
              "service-01",
            },
            entity_type = "service",
            errors = {
              {
                field = "protocol",
                message = "expected one of: grpc, grpcs, http, https, tcp, tls, tls_passthrough, udp",
                type = "field",
              },
            },
          },
        },
        message = "declarative config is invalid: {abnormal_extra_field=\"unknown field\"}",
        name = "invalid declarative configuration",
      },
    },
  },

  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        consumers = {
          {
            acls = {
              {
                group = "app",
                tags = {
                  "k8s-name:app-acl",
                  "k8s-namespace:default",
                  "k8s-kind:Secret",
                  "k8s-uid:f1c5661c-a087-4c4b-b545-2d8b3870d661",
                  "k8s-version:v1",
                },
              },
            },
            basicauth_credentials = {
              {
                password = "6ef728de-ba68-4e59-acb9-6e502c28ae0b",
                tags = {
                  "k8s-name:app-cred",
                  "k8s-namespace:default",
                  "k8s-kind:Secret",
                  "k8s-uid:aadd4598-2969-49ea-82ac-6ab5159e2f2e",
                  "k8s-version:v1",
                },
                username = "774f8446-6427-43f9-9962-ce7ab8097fe4",
              },
            },
            id = "68d5de9f-2211-5ed8-b827-22f57a492d0f",
            tags = {
              "k8s-name:app",
              "k8s-namespace:default",
              "k8s-kind:KongConsumer",
              "k8s-uid:7ee19bea-72d5-402b-bf0f-f57bf81032bf",
              "k8s-group:configuration.konghq.com",
              "k8s-version:v1",
            },
            username = "774f8446-6427-43f9-9962-ce7ab8097fe4",
          },
        },
        plugins = {
          {
            config = {
              error_code = 429,
              error_message = "API rate limit exceeded",
              fault_tolerant = true,
              hide_client_headers = false,
              limit_by = "consumer",
              policy = "local",
              second = 2000,
            },
            consumer = "774f8446-6427-43f9-9962-ce7ab8097fe4",
            enabled = true,
            name = "rate-limiting",
            protocols = {
              "grpc",
              "grpcs",
              "http",
              "https",
            },
            tags = {
              "k8s-name:nginx-sample-1-rate",
              "k8s-namespace:default",
              "k8s-kind:KongPlugin",
              "k8s-uid:5163972c-543d-48ae-b0f6-21701c43c1ff",
              "k8s-group:configuration.konghq.com",
              "k8s-version:v1",
            },
          },
          {
            config = {
              error_code = 429,
              error_message = "API rate limit exceeded",
              fault_tolerant = true,
              hide_client_headers = false,
              limit_by = "consumer",
              policy = "local",
              second = 2000,
            },
            consumer = "774f8446-6427-43f9-9962-ce7ab8097fe4",
            enabled = true,
            name = "rate-limiting",
            protocols = {
              "grpc",
              "grpcs",
              "http",
              "https",
            },
            tags = {
              "k8s-name:nginx-sample-2-rate",
              "k8s-namespace:default",
              "k8s-kind:KongPlugin",
              "k8s-uid:89fa1cd1-78da-4c3e-8c3b-32be1811535a",
              "k8s-group:configuration.konghq.com",
              "k8s-version:v1",
            },
          },
          {
            config = {
              allow = {
                "nginx-sample-1",
                "app",
              },
              hide_groups_header = false,
            },
            enabled = true,
            name = "acl",
            protocols = {
              "grpc",
              "grpcs",
              "http",
              "https",
            },
            service = "default.nginx-sample-1.nginx-sample-1.80",
            tags = {
              "k8s-name:nginx-sample-1",
              "k8s-namespace:default",
              "k8s-kind:KongPlugin",
              "k8s-uid:b9373482-32e1-4ac3-bd2a-8926ab728700",
              "k8s-group:configuration.konghq.com",
              "k8s-version:v1",
            },
          },
        },
        services = {
          {
            connect_timeout = 60000,
            host = "nginx-sample-1.default.80.svc",
            id = "8c17ab3e-b6bd-51b2-b5ec-878b4d608b9d",
            name = "default.nginx-sample-1.nginx-sample-1.80",
            path = "/",
            port = 80,
            protocol = "http",
            read_timeout = 60000,
            retries = 5,
            routes = {
              {
                https_redirect_status_code = 426,
                id = "84d45463-1faa-55cf-8ef6-4285007b715e",
                methods = {
                  "GET",
                },
                name = "default.nginx-sample-1.nginx-sample-1..80",
                path_handling = "v0",
                paths = {
                  "/sample/1",
                },
                preserve_host = true,
                protocols = {
                  "http",
                  "https",
                },
                regex_priority = 0,
                request_buffering = true,
                response_buffering = true,
                strip_path = false,
                tags = {
                  "k8s-name:nginx-sample-1",
                  "k8s-namespace:default",
                  "k8s-kind:Ingress",
                  "k8s-uid:916a6e5a-eebe-4527-a78d-81963eb3e043",
                  "k8s-group:networking.k8s.io",
                  "k8s-version:v1",
                },
              },
            },
            tags = {
              "k8s-name:nginx-sample-1",
              "k8s-namespace:default",
              "k8s-kind:Service",
              "k8s-uid:f7cc87f4-d5f7-41f8-b4e3-70608017e588",
              "k8s-version:v1",
            },
            write_timeout = 60000,
          },
        },
        upstreams = {
          {
            algorithm = "round-robin",
            name = "nginx-sample-1.default.80.svc",
            tags = {
              "k8s-name:nginx-sample-1",
              "k8s-namespace:default",
              "k8s-kind:Service",
              "k8s-uid:f7cc87f4-d5f7-41f8-b4e3-70608017e588",
              "k8s-version:v1",
            },
            targets = {
              {
                target = "nginx-sample-1.default.svc:80",
              },
            },
          },
        },
      },
      err_t = {
        plugins = {
          {
            consumer = {
              id = "missing primary key",
            },
          },
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {},
        flattened_errors = {
          {
            entity = {
              config = {
                error_code = 429,
                error_message = "API rate limit exceeded",
                fault_tolerant = true,
                hide_client_headers = false,
                limit_by = "consumer",
                policy = "local",
                second = 2000,
              },
              consumer = "774f8446-6427-43f9-9962-ce7ab8097fe4",
              enabled = true,
              name = "rate-limiting",
              protocols = {
                "grpc",
                "grpcs",
                "http",
                "https",
              },
              tags = {
                "k8s-name:nginx-sample-1-rate",
                "k8s-namespace:default",
                "k8s-kind:KongPlugin",
                "k8s-uid:5163972c-543d-48ae-b0f6-21701c43c1ff",
                "k8s-group:configuration.konghq.com",
                "k8s-version:v1",
              },
            },
            entity_name = "rate-limiting",
            entity_tags = {
              "k8s-name:nginx-sample-1-rate",
              "k8s-namespace:default",
              "k8s-kind:KongPlugin",
              "k8s-uid:5163972c-543d-48ae-b0f6-21701c43c1ff",
              "k8s-group:configuration.konghq.com",
              "k8s-version:v1",
            },
            entity_type = "plugin",
            errors = {
              {
                field = "consumer.id",
                message = "missing primary key",
                type = "field",
              },
            },
          },
        },
        message = "declarative config is invalid: {}",
        name = "invalid declarative configuration",
      },
    },
  },

  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        consumers = {
          {
            id = "a73dc9a7-93df-584d-97c0-7f41a1bbce3d",
            tags = {
              "consumer-1",
            },
            username = "test-consumer-1",
          },
          {
            id = "a73dc9a7-93df-584d-97c0-7f41a1bbce32",
            tags = {
              "consumer-2",
            },
            username = "test-consumer-1",
          },
        },
      },
      err_t = {
        consumers = {
          nil,
          "uniqueness violation: 'consumers' entity with username set to 'test-consumer-1' already declared",
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {},
        flattened_errors = {
          {
            entity = {
              id = "a73dc9a7-93df-584d-97c0-7f41a1bbce32",
              tags = {
                "consumer-2",
              },
              username = "test-consumer-1",
            },
            entity_id = "a73dc9a7-93df-584d-97c0-7f41a1bbce32",
            entity_tags = {
              "consumer-2",
            },
            entity_type = "consumer",
            errors = {
              {
                message = "uniqueness violation: 'consumers' entity with username set to 'test-consumer-1' already declared",
                type = "entity",
              },
            },
          },
        },
        message = "declarative config is invalid: {}",
        name = "invalid declarative configuration",
      },
    },
  },

  {
    input = {
      config = {
        _format_version = "3.0",
        _transform = true,
        services = {
          {
            connect_timeout = 60000,
            host = "httproute.default.httproute-testing.0",
            id = "4e3cb785-a8d0-5866-aa05-117f7c64f24d",
            name = "httproute.default.httproute-testing.0",
            port = 8080,
            protocol = "http",
            read_timeout = 60000,
            retries = 5,
            routes = {
              {
                https_redirect_status_code = 426,
                id = "073fc413-1c03-50b4-8f44-43367c13daba",
                name = "httproute.default.httproute-testing.0.0",
                path_handling = "v0",
                paths = {
                  "~/httproute-testing$",
                  "/httproute-testing/",
                },
                preserve_host = true,
                protocols = {
                  "http",
                  "https",
                },
                strip_path = true,
                tags = {},
              },
            },
            tags = {},
            write_timeout = 60000,
          },
        },
        upstreams = {
          {
            algorithm = "round-robin",
            id = "e9792964-6797-482c-bfdf-08220a4f6832",
            name = "httproute.default.httproute-testing.0",
            tags = {
              "k8s-name:httproute-testing",
              "k8s-namespace:default",
              "k8s-kind:HTTPRoute",
              "k8s-uid:f9792964-6797-482c-bfdf-08220a4f6839",
              "k8s-group:gateway.networking.k8s.io",
              "k8s-version:v1",
            },
            targets = {
              {
                id = "715f9482-4236-5fe5-9ae5-e75c1a498940",
                target = "10.244.0.11:80",
                weight = 1,
              },
              {
                id = "89a2966d-773c-580a-b063-6ab4dfd24701",
                target = "10.244.0.12:80",
                weight = 1,
              },
            },
          },
          {
            algorithm = "round-robin",
            id = "f9792964-6797-482c-bfdf-08220a4f6839",
            name = "httproute.default.httproute-testing.1",
            tags = {
              "k8s-name:httproute-testing",
              "k8s-namespace:default",
              "k8s-kind:HTTPRoute",
              "k8s-uid:f9792964-6797-482c-bfdf-08220a4f6839",
              "k8s-group:gateway.networking.k8s.io",
              "k8s-version:v1",
            },
            targets = {
              {
                id = "48322e4a-b3b0-591b-8ed6-fd95a6d75019",
                tags = {
                  "target-1",
                },
                target = "10.244.0.12:80",
                weight = 1,
              },
              {
                id = "48322e4a-b3b0-591b-8ed6-fd95a6d75019",
                tags = {
                  "target-2",
                },
                target = "10.244.0.12:80",
                weight = 1,
              },
            },
          },
        },
      },
      err_t = {
        upstreams = {
          nil,
          {
            targets = {
              nil,
              "uniqueness violation: 'targets' entity with primary key set to '48322e4a-b3b0-591b-8ed6-fd95a6d75019' already declared",
            },
          },
        },
      },
    },
    output = {
      err_t = {
        code = 14,
        fields = {},
        flattened_errors = {
          {
            entity = {
              id = "48322e4a-b3b0-591b-8ed6-fd95a6d75019",
              tags = {
                "target-2",
              },
              target = "10.244.0.12:80",
              upstream = {
                id = "f9792964-6797-482c-bfdf-08220a4f6839",
              },
              weight = 1,
            },
            entity_id = "48322e4a-b3b0-591b-8ed6-fd95a6d75019",
            entity_tags = {
              "target-2",
            },
            entity_type = "target",
            errors = {
              {
                message = "uniqueness violation: 'targets' entity with primary key set to '48322e4a-b3b0-591b-8ed6-fd95a6d75019' already declared",
                type = "entity",
              },
            },
          },
        },
        message = "declarative config is invalid: {}",
        name = "invalid declarative configuration",
      },
    },
  },
}

describe("kong.db.errors.declarative_config_flattened()", function()
  local errors

  lazy_setup(function()
    -- required to initialize _G.kong for the kong.db.errors module
    require("spec.helpers")
    errors = require("kong.db.errors")
  end)

  it("flattens dbless errors into a single array", function()
    local function find_err(needle, haystack)
      for i = 1, #haystack do
        local err = haystack[i]

        if err.entity_type == needle.entity_type
          and err.entity_name == needle.entity_name
          and err.entity_id == needle.entity_id
          and tablex.deepcompare(err.entity_tags, needle.entity_tags, true)
        then
          return table.remove(haystack, i)
        end
      end
    end

    for _, elem in ipairs(TESTS) do
      local exp = elem.output.err_t
      local got = errors:declarative_config_flattened(elem.input.err_t, elem.input.config)

      local missing = {}
      for _, err in ipairs(exp.flattened_errors) do
        local found = find_err(err, got.flattened_errors)
        if found then
          assert.same(err, found)
        else
          table.insert(missing, err)
        end
      end

      for _, err in ipairs(missing) do
        assert.is_nil(err)
      end

      assert.equals(0, #got.flattened_errors)
    end

  end)

  it("retains errors that it does not understand how to flatten", function()
    local input = { foo = { [2] = "some error" } }
    local err_t = errors:declarative_config_flattened(input, {})
    assert.equals(0, #err_t.flattened_errors)
    assert.same(input, err_t.fields)
  end)

  it("ensures that `flattened_errors` encodes to a JSON array when empty", function()
    local err_t = errors:declarative_config_flattened({}, {})
    assert.is_table(err_t)
    local flattened_errors = assert.is_table(err_t.flattened_errors)
    assert.equals(0, #flattened_errors)
    assert.same(cjson.array_mt, debug.getmetatable(flattened_errors))
    assert.equals("[]", cjson.encode(flattened_errors))
  end)

  it("throws for invalid inputs", function()
    assert.has_error(function()
      errors:declarative_config_flattened()
    end)

    assert.has_error(function()
      errors:declarative_config_flattened(1, 2)
    end)

    assert.has_error(function()
      errors:declarative_config_flattened({}, 123)
    end)

    assert.has_error(function()
      errors:declarative_config_flattened(123, {})
    end)
  end)
end)
