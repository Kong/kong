return {

--------------------------------------------------------------------------------
-- Known files and entities, to compare what's coded to what's documented
--
-- We avoid automagic detection based on traversal of filesystem and modules,
-- so that adding new info to the documentation becomes a conscious process.
-- We traverse the filesystem and modules to cross-check that everything that
-- is present in the code is either documented or consciously omitted from
-- the docs (e.g. in the last stage of deprecation).
--------------------------------------------------------------------------------

  known = {
    general_files = {
      "kong/api/routes/kong.lua",
      "kong/api/routes/health.lua",
      "kong/api/routes/config.lua",
      "kong/api/routes/tags.lua",
      "kong/api/routes/clustering.lua",
    },
    nodoc_files = {
      "kong/api/routes/cache.lua", -- FIXME should we document this?
    },
    entities = {
      "services",
      "routes",
      "consumers",
      "plugins",
      "certificates",
      "ca_certificates",
      "snis",
      "upstreams",
      "targets",
    },
    nodoc_entities = {
    },
  },

--------------------------------------------------------------------------------
-- General (non-entity) Admin API route files
--------------------------------------------------------------------------------

  intro = {
    {
      text = [[
        <div class="alert alert-info.blue" role="alert">
          This page refers to the Admin API for running Kong configured with a
          database (Postgres or Cassandra). For using the Admin API for Kong
          in DB-less mode, please refer to the
          <a href="/{{page.kong_version}}/db-less-admin-api">Admin API for DB-less Mode</a>
          page.
        </div>

        Kong comes with an **internal** RESTful Admin API for administration purposes.
        Requests to the Admin API can be sent to any node in the cluster, and Kong will
        keep the configuration consistent across all nodes.

        - `8001` is the default port on which the Admin API listens.
        - `8444` is the default port for HTTPS traffic to the Admin API.

        This API is designed for internal use and provides full control over Kong, so
        care should be taken when setting up Kong environments to avoid undue public
        exposure of this API. See [this document][secure-admin-api] for a discussion
        of methods to secure the Admin API.
      ]]
    }, {
      title = [[Supported Content Types]],
      text = [[
        The Admin API accepts 2 content types on every endpoint:

        - **application/x-www-form-urlencoded**

        Simple enough for basic request bodies, you will probably use it most of the time.
        Note that when sending nested values, Kong expects nested objects to be referenced
        with dotted keys. Example:

        ```
        config.limit=10&config.period=seconds
        ```

        - **application/json**

        Handy for complex bodies (ex: complex plugin configuration), in that case simply send
        a JSON representation of the data you want to send. Example:

        ```json
        {
            "config": {
                "limit": 10,
                "period": "seconds"
            }
        }
        ```
      ]]
    },
  },

  footer = [[
    [clustering]: /{{page.kong_version}}/clustering
    [cli]: /{{page.kong_version}}/cli
    [active]: /{{page.kong_version}}/health-checks-circuit-breakers/#active-health-checks
    [healthchecks]: /{{page.kong_version}}/health-checks-circuit-breakers
    [secure-admin-api]: /{{page.kong_version}}/secure-admin-api
    [proxy-reference]: /{{page.kong_version}}/proxy
    [db-less-admin-api]: /{{page.kong_version}}/db-less-admin-api
  ]],

  general = {
    kong = {
      title = [[Information routes]],
      description = "",
      ["/"] = {
        GET = {
          title = [[Retrieve node information]],
          endpoint = [[<div class="endpoint get">/</div>]],
          description = [[Retrieve generic details about a node.]],
          response =[[
            ```
            HTTP 200 OK
            ```

            ```json
            {
                "hostname": "",
                "node_id": "6a72192c-a3a1-4c8d-95c6-efabae9fb969",
                "lua_version": "LuaJIT 2.1.0-beta3",
                "plugins": {
                    "available_on_server": [
                        ...
                    ],
                    "enabled_in_cluster": [
                        ...
                    ]
                },
                "configuration" : {
                    ...
                },
                "tagline": "Welcome to Kong",
                "version": "0.14.0"
            }
            ```

            * `node_id`: A UUID representing the running Kong node. This UUID
              is randomly generated when Kong starts, so the node will have a
              different `node_id` each time it is restarted.
            * `available_on_server`: Names of plugins that are installed on the node.
            * `enabled_in_cluster`: Names of plugins that are enabled/configured.
              That is, the plugins configurations currently in the datastore shared
              by all Kong nodes.
          ]],
        },
      },
      ["/endpoints"] = {
        GET = {
          title = [[List available endpoints]],
          endpoint = [[<div class="endpoint get">/endpoints</div>]],
          description = [[List all available endpoints provided by the Admin API.]],
          response =[[
            ```
            HTTP 200 OK
            ```

            ```json
            {
                "data": [
                    "/",
                    "/acls",
                    "/acls/{acls}",
                    "/acls/{acls}/consumer",
                    "/basic-auths",
                    "/basic-auths/{basicauth_credentials}",
                    "/basic-auths/{basicauth_credentials}/consumer",
                    "/ca_certificates",
                    "/ca_certificates/{ca_certificates}",
                    "/cache",
                    "/cache/{key}",
                    "..."
                ]
            }
            ```
          ]],
        },
      },
      ["/schemas/:db_entity_name/validate"] = {
        POST = {
          title = [[Validate a configuration against a schema]],
          endpoint = [[<div class="endpoint post">/schemas/{entity}/validate</div>]],
          description = [[
            Check validity of a configuration against its entity schema.
            This allows you to test your input before submitting a request
            to the entity endpoints of the Admin API.

            Note that this only performs the schema validation checks,
            checking that the input configuration is well-formed.
            A requests to the entity endpoint using the given configuration
            may still fail due to other reasons, such as invalid foreign
            key relationships or uniqueness check failures against the
            contents of the data store.
          ]],
          response =[[
            ```
            HTTP 200 OK
            ```

            ```json
            {
                "message": "schema validation successful"
            }
            ```
          ]],
        },
      },
      ["/schemas/:name"] = {
        GET = {
          title = [[Retrieve Entity Schema]],
          endpoint = [[<div class="endpoint get">/schemas/{entity name}</div>]],
          description = [[
            Retrieve the schema of an entity. This is useful to
            understand what fields an entity accepts, and can be used for building
            third-party integrations to the Kong.
          ]],
          response = [[
            ```
            HTTP 200 OK
            ```

            ```json
            {
                "fields": [
                    {
                        "id": {
                            "auto": true,
                            "type": "string",
                            "uuid": true
                        }
                    },
                    {
                        "created_at": {
                            "auto": true,
                            "timestamp": true,
                            "type": "integer"
                        }
                    },
                    ...
                ]
            }
            ```
          ]],
        },
      },
      ["/schemas/plugins/:name"] = {
        GET = {
          title = [[Retrieve Plugin Schema]],
          endpoint = [[<div class="endpoint get">/schemas/plugins/{plugin name}</div>]],
          description = [[
            Retrieve the schema of a plugin's configuration. This is useful to
            understand what fields a plugin accepts, and can be used for building
            third-party integrations to the Kong's plugin system.
          ]],
          response = [[
            ```
            HTTP 200 OK
            ```

            ```json
            {
                "fields": {
                    "hide_credentials": {
                        "default": false,
                        "type": "boolean"
                    },
                    "key_names": {
                        "default": "function",
                        "required": true,
                        "type": "array"
                    }
                }
            }
            ```
          ]],
        },
      },
    },
    health = {
      title = [[Health routes]],
      description = "",
      ["/status"] = {
        GET = {
          title = [[Retrieve node status]],
          endpoint = [[<div class="endpoint get">/status</div>]],
          description = [[
            Retrieve usage information about a node, with some basic information
            about the connections being processed by the underlying nginx process,
            the status of the database connection, and node's memory usage.

            If you want to monitor the Kong process, since Kong is built on top
            of nginx, every existing nginx monitoring tool or agent can be used.
          ]],
          response = [[
            ```
            HTTP 200 OK
            ```

            ```json
            {
                "database": {
                  "reachable": true
                },
                "memory": {
                    "workers_lua_vms": [{
                        "http_allocated_gc": "0.02 MiB",
                        "pid": 18477
                      }, {
                        "http_allocated_gc": "0.02 MiB",
                        "pid": 18478
                    }],
                    "lua_shared_dicts": {
                        "kong": {
                            "allocated_slabs": "0.04 MiB",
                            "capacity": "5.00 MiB"
                        },
                        "kong_db_cache": {
                            "allocated_slabs": "0.80 MiB",
                            "capacity": "128.00 MiB"
                        },
                    }
                },
                "server": {
                    "total_requests": 3,
                    "connections_active": 1,
                    "connections_accepted": 1,
                    "connections_handled": 1,
                    "connections_reading": 0,
                    "connections_writing": 1,
                    "connections_waiting": 0
                }
            }
            ```

            * `memory`: Metrics about the memory usage.
                * `workers_lua_vms`: An array with all workers of the Kong node, where each
                  entry contains:
                * `http_allocated_gc`: HTTP submodule's Lua virtual machine's memory
                  usage information, as reported by `collectgarbage("count")`, for every
                  active worker, i.e. a worker that received a proxy call in the last 10
                  seconds.
                * `pid`: worker's process identification number.
                * `lua_shared_dicts`: An array of information about dictionaries that are
                  shared with all workers in a Kong node, where each array node contains how
                  much memory is dedicated for the specific shared dictionary (`capacity`)
                  and how much of said memory is in use (`allocated_slabs`).
                  These shared dictionaries have least recent used (LRU) eviction
                  capabilities, so a full dictionary, where `allocated_slabs == capacity`,
                  will work properly. However for some dictionaries, e.g. cache HIT/MISS
                  shared dictionaries, increasing their size can be beneficial for the
                  overall performance of a Kong node.
              * The memory usage unit and precision can be changed using the querystring
                arguments `unit` and `scale`:
                  * `unit`: one of `b/B`, `k/K`, `m/M`, `g/G`, which will return results
                    in bytes, kibibytes, mebibytes, or gibibytes, respectively. When
                    "bytes" are requested, the memory values in the response will have a
                    number type instead of string. Defaults to `m`.
                  * `scale`: the number of digits to the right of the decimal points when
                    values are given in human-readable memory strings (unit other than
                    "bytes"). Defaults to `2`.
                  You can get the shared dictionaries memory usage in kibibytes with 4
                  digits of precision by doing: `GET /status?unit=k&scale=4`
            * `server`: Metrics about the nginx HTTP/S server.
                * `total_requests`: The total number of client requests.
                * `connections_active`: The current number of active client
                  connections including Waiting connections.
                * `connections_accepted`: The total number of accepted client
                  connections.
                * `connections_handled`: The total number of handled connections.
                  Generally, the parameter value is the same as accepts unless
                  some resource limits have been reached.
                * `connections_reading`: The current number of connections
                  where Kong is reading the request header.
                * `connections_writing`: The current number of connections
                  where nginx is writing the response back to the client.
                * `connections_waiting`: The current number of idle client
                  connections waiting for a request.
            * `database`: Metrics about the database.
                * `reachable`: A boolean value reflecting the state of the
                  database connection. Please note that this flag **does not**
                  reflect the health of the database itself.
          ]],
        },
      }
    },
    config = {
      skip = true,
    },
    clustering = {
      skip = true,
    },
    tags = {
      title = [[ Tags ]],
      description = [[
        Tags are strings associated to entities in Kong. Each tag must be composed of one or more
        alphanumeric characters, `_`, `-`, `.` or `~`.

        Most core entities can be *tagged* via their `tags` attribute, upon creation or edition.

        Tags can be used to filter core entities as well, via the `?tags` querystring parameter.

        For example: if you normally get a list of all the Services by doing:

        ```
        GET /services
        ```

        You can get the list of all the Services tagged `example` by doing:

        ```
        GET /services?tags=example
        ```

        Similarly, if you want to filter Services so that you only get the ones tagged `example` *and*
        `admin`, you can do that like so:

        ```
        GET /services?tags=example,admin
        ```

        Finally, if you wanted to filter the Services tagged `example` *or* `admin`, you could use:

        ```
        GET /services?tags=example/admin
        ```

        Some notes:

        * A maximum of 5 tags can be queried simultaneously in a single request with `,` or `/`
        * Mixing operators is not supported: if you try to mix `,` with `/` in the same querystring,
          you will receive an error.
        * You may need to quote and/or escape some characters when using them from the
          command line.
        * Filtering by `tags` is not supported in foreign key relationship endpoints. For example,
          the `tags` parameter will be ignored in a request such as `GET /services/foo/routes?tags=a,b`
        * `offset` parameters are not guaranteed to work if the `tags` parameter is altered or removed
      ]],
      ["/tags"] = {
        GET = {
          title = [[ List all tags ]],
          endpoint = [[<div class="endpoint get">/tags</div>]],
          description = [[
            Returns a paginated list of all the tags in the system.

            The list of entities will not be restricted to a single entity type: all the
            entities tagged with tags will be present on this list.

            If an entity is tagged with more than one tag, the `entity_id` for that entity
            will appear more than once in the resulting list. Similarly, if several entities
            have been tagged with the same tag, the tag will appear in several items of this list.
          ]],
          response = [[
            ```
            HTTP 200 OK
            ```

            ``` json
            {
                {
                  "data": [
                    { "entity_name": "services",
                      "entity_id": "acf60b10-125c-4c1a-bffe-6ed55daefba4",
                      "tag": "s1",
                    },
                    { "entity_name": "services",
                      "entity_id": "acf60b10-125c-4c1a-bffe-6ed55daefba4",
                      "tag": "s2",
                    },
                    { "entity_name": "routes",
                      "entity_id": "60631e85-ba6d-4c59-bd28-e36dd90f6000",
                      "tag": "s1",
                    },
                    ...
                  ],
                  "offset" = "c47139f3-d780-483d-8a97-17e9adc5a7ab",
                  "next" = "/tags?offset=c47139f3-d780-483d-8a97-17e9adc5a7ab",
                }
            }
            ```
          ]]
        },
      },

      ["/tags/:tags"] = {
        GET = {
          title = [[ List entity IDs by tag ]],
          endpoint = [[<div class="endpoint get">/tags/{tags}</div>]],
          description = [[
            Returns the entities that have been tagged with the specified tag.

            The list of entities will not be restricted to a single entity type: all the
            entities tagged with tags will be present on this list.
          ]],
          response = [[
            ```
            HTTP 200 OK
            ```

            ``` json
            {
                {
                  "data": [
                    { "entity_name": "services",
                      "entity_id": "c87440e1-0496-420b-b06f-dac59544bb6c",
                      "tag": "example",
                    },
                    { "entity_name": "routes",
                      "entity_id": "8a99e4b1-d268-446b-ab8b-cd25cff129b1",
                      "tag": "example",
                    },
                    ...
                  ],
                  "offset" = "1fb491c4-f4a7-4bca-aeba-7f3bcee4d2f9",
                  "next" = "/tags/example?offset=1fb491c4-f4a7-4bca-aeba-7f3bcee4d2f9",
                }
            }
            ```
          ]]
        },
      },
    },
  },

--------------------------------------------------------------------------------
-- Entities
--------------------------------------------------------------------------------

  entities = {
    services = {
      description = [[
        Service entities, as the name implies, are abstractions of each of your own
        upstream services. Examples of Services would be a data transformation
        microservice, a billing API, etc.

        The main attribute of a Service is its URL (where Kong should proxy traffic
        to), which can be set as a single string or by specifying its `protocol`,
        `host`, `port` and `path` individually.

        Services are associated to Routes (a Service can have many Routes associated
        with it). Routes are entry-points in Kong and define rules to match client
        requests. Once a Route is matched, Kong proxies the request to its associated
        Service. See the [Proxy Reference][proxy-reference] for a detailed explanation
        of how Kong proxies traffic.
      ]],

      ["/services/:services/client_certificate"] = {
        endpoint = false,
      },

      fields = {
        id = { skip = true },
        created_at = { skip = true },
        updated_at = { skip = true },
        name = {
          description = [[The Service name.]]
        },
        protocol = {
          description = [[
            The protocol used to communicate with the upstream.
          ]]
        },
        host = {
          description = [[The host of the upstream server.]],
          example = "example.com",
        },
        port = {
          description = [[The upstream server port.]]
        },
        path = {
          description = [[The path to be used in requests to the upstream server.]],
          examples = {
            "/some_api",
            "/another_api",
          }
        },
        retries = {
          description = [[The number of retries to execute upon failure to proxy.]]
        },
        connect_timeout = {
          description = [[
            The timeout in milliseconds for establishing a connection to the
            upstream server.
          ]]
        },
        write_timeout = {
          description = [[
            The timeout in milliseconds between two successive write operations
            for transmitting a request to the upstream server.
          ]]
        },
        read_timeout = {
          description = [[
            The timeout in milliseconds between two successive read operations
            for transmitting a request to the upstream server.
          ]]
        },
        client_certificate = {
          description = [[
            Certificate to be used as client certificate while TLS handshaking
            to the upstream server.
          ]],
        },
        tags = {
          description = [[
            An optional set of strings associated with the Service, for grouping and filtering.
          ]],
          examples = {
            { "user-level", "low-priority" },
            { "admin", "high-priority", "critical" }
          },
        },
      },
      extra_fields = {
        { url = {
          kind = "shorthand-attribute",
          description = [[
            Shorthand attribute to set `protocol`, `host`, `port` and `path`
            at once. This attribute is write-only (the Admin API never
            "returns" the url).
          ]]
        } },
      }
    },

    routes = {
      description = [[
        Route entities define rules to match client requests. Each Route is
        associated with a Service, and a Service may have multiple Routes associated to
        it. Every request matching a given Route will be proxied to its associated
        Service.

        The combination of Routes and Services (and the separation of concerns between
        them) offers a powerful routing mechanism with which it is possible to define
        fine-grained entry-points in Kong leading to different upstream services of
        your infrastructure.

        You need at least one matching rule that applies to the protocol being matched
        by the Route. Depending on the protocols configured to be matched by the Route
        (as defined with the `protocols` field), this means that at least one of the
        following attributes must be set:

        * For `http`, at least one of `methods`, `hosts`, `headers` or `paths`;
        * For `https`, at least one of `methods`, `hosts`, `headers`, `paths` or `snis`;
        * For `tcp`, at least one of `sources` or `destinations`;
        * For `tls`, at least one of `sources`, `destinations` or `snis`;
        * For `grpc`, at least one of `hosts`, `headers` or `paths`;
        * For `grpcs`, at least one of `hosts`, `headers`, `paths` or `snis`.

        #### Path handling algorithms

        `"v0"` is the behavior used in Kong 0.x and 2.x. It treats `service.path`, `route.path` and request path as
        *segments* of a url. It will always join them via slashes. Given a service path `/s`, route path `/r`
        and request path `/re`, the concatenated path will be `/s/re`. If the resulting path is a single slash,
        no further transformation is done to it. If it's longer, then the trailing slash is removed.

        `"v1"` is the behavior used in Kong 1.x. It treats `service.path` as a *prefix*, and ignores the initial
        slashes of the request and route paths. Given service path `/s`, route path `/r` and request path `/re`,
        the concatenated path will be `/sre`.

        Both versions of the algorithm detect "double slashes" when combining paths, replacing them by single
        slashes.

        On the following table, `s` is the Service and `r` is the Route.

        | `s.path` | `r.path` | `r.strip_path` | `r.path_handling` | request path | proxied path  |
        |----------|----------|----------------|-------------------|--------------|---------------|
        | `/s`     | `/fv0`   | `false`        | `v0`              | `/fv0req`    | `/s/fv0req`   |
        | `/s`     | `/fv1`   | `false`        | `v1`              | `/fv1req`    | `/sfv1req`    |
        | `/s`     | `/tv0`   | `true`         | `v0`              | `/tv0req`    | `/s/req`      |
        | `/s`     | `/tv1`   | `true`         | `v1`              | `/tv1req`    | `/sreq`       |
        | `/s`     | `/fv0/`  | `false`        | `v0`              | `/fv0/req`   | `/s/fv0/req`  |
        | `/s`     | `/fv1/`  | `false`        | `v1`              | `/fv1/req`   | `/sfv1/req`   |
        | `/s`     | `/tv0/`  | `true`         | `v0`              | `/tv0/req`   | `/s/req`      |
        | `/s`     | `/tv1/`  | `true`         | `v1`              | `/tv1/req`   | `/sreq`       |

      ]],
      fields = {
        id = { skip = true },
        created_at = { skip = true },
        updated_at = { skip = true },
        name = {
          description = [[The name of the Route.]]
        },
        regex_priority = {
          description = [[
            A number used to choose which route resolves a given request when several
            routes match it using regexes simultaneously. When two routes match the path
            and have the same `regex_priority`, the older one (lowest `created_at`)
            is used. Note that the priority for non-regex routes is different (longer
            non-regex routes are matched before shorter ones).
          ]]
        },
        protocols = {
          description = [[
            A list of the protocols this Route should allow. When set to `["https"]`,
            HTTP requests are answered with a request to upgrade to HTTPS.
          ]],
          examples = {
            {"http", "https"},
            {"tcp", "tls"},
          }
        },
        methods = {
          kind = "semi-optional",
          description = [[
            A list of HTTP methods that match this Route.
          ]],
          examples = { {"GET", "POST"}, nil },
          skip_in_example = true, -- hack so we get HTTP fields in the first example and Stream fields in the second
        },
        hosts = {
          kind = "semi-optional",
          description = [[
            A list of domain names that match this Route.
          ]],
          examples = { {"example.com", "foo.test"}, nil },
          skip_in_example = true, -- hack so we get HTTP fields in the first example and Stream fields in the second
        },
        paths = {
          kind = "semi-optional",
          description = [[
            A list of paths that match this Route.
          ]],
          examples = { {"/foo", "/bar"}, nil },
          skip_in_example = true, -- hack so we get HTTP fields in the first example and Stream fields in the second
        },
        headers = {
          kind = "semi-optional",
          description = [[
            One or more lists of values indexed by header name that will cause this Route to
            match if present in the request.
            The `Host` header cannot be used with this attribute: hosts should be specified
            using the `hosts` attribute.
          ]],
          examples = { { ["x-my-header"] = {"foo", "bar"}, ["x-another-header"] = {"bla"} }, nil },
          skip_in_example = true, -- hack so we get HTTP fields in the first example and Stream fields in the second
        },
        snis = {
          kind = "semi-optional",
          description = [[
            A list of SNIs that match this Route when using stream routing.
          ]],
          examples = { nil, {"foo.test", "example.com"} },
          skip_in_example = true, -- hack so we get HTTP fields in the first example and Stream fields in the second
        },
        sources = {
          kind = "semi-optional",
          description = [[
            A list of IP sources of incoming connections that match this Route when using stream routing.
            Each entry is an object with fields "ip" (optionally in CIDR range notation) and/or "port".
          ]],
          examples = { nil, {{ip = "10.1.0.0/16", port = 1234}, {ip = "10.2.2.2"}, {port = 9123}} },
          skip_in_example = true, -- hack so we get HTTP fields in the first example and Stream fields in the second
        },
        destinations = {
          kind = "semi-optional",
          description = [[
            A list of IP destinations of incoming connections that match this Route when using stream routing.
            Each entry is an object with fields "ip" (optionally in CIDR range notation) and/or "port".
          ]],
          examples = { nil, {{ip = "10.1.0.0/16", port = 1234}, {ip = "10.2.2.2"}, {port = 9123}} },
          skip_in_example = true, -- hack so we get HTTP fields in the first example and Stream fields in the second
        },
        strip_path = {
          description = [[
            When matching a Route via one of the `paths`,
            strip the matching prefix from the upstream request URL.
          ]]
        },
        path_handling = {
          description = [[
            Controls how the Service path, Route path and requested path are combined when sending a request to the
            upstream. See above for a detailed description of each behavior.
          ]]
        },
        preserve_host = {
          description = [[
            When matching a Route via one of the `hosts` domain names,
            use the request `Host` header in the upstream request headers.
            If set to `false`, the upstream `Host` header will be that of
            the Service's `host`.
          ]]
        },
        service = {
          description = [[
            The Service this Route is associated to.
            This is where the Route proxies traffic to.
          ]]
        },
        https_redirect_status_code = {
          description = [[
            The status code Kong responds with when all properties of a Route
            match except the protocol i.e. if the protocol of the request
            is `HTTP` instead of `HTTPS`.
            `Location` header is injected by Kong if the field is set
            to 301, 302, 307 or 308.
          ]]
        },
        tags = {
          description = [[
            An optional set of strings associated with the Route, for grouping and filtering.
          ]],
          examples = {
            { "user-level", "low-priority" },
            { "admin", "high-priority", "critical" }
          },
        },
      }
    },

    consumers = {
      description = [[
        The Consumer object represents a consumer - or a user - of a Service. You can
        either rely on Kong as the primary datastore, or you can map the consumer list
        with your database to keep consistency between Kong and your existing primary
        datastore.
      ]],
      fields = {
        id = { skip = true },
        created_at = { skip = true },
        updated_at = { skip = true },
        username = {
          kind = "semi-optional",
          description = [[
            The unique username of the consumer. You must send either
            this field or `custom_id` with the request.
          ]],
          example = "my-username",
        },
        custom_id = {
          kind = "semi-optional",
          description = [[
            Field for storing an existing unique ID for the consumer -
            useful for mapping Kong with users in your existing database.
            You must send either this field or `username` with the request.
          ]],
          example = "my-custom-id",
        },
        tags = {
          description = [[
            An optional set of strings associated with the Consumer, for grouping and filtering.
          ]],
          examples = {
            { "user-level", "low-priority" },
            { "admin", "high-priority", "critical" }
          },
        },
      }
    },

    plugins = {
      description = [[
        A Plugin entity represents a plugin configuration that will be executed during
        the HTTP request/response lifecycle. It is how you can add functionalities
        to Services that run behind Kong, like Authentication or Rate Limiting for
        example. You can find more information about how to install and what values
        each plugin takes by visiting the [Kong Hub](https://docs.konghq.com/hub/).

        When adding a Plugin Configuration to a Service, every request made by a client to
        that Service will run said Plugin. If a Plugin needs to be tuned to different
        values for some specific Consumers, you can do so by creating a separate
        plugin instance that specifies both the Service and the Consumer, through the
        `service` and `consumer` fields.
      ]],
      details = [[
        See the [Precedence](#precedence) section below for more details.

        #### Precedence

        A plugin will always be run once and only once per request. But the
        configuration with which it will run depends on the entities it has been
        configured for.

        Plugins can be configured for various entities, combination of entities, or
        even globally. This is useful, for example, when you wish to configure a plugin
        a certain way for most requests, but make _authenticated requests_ behave
        slightly differently.

        Therefore, there exists an order of precedence for running a plugin when it has
        been applied to different entities with different configurations. The rule of
        thumb is: the more specific a plugin is with regards to how many entities it
        has been configured on, the higher its priority.

        The complete order of precedence when a plugin has been configured multiple
        times is:

        1. Plugins configured on a combination of: a Route, a Service, and a Consumer.
            (Consumer means the request must be authenticated).
        2. Plugins configured on a combination of a Route and a Consumer.
            (Consumer means the request must be authenticated).
        3. Plugins configured on a combination of a Service and a Consumer.
            (Consumer means the request must be authenticated).
        4. Plugins configured on a combination of a Route and a Service.
        5. Plugins configured on a Consumer.
            (Consumer means the request must be authenticated).
        6. Plugins configured on a Route.
        7. Plugins configured on a Service.
        8. Plugins configured to run globally.

        **Example**: if the `rate-limiting` plugin is applied twice (with different
        configurations): for a Service (Plugin config A), and for a Consumer (Plugin
        config B), then requests authenticating this Consumer will run Plugin config B
        and ignore A. However, requests that do not authenticate this Consumer will
        fallback to running Plugin config A. Note that if config B is disabled
        (its `enabled` flag is set to `false`), config A will apply to requests that
        would have otherwise matched config B.
      ]],

      -- deprecated
      ["/plugins/schema/:name"] = {
        skip = true,
      },

      ["/plugins/enabled"] = {
        GET = {
          title = [[Retrieve Enabled Plugins]],
          description = [[Retrieve a list of all installed plugins on the Kong node.]],
          endpoint = [[<div class="endpoint get">/plugins/enabled</div>]],
          response = [[
            ```
            HTTP 200 OK
            ```

            ```json
            {
                "enabled_plugins": [
                    "jwt",
                    "acl",
                    "cors",
                    "oauth2",
                    "tcp-log",
                    "udp-log",
                    "file-log",
                    "http-log",
                    "key-auth",
                    "hmac-auth",
                    "basic-auth",
                    "ip-restriction",
                    "request-transformer",
                    "response-transformer",
                    "request-size-limiting",
                    "rate-limiting",
                    "response-ratelimiting",
                    "aws-lambda",
                    "bot-detection",
                    "correlation-id",
                    "datadog",
                    "galileo",
                    "ldap-auth",
                    "loggly",
                    "statsd",
                    "syslog"
                ]
            }
            ```
          ]]
        }
      },

      -- While these endpoints actually support DELETE (deleting the entity and
      -- cascade-deleting the plugin), we do not document them, as this operation
      -- is somewhat odd.
      ["/plugins/:plugins/route"] = {
        DELETE = {
          endpoint = false,
        }
      },
      ["/plugins/:plugins/service"] = {
        DELETE = {
          endpoint = false,
        }
      },
      ["/plugins/:plugins/consumer"] = {
        DELETE = {
          endpoint = false,
        }
      },
      -- Skip deprecated endpoints
      ["/routes/:routes/plugins/:plugins"] = {
        skip = true,
      },
      ["/services/:services/plugins/:plugins"] = {
        skip = true,
      },
      ["/consumers/:consumers/plugins/:plugins"] = {
        skip = true,
      },

      fields = {
        id = { skip = true },
        created_at = { skip = true },
        updated_at = { skip = true },
        name = {
          description = [[
            The name of the Plugin that's going to be added. Currently the
            Plugin must be installed in every Kong instance separately.
          ]],
          example = "rate-limiting",
        },
        config = {
          description = [[
            The configuration properties for the Plugin which can be found on
            the plugins documentation page in the
            [Kong Hub](https://docs.konghq.com/hub/).
          ]],
          example = { minute = 20, hour = 500 },
        },
        enabled = { description = [[Whether the plugin is applied.]] },
        route = { description = [[
          If set, the plugin will only activate when receiving requests via the specified route. Leave
          unset for the plugin to activate regardless of the Route being used.
        ]] },
        service = { description = [[
          If set, the plugin will only activate when receiving requests via one of the routes belonging to the
          specified Service. Leave unset for the plugin to activate regardless of the Service being
          matched.
        ]] },
        consumer = { description = [[
          If set, the plugin will activate only for requests where the specified has been authenticated.
          (Note that some plugins can not be restricted to consumers this way.). Leave unset for the plugin
          to activate regardless of the authenticated consumer.
        ]] },
        protocols = {
          description = [[
            A list of the request protocols that will trigger this plugin.

            The default value, as well as the possible values allowed on this field, may change
            depending on the plugin type. For example, plugins that only work in stream mode will
            only support `"tcp"` and `"tls"`.
          ]],
          examples = {
            { "http", "https" },
            { "tcp", "tls" },
          },
        },
        tags = {
          description = [[
            An optional set of strings associated with the Plugin, for grouping and filtering.
          ]],
          examples = {
            { "user-level", "low-priority" },
            { "admin", "high-priority", "critical" }
          },
        },
      }
    },

    certificates = {
      description = [[
        A certificate object represents a public certificate, and can be optionally paired with the
        corresponding private key. These objects are used by Kong to handle SSL/TLS termination for
        encrypted requests, or for use as a trusted CA store when validating peer certificate of
        client/service. Certificates are optionally associated with SNI objects to
        tie a cert/key pair to one or more hostnames.

        If intermediate certificates are required in addition to the main
        certificate, they should be concatenated together into one string according to
        the following order: main certificate on the top, followed by any intermediates.
      ]],
      fields = {
        id = { skip = true },
        created_at = { skip = true },
        cert = {
          description = [[PEM-encoded public certificate chain of the SSL key pair.]],
          example = "-----BEGIN CERTIFICATE-----...",
        },
        key = {
          description = [[PEM-encoded private key of the SSL key pair.]],
          example = "-----BEGIN RSA PRIVATE KEY-----..."
        },
        tags = {
          description = [[
            An optional set of strings associated with the Certificate, for grouping and filtering.
          ]],
          examples = {
            { "user-level", "low-priority" },
            { "admin", "high-priority", "critical" }
          },
        },
      },
      extra_fields = {
        { snis = {
          kind = "shorthand-attribute",
          description = [[
            An array of zero or more hostnames to associate with this
            certificate as SNIs. This is a sugar parameter that will, under the
            hood, create an SNI object and associate it with this certificate
            for your convenience. To set this attribute this certificate must
            have a valid private key associated with it.
          ]]
        } },
      },

    },

    ca_certificates = {
      entity_title = "CA Certificate",
      entity_title_plural = "CA Certificates",
      description = [[
        A CA certificate object represents a trusted CA. These objects are used by Kong to
        verify the validity of a client or server certificate.
      ]],
      fields = {
        id = { skip = true },
        created_at = { skip = true },
        cert = {
          description = [[PEM-encoded public certificate of the CA.]],
          example = "-----BEGIN CERTIFICATE-----...",
        },
        tags = {
          description = [[
            An optional set of strings associated with the Certificate, for grouping and filtering.
          ]],
          examples = {
            { "user-level", "low-priority" },
            { "admin", "high-priority", "critical" }
          },
        },
      },
    },

    snis = {
      entity_title = "SNI",
      entity_title_plural = "SNIs",
      description = [[
        An SNI object represents a many-to-one mapping of hostnames to a certificate.
        That is, a certificate object can have many hostnames associated with it; when
        Kong receives an SSL request, it uses the SNI field in the Client Hello to
        lookup the certificate object based on the SNI associated with the certificate.
      ]],
      ["/snis/:snis/certificate"] = {
        endpoint = false,
      },
      fields = {
        id = { skip = true },
        created_at = { skip = true },
        name = { description = [[The SNI name to associate with the given certificate.]] },
        certificate = {
          description = [[
            The id (a UUID) of the certificate with which to associate the SNI hostname.
            The Certificate must have a valid private key associated with it to be used
            by the SNI object.
          ]]
        },
        tags = {
          description = [[
            An optional set of strings associated with the SNIs, for grouping and filtering.
          ]],
          examples = {
            { "user-level", "low-priority" },
            { "admin", "high-priority", "critical" }
          },
        },
      },
    },

    upstreams = {
      description = [[
        The upstream object represents a virtual hostname and can be used to loadbalance
        incoming requests over multiple services (targets). So for example an upstream
        named `service.v1.xyz` for a Service object whose `host` is `service.v1.xyz`.
        Requests for this Service would be proxied to the targets defined within the upstream.

        An upstream also includes a [health checker][healthchecks], which is able to
        enable and disable targets based on their ability or inability to serve
        requests. The configuration for the health checker is stored in the upstream
        object, and applies to all of its targets.
      ]],
      ["/upstreams/:upstreams/health"] = {
        GET = {
          title = [[Show Upstream health for node]],
          description = [[
            Displays the health status for all Targets of a given Upstream, or for
            the whole Upstream, according to the perspective of a specific Kong node.
            Note that, being node-specific information, making this same request
            to different nodes of the Kong cluster may produce different results.
            For example, one specific node of the Kong cluster may be experiencing
            network issues, causing it to fail to connect to some Targets: these
            Targets will be marked as unhealthy by that node (directing traffic from
            this node to other Targets that it can successfully reach), but healthy
            to all others Kong nodes (which have no problems using that Target).

            The `data` field of the response contains an array of Target objects.
            The health for each Target is returned in its `health` field:

            * If a Target fails to be activated in the balancer due to DNS issues,
              its status displays as `DNS_ERROR`.
            * When [health checks][healthchecks] are not enabled in the Upstream
              configuration, the health status for active Targets is displayed as
              `HEALTHCHECKS_OFF`.
            * When health checks are enabled and the Target is determined to be healthy,
              either automatically or [manually](#set-target-as-healthy),
              its status is displayed as `HEALTHY`. This means that this Target is
              currently included in this Upstream's load balancer execution.
            * When a Target has been disabled by either active or passive health checks
              (circuit breakers) or [manually](#set-target-as-unhealthy),
              its status is displayed as `UNHEALTHY`. The load balancer is not directing
              any traffic to this Target via this Upstream.

            When the request query parameter `balancer_health` is set to `1`, the
            `data` field of the response refers to the whole Upstream, and its `health`
            attribute is defined by the state of all of Upstream's Targets, according
            to the field [health checker's threshold][healthchecks.threshold].
          ]],
          endpoint = [[
            <div class="endpoint get indent">/upstreams/{name or id}/health/</div>

            {:.indent}
            Attributes | Description
            ---:| ---
            `name or id`<br>**required** | The unique identifier **or** the name of the Upstream for which to display Target health.
          ]],
          request_query = [[
            Attributes | Description
            ---:| ---
            `balancer_health`<br>*optional* | If set to 1, Kong will return the health status of the whole Upstream.
          ]],
          response = [[
            ```
            HTTP 200 OK
            ```

            ```json
            {
                "total": 2,
                "node_id": "cbb297c0-14a9-46bc-ad91-1d0ef9b42df9",
                "data": [
                    {
                        "created_at": 1485524883980,
                        "id": "18c0ad90-f942-4098-88db-bbee3e43b27f",
                        "health": "HEALTHY",
                        "target": "127.0.0.1:20000",
                        "upstream_id": "07131005-ba30-4204-a29f-0927d53257b4",
                        "weight": 100
                    },
                    {
                        "created_at": 1485524914883,
                        "id": "6c6f34eb-e6c3-4c1f-ac58-4060e5bca890",
                        "health": "UNHEALTHY",
                        "target": "127.0.0.1:20002",
                        "upstream_id": "07131005-ba30-4204-a29f-0927d53257b4",
                        "weight": 200
                    }
                ]
            }
            ```

            If `balancer_health=1`:
            ```
            HTTP 200 OK
            ```

            ```json
            {
                "data": {
                    "health": "HEALTHY",
                    "id": "07131005-ba30-4204-a29f-0927d53257b4"
                },
                "next": null,
                "node_id": "cbb297c0-14a9-46bc-ad91-1d0ef9b42df9"
            }
            ```
          ]],
        },

      },
      fields = {
        id = { skip = true },
        created_at = { skip = true },
        ["name"] = { description = [[This is a hostname, which must be equal to the `host` of a Service.]] },
        ["slots"] = { description = [[The number of slots in the loadbalancer algorithm (`10`-`65536`).]] },
        ["algorithm"] = { description = [[Which load balancing algorithm to use.]] },
        ["hash_on"] = { description = [[What to use as hashing input. Using `none` results in a weighted-round-robin scheme with no hashing.]] },
        ["hash_fallback"] = { description = [[What to use as hashing input if the primary `hash_on` does not return a hash (eg. header is missing, or no consumer identified). Not available if `hash_on` is set to `cookie`.]] },
        ["hash_on_header"] = { kind = "semi-optional", skip_in_example = true, description = [[The header name to take the value from as hash input. Only required when `hash_on` is set to `header`.]] },
        ["hash_fallback_header"] = { kind = "semi-optional", skip_in_example = true, description = [[The header name to take the value from as hash input. Only required when `hash_fallback` is set to `header`.]] },
        ["hash_on_cookie"] = { kind = "semi-optional", skip_in_example = true, description = [[The cookie name to take the value from as hash input. Only required when `hash_on` or `hash_fallback` is set to `cookie`. If the specified cookie is not in the request, Kong will generate a value and set the cookie in the response.]] },
        ["hash_on_cookie_path"] = { kind = "semi-optional", skip_in_example = true, description = [[The cookie path to set in the response headers. Only required when `hash_on` or `hash_fallback` is set to `cookie`.]] },
        ["host_header"] = { description = [[The hostname to be used as `Host` header when proxying requests through Kong.]], example = "example.com", },
        ["healthchecks.active.timeout"] = { description = [[Socket timeout for active health checks (in seconds).]] },
        ["healthchecks.active.concurrency"] = { description = [[Number of targets to check concurrently in active health checks.]] },
        ["healthchecks.active.type"] = { description = [[Whether to perform active health checks using HTTP or HTTPS, or just attempt a TCP connection.]] },
        ["healthchecks.active.http_path"] = { description = [[Path to use in GET HTTP request to run as a probe on active health checks.]] },
        ["healthchecks.active.https_verify_certificate"] = { description = [[Whether to check the validity of the SSL certificate of the remote host when performing active health checks using HTTPS.]] },
        ["healthchecks.active.https_sni"] = { description = [[The hostname to use as an SNI (Server Name Identification) when performing active health checks using HTTPS. This is particularly useful when Targets are configured using IPs, so that the target host's certificate can be verified with the proper SNI.]], example = "example.com", },
        ["healthchecks.active.healthy.interval"] = { description = [[Interval between active health checks for healthy targets (in seconds). A value of zero indicates that active probes for healthy targets should not be performed.]] },
        ["healthchecks.active.healthy.http_statuses"] = { description = [[An array of HTTP statuses to consider a success, indicating healthiness, when returned by a probe in active health checks.]] },
        ["healthchecks.active.healthy.successes"] = { description = [[Number of successes in active probes (as defined by `healthchecks.active.healthy.http_statuses`) to consider a target healthy.]] },
        ["healthchecks.active.unhealthy.interval"] = { description = [[Interval between active health checks for unhealthy targets (in seconds). A value of zero indicates that active probes for unhealthy targets should not be performed.]] },
        ["healthchecks.active.unhealthy.http_statuses"] = { description = [[An array of HTTP statuses to consider a failure, indicating unhealthiness, when returned by a probe in active health checks.]] },
        ["healthchecks.active.unhealthy.tcp_failures"] = { description = [[Number of TCP failures in active probes to consider a target unhealthy.]] },
        ["healthchecks.active.unhealthy.timeouts"] = { description = [[Number of timeouts in active probes to consider a target unhealthy.]] },
        ["healthchecks.active.unhealthy.http_failures"] = { description = [[Number of HTTP failures in active probes (as defined by `healthchecks.active.unhealthy.http_statuses`) to consider a target unhealthy.]] },
        ["healthchecks.passive.type"] = { description = [[Whether to perform passive health checks interpreting HTTP/HTTPS statuses, or just check for TCP connection success. In passive checks, `http` and `https` options are equivalent.]] },
        ["healthchecks.passive.healthy.http_statuses"] = { description = [[An array of HTTP statuses which represent healthiness when produced by proxied traffic, as observed by passive health checks.]] },
        ["healthchecks.passive.healthy.successes"] = { description = [[Number of successes in proxied traffic (as defined by `healthchecks.passive.healthy.http_statuses`) to consider a target healthy, as observed by passive health checks.]] },
        ["healthchecks.passive.unhealthy.http_statuses"] = { description = [[An array of HTTP statuses which represent unhealthiness when produced by proxied traffic, as observed by passive health checks.]] },
        ["healthchecks.passive.unhealthy.tcp_failures"] = { description = [[Number of TCP failures in proxied traffic to consider a target unhealthy, as observed by passive health checks.]] },
        ["healthchecks.passive.unhealthy.timeouts"] = { description = [[Number of timeouts in proxied traffic to consider a target unhealthy, as observed by passive health checks.]] },
        ["healthchecks.passive.unhealthy.http_failures"] = { description = [[Number of HTTP failures in proxied traffic (as defined by `healthchecks.passive.unhealthy.http_statuses`) to consider a target unhealthy, as observed by passive health checks.]] },
        ["healthchecks.threshold"] = { description = [[The minimum percentage of the upstream's targets' weight that must be available for the whole upstream to be considered healthy.]] },
        tags = {
          description = [[
            An optional set of strings associated with the Upstream, for grouping and filtering.
          ]],
          examples = {
            { "user-level", "low-priority" },
            { "admin", "high-priority", "critical" }
          },
        },
      }
    },

    targets = {
      entity_endpoint_key = "host:port",
      description = [[
        A target is an ip address/hostname with a port that identifies an instance of a backend
        service. Every upstream can have many targets, and the targets can be
        dynamically added. Changes are effectuated on the fly.

        Because the upstream maintains a history of target changes, the targets cannot
        be deleted or modified. To disable a target, post a new one with `weight=0`;
        alternatively, use the `DELETE` convenience method to accomplish the same.

        The current target object definition is the one with the latest `created_at`.
      ]],
      ["/targets"] = {
        -- This is not using `skip = true` because
        -- we want the sections for GETting targets and POSTing targets to appear,
        -- but we don't want them to appear using `GET /targets` and `POST /targets`.
        -- Instead, we want the section itself to appear, but only the endpoints
        -- generated via foreign keys (`GET /upstreams/:upstreams/targets` and
        -- `POST /upstreams/:upstream/targets`)
        endpoint = false,
      },
      ["/targets/:targets"] = {
        skip = true,
      },
      ["/targets/:targets/upstreams"] = {
        skip = true,
      },
      ["/upstreams/:upstreams/targets/:targets"] = {
        DELETE = {
          title = [[Delete Target]],
          description = [[
            Disable a target in the load balancer. Under the hood, this method creates
            a new entry for the given target definition with a `weight` of 0.
          ]],
          endpoint = [[
            <div class="endpoint delete indent">/upstreams/{upstream name or id}/targets/{host:port or id}</div>

            {:.indent}
            Attributes | Description
            ---:| ---
            `upstream name or id`<br>**required** | The unique identifier **or** the name of the upstream for which to delete the target.
            `host:port or id`<br>**required** | The host:port combination element of the target to remove, or the `id` of an existing target entry.
          ]],
          response = [[
            ```
            HTTP 204 No Content
            ```
          ]]
        }
      },

      ["/upstreams/:upstreams/targets/all"] = {
        GET = {
          title = [[List all Targets]],
          description = [[
            Lists all targets of the upstream. Multiple target objects for the same
            target may be returned, showing the history of changes for a specific target.
            The target object with the latest `created_at` is the current definition.
          ]],
          endpoint = [[
            <div class="endpoint get indent">/upstreams/{name or id}/targets/all/</div>

            {:.indent}
            Attributes | Description
            ---:| ---
            `name or id`<br>**required** | The unique identifier **or** the name of the upstream for which to list the targets.
          ]],
          response = [[
            ```
            HTTP 200 OK
            ```

            ```json
            {
                "total": 2,
                "data": [
                    {
                        "created_at": 1485524883980,
                        "id": "18c0ad90-f942-4098-88db-bbee3e43b27f",
                        "target": "127.0.0.1:20000",
                        "upstream_id": "07131005-ba30-4204-a29f-0927d53257b4",
                        "weight": 100
                    },
                    {
                        "created_at": 1485524914883,
                        "id": "6c6f34eb-e6c3-4c1f-ac58-4060e5bca890",
                        "target": "127.0.0.1:20002",
                        "upstream_id": "07131005-ba30-4204-a29f-0927d53257b4",
                        "weight": 200
                    }
                ]
            }
            ```
          ]],
        }
      },
      ["/upstreams/:upstreams/targets/:targets/healthy"] = {
        POST = {
          title = [[Set target as healthy]],
          description = [[
            Set the current health status of a target in the load balancer to "healthy"
            in the entire Kong cluster. This sets the "healthy" status to all addresses
            resolved by this target.

            This endpoint can be used to manually re-enable a target that was previously
            disabled by the upstream's [health checker][healthchecks]. Upstreams only
            forward requests to healthy nodes, so this call tells Kong to start using this
            target again.

            This resets the health counters of the health checkers running in all workers
            of the Kong node, and broadcasts a cluster-wide message so that the "healthy"
            status is propagated to the whole Kong cluster.
          ]],
          endpoint = [[
            <div class="endpoint post indent">/upstreams/{upstream name or id}/targets/{target or id}/healthy</div>

            {:.indent}
            Attributes | Description
            ---:| ---
            `upstream name or id`<br>**required** | The unique identifier **or** the name of the upstream.
            `target or id`<br>**required** | The host/port combination element of the target to set as healthy, or the `id` of an existing target entry.
          ]],
          response = [[
            ```
            HTTP 204 No Content
            ```
          ]],
        }
      },
      ["/upstreams/:upstreams/targets/:targets/unhealthy"] = {
        POST = {
          title = [[Set target as unhealthy]],
          description = [[
            Set the current health status of a target in the load balancer to "unhealthy"
            in the entire Kong cluster. This sets the "unhealthy" status to all addresses
            resolved by this target.

            This endpoint can be used to manually disable a target and have it stop
            responding to requests. Upstreams only forward requests to healthy nodes, so
            this call tells Kong to start skipping this target.

            This call resets the health counters of the health checkers running in all
            workers of the Kong node, and broadcasts a cluster-wide message so that the
            "unhealthy" status is propagated to the whole Kong cluster.

            [Active health checks][active] continue to execute for unhealthy
            targets. Note that if active health checks are enabled and the probe detects
            that the target is actually healthy, it will automatically re-enable it again.
            To permanently remove a target from the balancer, you should [delete a
            target](#delete-target) instead.
          ]],
          endpoint = [[
            <div class="endpoint post indent">/upstreams/{upstream name or id}/targets/{target or id}/unhealthy</div>

            {:.indent}
            Attributes | Description
            ---:| ---
            `upstream name or id`<br>**required** | The unique identifier **or** the name of the upstream.
            `target or id`<br>**required** | The host/port combination element of the target to set as unhealthy, or the `id` of an existing target entry.
          ]],
          response = [[
            ```
            HTTP 204 No Content
            ```
          ]],
        }
      },
      ["/upstreams/:upstreams/targets/:targets/:address/healthy"] = {
        POST = {
          title = [[Set target address as healthy]],
          description = [[
            Set the current health status of an individual address resolved by a target
            in the load balancer to "healthy" in the entire Kong cluster.

            This endpoint can be used to manually re-enable an address resolved by a
            target that was previously disabled by the upstream's [health checker][healthchecks].
            Upstreams only forward requests to healthy nodes, so this call tells Kong
            to start using this address again.

            This resets the health counters of the health checkers running in all workers
            of the Kong node, and broadcasts a cluster-wide message so that the "healthy"
            status is propagated to the whole Kong cluster.
          ]],
          endpoint = [[
            <div class="endpoint post indent">/upstreams/{upstream name or id}/targets/{target or id}/{address}/healthy</div>

            {:.indent}
            Attributes | Description
            ---:| ---
            `upstream name or id`<br>**required** | The unique identifier **or** the name of the upstream.
            `target or id`<br>**required** | The host/port combination element of the target to set as healthy, or the `id` of an existing target entry.
            `address`<br>**required** | The host/port combination element of the address to set as healthy.
          ]],
          response = [[
            ```
            HTTP 204 No Content
            ```
          ]],
        }
      },
      ["/upstreams/:upstreams/targets/:targets/:address/unhealthy"] = {
        POST = {
          title = [[Set target address as unhealthy]],
          description = [[
            Set the current health status of an individual address resolved by a target
            in the load balancer to "unhealthy" in the entire Kong cluster.

            This endpoint can be used to manually disable an address and have it stop
            responding to requests. Upstreams only forward requests to healthy nodes, so
            this call tells Kong to start skipping this address.

            This call resets the health counters of the health checkers running in all
            workers of the Kong node, and broadcasts a cluster-wide message so that the
            "unhealthy" status is propagated to the whole Kong cluster.

            [Active health checks][active] continue to execute for unhealthy
            addresses. Note that if active health checks are enabled and the probe detects
            that the address is actually healthy, it will automatically re-enable it again.
            To permanently remove a target from the balancer, you should [delete a
            target](#delete-target) instead.
          ]],
          endpoint = [[
            <div class="endpoint post indent">/upstreams/{upstream name or id}/targets/{target or id}/unhealthy</div>

            {:.indent}
            Attributes | Description
            ---:| ---
            `upstream name or id`<br>**required** | The unique identifier **or** the name of the upstream.
            `target or id`<br>**required** | The host/port combination element of the target to set as unhealthy, or the `id` of an existing target entry.
          ]],
          response = [[
            ```
            HTTP 204 No Content
            ```
          ]],
        }
      },
      fields = {
        id = { skip = true },
        created_at = { skip = true },
        upstream = { skip = true },
        target = {
          description = [[
            The target address (ip or hostname) and port.
            If the hostname resolves to an SRV record, the `port` value will
            be overridden by the value from the DNS record.
          ]],
          example = "example.com:8000",
        },
        weight = {
          description = [[
            The weight this target gets within the upstream loadbalancer (`0`-`1000`).
            If the hostname resolves to an SRV record, the `weight` value will be
            overridden by the value from the DNS record.
          ]]
        },
        tags = {
          description = [[
            An optional set of strings associated with the Target, for grouping and filtering.
          ]],
          examples = {
            { "user-level", "low-priority" },
            { "admin", "high-priority", "critical" }
          },
        },
      },
    }
  },

--------------------------------------------------------------------------------
-- Templates for auto-generated endpoints
--------------------------------------------------------------------------------

  collection_templates = {
    GET = {
      title = [[List ${Entities}]],
      endpoint_w_ek = [[
        ##### List All ${Entities}

        <div class="endpoint ${method} indent">/${entities_url}</div>
      ]],
      endpoint = [[
        ##### List All ${Entities}

        <div class="endpoint ${method} indent">/${entities_url}</div>
      ]],
      fk_endpoint = [[
        ##### List ${Entities} Associated to a Specific ${ForeignEntity}

        <div class="endpoint ${method} indent">/${foreign_entities_url}/{${foreign_entity} id}/${entities_url}</div>

        {:.indent}
        Attributes | Description
        ---:| ---
        `${foreign_entity} id`<br>**required** | The unique identifier of the ${ForeignEntity} whose ${Entities} are to be retrieved. When using this endpoint, only ${Entities} associated to the specified ${ForeignEntity} will be listed.
      ]],
      fk_endpoint_w_ek = [[
        ##### List ${Entities} Associated to a Specific ${ForeignEntity}

        <div class="endpoint ${method} indent">/${foreign_entities_url}/{${foreign_entity} ${endpoint_key} or id}/${entities_url}</div>

        {:.indent}
        Attributes | Description
        ---:| ---
        `${foreign_entity} ${endpoint_key} or id`<br>**required** | The unique identifier or the `${endpoint_key}` attribute of the ${ForeignEntity} whose ${Entities} are to be retrieved. When using this endpoint, only ${Entities} associated to the specified ${ForeignEntity} will be listed.
      ]],
      request_query = [[
        Attributes | Description
        ---:| ---
        `offset`<br>*optional* | A cursor used for pagination. `offset` is an object identifier that defines a place in the list.
        `size`<br>*optional, default is __100__ max is __1000__* | A limit on the number of objects to be returned per page.
      ]],
      response = [[
        ```
        HTTP 200 OK
        ```

        ```json
        {
        {{ page.${entity}_data }}
            "next": "http://localhost:8001/${entities_url}?offset=6378122c-a0a1-438d-a5c6-efabae9fb969"
        }
        ```
      ]],
    },
    POST = {
      title = [[Add ${Entity}]],
      endpoint_w_ek = [[
        ##### Create ${Entity}

        <div class="endpoint ${method} indent">/${entities_url}</div>
      ]],
      endpoint = [[
        ##### Create ${Entity}

        <div class="endpoint ${method} indent">/${entities_url}</div>
      ]],
      fk_endpoint = [[
        ##### Create ${Entity} Associated to a Specific ${ForeignEntity}

        <div class="endpoint ${method} indent">/${foreign_entities_url}/{${foreign_entity} id}/${entities_url}</div>

        {:.indent}
        Attributes | Description
        ---:| ---
        `${foreign_entity} id`<br>**required** | The unique identifier of the ${ForeignEntity} that should be associated to the newly-created ${Entity}.
      ]],
      fk_endpoint_w_ek = [[
        ##### Create ${Entity} Associated to a Specific ${ForeignEntity}

        <div class="endpoint ${method} indent">/${foreign_entities_url}/{${foreign_entity} ${endpoint_key} or id}/${entities_url}</div>

        {:.indent}
        Attributes | Description
        ---:| ---
        `${foreign_entity} ${endpoint_key} or id`<br>**required** | The unique identifier or the `${endpoint_key}` attribute of the ${ForeignEntity} that should be associated to the newly-created ${Entity}.
      ]],
      request_body = [[
        {{ page.${entity}_body }}
      ]],
      response = [[
        ```
        HTTP 201 Created
        ```

        ```json
        {{ page.${entity}_json }}
        ```
      ]],
    },
  },
  entity_templates = {
    tags = [[
      ${Entities} can be both [tagged and filtered by tags](#tags).
    ]],
    endpoint_w_ek = [[
      ##### ${Active_verb} ${Entity}

      <div class="endpoint ${method} indent">/${entities_url}/{${entity} ${endpoint_key} or id}</div>

      {:.indent}
      Attributes | Description
      ---:| ---
      `${entity} ${endpoint_key} or id`<br>**required** | The unique identifier **or** the ${endpoint_key} of the ${Entity} to ${active_verb}.
    ]],
    fk_endpoint_w_ek = [[
      ##### ${Active_verb} ${ForeignEntity} Associated to a Specific ${Entity}

      <div class="endpoint ${method} indent">/${entities_url}/{${entity} ${endpoint_key} or id}/${foreign_entity_url}</div>

      {:.indent}
      Attributes | Description
      ---:| ---
      `${entity} ${endpoint_key} or id`<br>**required** | The unique identifier **or** the ${endpoint_key} of the ${Entity} associated to the ${ForeignEntity} to be ${passive_verb}.
    ]],
    endpoint = [[
      ##### ${Active_verb} ${Entity}

      <div class="endpoint ${method} indent">/${entities_url}/{${entity} id}</div>

      {:.indent}
      Attributes | Description
      ---:| ---
      `${entity} id`<br>**required** | The unique identifier of the ${Entity} to ${active_verb}.
    ]],
    fk_endpoint = [[
      ##### ${Active_verb} ${ForeignEntity} Associated to a Specific ${Entity}

      <div class="endpoint ${method} indent">/${entities_url}/{${entity} id}/${foreign_entity_url}</div>

      {:.indent}
      Attributes | Description
      ---:| ---
      `${entity} id`<br>**required** | The unique identifier of the ${Entity} associated to the ${ForeignEntity} to be ${passive_verb}.
    ]],
    nested_endpoint_w_eks = [[
      ##### ${Active_verb} ${Entity} Associated to a Specific ${ForeignEntity}

      <div class="endpoint ${method} indent">/${foreign_entities_url}/{${foreign_entity} ${foreign_endpoint_key} or id}/${entities_url}/{${entity} ${endpoint_key} or id}</div>

      {:.indent}
      Attributes | Description
      ---:| ---
      `${foreign_entity} ${foreign_endpoint_key} or id`<br>**required** | The unique identifier **or** the ${foreign_endpoint_key} of the ${ForeignEntity} to ${active_verb}.
      `${entity} ${endpoint_key} or id`<br>**required** | The unique identifier **or** the ${endpoint_key} of the ${Entity} to ${active_verb}.
    ]],
    nested_endpoint_w_ek = [[
      ##### ${Active_verb} ${Entity} Associated to a Specific ${ForeignEntity}

      <div class="endpoint ${method} indent">/${foreign_entities_url}/{${foreign_entity} id}/${entities_url}/{${entity} ${endpoint_key} or id}</div>

      {:.indent}
      Attributes | Description
      ---:| ---
      `${foreign_entity} id`<br>**required** | The unique identifier of the ${ForeignEntity} to ${active_verb}.
      `${entity} ${endpoint_key} or id`<br>**required** | The unique identifier **or** the ${endpoint_key} of the ${Entity} to ${active_verb}.
    ]],
    nested_endpoint_w_fek = [[
      ##### ${Active_verb} ${Entity} Associated to a Specific ${ForeignEntity}

      <div class="endpoint ${method} indent">/${foreign_entities_url}/{${foreign_entity} ${foreign_endpoint_key} or id}/${entities_url}/{${entity} id}</div>

      {:.indent}
      Attributes | Description
      ---:| ---
      `${foreign_entity} ${foreign_endpoint_key} or id`<br>**required** | The unique identifier **or** the ${foreign_endpoint_key} of the ${ForeignEntity} to ${active_verb}.
      `${entity} id`<br>**required** | The unique identifier of the ${Entity} to ${active_verb}.
    ]],
    nested_endpoint = [[
      ##### ${Active_verb} ${Entity} Associated to a Specific ${ForeignEntity}

      <div class="endpoint ${method} indent">/${foreign_entities_url}/{${foreign_entity} id}/${entities_url}/{${entity} id}</div>

      {:.indent}
      Attributes | Description
      ---:| ---
      `${foreign_entity} id`<br>**required** | The unique identifier of the ${ForeignEntity} to ${active_verb}.
      `${entity} id`<br>**required** | The unique identifier of the ${Entity} to ${active_verb}.
    ]],
    GET = {
      title = [[Retrieve ${Entity}]],
      response = [[
        ```
        HTTP 200 OK
        ```

        ```json
        {{ page.${entity}_json }}
        ```
      ]],
    },
    PATCH = {
      title = [[Update ${Entity}]],
      request_body = [[
        {{ page.${entity}_body }}
      ]],
      response = [[
        ```
        HTTP 200 OK
        ```

        ```json
        {{ page.${entity}_json }}
        ```
      ]],
    },
    PUT = {
      title = [[Update or create ${Entity}]],
      request_body = [[
        {{ page.${entity}_body }}
      ]],
      details = [[
        Inserts (or replaces) the ${Entity} under the requested resource with the
        definition specified in the body. The ${Entity} will be identified via the `${endpoint_key}
        or id` attribute.

        When the `${endpoint_key} or id` attribute has the structure of a UUID, the ${Entity} being
        inserted/replaced will be identified by its `id`. Otherwise it will be
        identified by its `${endpoint_key}`.

        When creating a new ${Entity} without specifying `id` (neither in the URL nor in
        the body), then it will be auto-generated.

        Notice that specifying a `${endpoint_key}` in the URL and a different one in the request
        body is not allowed.
      ]],
      response = [[
        ```
        HTTP 201 Created or HTTP 200 OK
        ```

        See POST and PATCH responses.
      ]],
    },
    DELETE = {
      title = [[Delete ${Entity}]],
      response = [[
        ```
        HTTP 204 No Content
        ```
      ]],
    }
  },

--------------------------------------------------------------------------------
-- Overrides for DB-less mode
--------------------------------------------------------------------------------

  dbless = {

    intro = {
      {
        text = [[
          <div class="alert alert-info.blue" role="alert">
            This page refers to the Admin API for running Kong configured without a
            database, managing in-memory entities via declarative config.
            For using the Admin API for Kong with a database, please refer to the
            <a href="/{{page.kong_version}}/admin-api">Admin API for Database Mode</a> page.
          </div>

          Kong comes with an **internal** RESTful Admin API for administration purposes.
          In [DB-less mode][db-less], this Admin API can be used to load a new declarative
          configuration, and for inspecting the current configuration. In DB-less mode,
          the Admin API for each Kong node functions independently, reflecting the memory state
          of that particular Kong node. This is the case because there is no database
          coordination between Kong nodes.

          - `8001` is the default port on which the Admin API listens.
          - `8444` is the default port for HTTPS traffic to the Admin API.

          This API provides full control over Kong, so care should be taken when setting
          up Kong environments to avoid undue public exposure of this API.
          See [this document][secure-admin-api] for a discussion
          of methods to secure the Admin API.
        ]],
      },
      {
        title = [[Supported Content Types]],
        text = [[
          The Admin API accepts 2 content types on every endpoint:

          - **application/x-www-form-urlencoded**
          - **application/json**
        ]],
      },
    },

    footer = [[
      [clustering]: /{{page.kong_version}}/clustering
      [cli]: /{{page.kong_version}}/cli
      [active]: /{{page.kong_version}}/health-checks-circuit-breakers/#active-health-checks
      [healthchecks]: /{{page.kong_version}}/health-checks-circuit-breakers
      [secure-admin-api]: /{{page.kong_version}}/secure-admin-api
      [proxy-reference]: /{{page.kong_version}}/proxy
      [db-less]: /{{page.kong_version}}/db-less-and-declarative-config
      [admin-api]: /{{page.kong_version}}/admin-api
    ]],

    general = {
      config = {
        skip = false,
        title = [[Declarative Configuration]],
        description = [[
          Loading the declarative configuration of entities into Kong
          can be done in two ways: at start-up, through the `declarative_config`
          property, or at run-time, through the Admin API using the `/config`
          endpoint.

          To get started using declarative configuration, you need a file
          (in YAML or JSON format) containing entity definitions. You can
          generate a sample declarative configuration with the command:

          ```
          kong config init
          ```

          It generates a file named `kong.yml` in the current directory,
          containing the appropriate structure and examples.
        ]],
        ["/config"] = {
          POST = {
            title = [[Reload declarative configuration]],
            endpoint = [[
              <div class="endpoint post indent">/config</div>

              {:.indent}
              Attributes | Description
              ---:| ---
              `config`<br>**required** | The config data (in YAML or JSON format) to be loaded.
            ]],

            request_query = [[
              Attributes | Description
              ---:| ---
              `check_hash`<br>*optional* | If set to 1, Kong will compare the hash of the input config data against that of the previous one. If the configuration is identical, it will not reload it and will return HTTP 304.
            ]],

            description = [[
              This endpoint allows resetting a DB-less Kong with a new
              declarative configuration data file. All previous contents
              are erased from memory, and the entities specified in the
              given file take their place.

              To learn more about the file format, please read the
              [declarative configuration][db-less] documentation.
            ]],
            response = [[
              ```
              HTTP 200 OK
              ```

              ``` json
              {
                  { "services": [],
                    "routes": []
                  }
              }
              ```

              The response contains a list of all the entities that were parsed from the
              input file.
            ]]
          }
        },
      },
    },

    entities = {
      methods = {
        -- in DB-less mode, only document GET endpoints for entities
        ["GET"] = true,
        ["POST"] = false,
        ["PATCH"] = false,
        ["PUT"] = false,
        ["DELETE"] = false,
        -- exceptions for the healthcheck endpoints:
        ["/upstreams/:upstreams/targets/:targets/healthy"] = {
          ["POST"] = true,
        },
        ["/upstreams/:upstreams/targets/:targets/unhealthy"] = {
          ["POST"] = true,
        },
      },
    }

  },

--------------------------------------------------------------------------------
-- Template for Admin API section of the Navigation file
--------------------------------------------------------------------------------

  nav = {
    header = [[
      - title: Admin API
        url: /admin-api/
        items:
          - text: DB-less
            url: /db-less-admin-api

          - text: Declarative Configuration
            url: /db-less-admin-api/#declarative-configuration
      ]],
  }

}
