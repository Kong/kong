# Table of Contents

- [0.6.0](#060---20190929)
- [0.5.0](#050---20190916)
- [0.4.1](#041---20190801)
- [0.4.0](#040---20190605)
- [0.3.4](#034---20181217)
- [0.3.3](#033---20181214)
- [0.3.2](#032---20181101)
- [0.3.1](#031---20181017)
- [0.3.0](#030---20181015)
- [0.2.0](#020---20180924)
- [0.1.0](#010---20180615)

##  [0.6.0] - 2019/09/29

- **Metrics on Status API:** Metrics are now be available on the Status API
  (Status API is being shipped with Kong 1.4).
  [#66](https://github.com/Kong/kong-plugin-prometheus/pull/66)

##  [0.5.0] - 2019/09/16

- **Route based metrics:**  All proxy metrics now contain a tag with the name
  or ID of the route.
  [#40](https://github.com/Kong/kong-plugin-prometheus/issues/40)
- **New metrics releated to Kong's memory usage:**
  New metrics related to Kong's shared dictionaries
  and Lua VMs are now available
  [#62](https://github.com/Kong/kong-plugin-prometheus/pull/62):
  - per worker Lua VM allocated bytes (`kong_memory_workers_lua_vms_bytes`)
  - shm capacity and bytes allocated (`kong_memory_lua_shared_dict_bytes` and
    `kong_memory_lua_shared_dict_total_bytes`)
- Performance has been improved by avoiding unnecessary timer creation.
  This will lower the impact of the plugin on Kong's overall latency.
  [#60](https://github.com/Kong/kong-plugin-prometheus/pull/60)
- Tests to ensure gRPC compatibility have been added.
  [#57](https://github.com/Kong/kong-plugin-prometheus/pull/57)

##  [0.4.0] - 2019/06/05

- Remove BasePlugin inheritance (not needed anymore)

##  [0.3.4] - 2018/12/17

- Drop the use of `kong.tools.responses` module for
  Kong 1.0 compatibility.
  [#34](https://github.com/Kong/kong-plugin-prometheus/pull/34)

##  [0.3.3] - 2018/12/14

- Do not attempt to send HTTP status code after the body has been sent
  while serving `/metrics`. This would result in error being logged in Kong.
  [#33](https://github.com/Kong/kong-plugin-prometheus/pull/33)

##  [0.3.2] - 2018/11/01

- Fix a nil pointer de-reference bug when no routes are matched in Kong.
  [#28](https://github.com/Kong/kong-plugin-prometheus/pull/28)

##  [0.3.1] - 2018/10/17

- Fix bugs introduced in 0.3.0 due to incorrect PDK function calls
  Thank you @kikito for the fix!
  [#26](https://github.com/Kong/kong-plugin-prometheus/pull/26)

##  [0.3.0] - 2018/10/15

- This release has no user facing changes but has under the hood
  changes for upcoming Kong 1.0.0 release.
- Migrated schema and API endpoint of the plugin to the new DAO and
  use PDK functions where possible.
  Thank you @kikito for the contribution!
  [#24](https://github.com/Kong/kong-plugin-prometheus/pull/24)

##  [0.2.0] - 2018/09/24

- :warning: Dropped metrics that were aggregated across services in Kong.
  These metrics can be obtained much more efficiently using queries in Prometheus.
  [#8](https://github.com/Kong/kong-plugin-prometheus/pull/8)

##  [0.1.0] - 2018/06/15

- Initial release of Prometheus plugin for Kong.

[0.6.0]: https://github.com/Kong/kong-plugin-prometheus/compare/0.5.0...0.6.0
[0.5.0]: https://github.com/Kong/kong-plugin-prometheus/compare/0.4.1...0.5.0
[0.4.1]: https://github.com/Kong/kong-plugin-prometheus/compare/0.4.0...0.4.1
[0.4.0]: https://github.com/Kong/kong-plugin-prometheus/compare/0.3.4...0.4.0
[0.3.4]: https://github.com/Kong/kong-plugin-prometheus/compare/0.3.3...0.3.4
[0.3.3]: https://github.com/Kong/kong-plugin-prometheus/compare/0.3.2...0.3.3
[0.3.2]: https://github.com/Kong/kong-plugin-prometheus/compare/0.3.1...0.3.2
[0.3.1]: https://github.com/Kong/kong-plugin-prometheus/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/Kong/kong-plugin-prometheus/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/Kong/kong-plugin-prometheus/compare/0.1.0...0.2.0
[0.1.0]: https://github.com/Kong/kong-plugin-prometheus/commit/dc81ea15bd2b331beb8f59176e3ce0fd9007ec03
