# Table of Contents

- [1.3.0](#130---20210527)
- [1.2.1](#121---20210415)
- [1.2.0](#120---20210324)
- [1.1.0](#110---20210303)
- [1.0.0](#100---20200820)
- [0.9.0](#090---20200617)
- [0.8.0](#080---20200424)
- [0.7.1](#071---20200105)
- [0.7.0](#070---20191204)
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

##  [1.3.0] - 2021/05/27

- Fix exporter to attach subsystem label to memory stats
  [#118](https://github.com/Kong/kong-plugin-prometheus/pull/118)
- Expose dataplane status on control plane, new metrics `data_plane_last_seen`,
  `data_plane_config_hash` and `data_plane_version_compatible` are added.
  [#98](https://github.com/Kong/kong-plugin-prometheus/pull/98)

##  [1.2.1] - 2021/04/15

- Fix an issue where the Content-Length header could be potentially mispelled
  [#124](https://github.com/Kong/kong-plugin-prometheus/pull/124)

##  [1.2.0] - 2021/03/24

- Fix an issue where there's no stream listener or stream API is not available,
/metrics endpoint may timeout [#108](https://github.com/Kong/kong-plugin-prometheus/pull/108)
- Export per-consumer status [#115](https://github.com/Kong/kong-plugin-prometheus/pull/115)
(Thanks, [samsk](https://github.com/samsk)!)

##  [1.1.0] - 2021/03/03

- Export Kong Enterprise Edition licensing information.
  [#110](https://github.com/Kong/kong-plugin-prometheus/pull/110)

##  [1.0.0] - 2020/08/20

- Change handler to use Kong PDK function kong.log.serialize instead of using
  a deprecated basic serializer.

##  [0.9.0] - 2020/06/17

- Expose healthiness of upstream targets
  (Thanks, [carnei-ro](https://github.com/carnei-ro)!)
  [#88](https://github.com/Kong/kong-plugin-prometheus/pull/88)
- Fix a typo on the dashboard
  (Thanks, [Monska85](https://github.com/Monska85)!)

##  [0.8.0] - 2020/04/24

- Expose the `prometheus` object for custom metrics
  [#78](https://github.com/Kong/kong-plugin-prometheus/pull/78)
- Significant performance enhancements; expect manifolds improvements in
  Kong's throughput while using the plugin and reduction in CPU usage while
  memory usage is expected to go up.
  [#79](https://github.com/Kong/kong-plugin-prometheus/pull/79)

##  [0.7.1] - 2020/01/05

- Fix `full_metric_name` function was not accessible
- Fix linting issues

##  [0.7.0] - 2019/12/04

- **Performance improvements:** Reduced the number of writes (and hence locks)
  to the shared dictionary using lua-resty-counter library.
  (Status API is being shipped with Kong 1.4).
  [#69](https://github.com/Kong/kong-plugin-prometheus/pull/69)
- Update schema for the plugin for Kong 2.0 compatibility
  [#72](https://github.com/Kong/kong-plugin-prometheus/pull/72)

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

##  [0.4.1] - 2019/08/01

- Fix issue where the plugin's shared dictionary would not be properly
initialized

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

[1.3.0]: https://github.com/Kong/kong-plugin-prometheus/compare/1.2.1...1.3.0
[1.2.1]: https://github.com/Kong/kong-plugin-prometheus/compare/1.2.0...1.2.1
[1.2.0]: https://github.com/Kong/kong-plugin-prometheus/compare/1.1.0...1.2.0
[1.1.0]: https://github.com/Kong/kong-plugin-prometheus/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/Kong/kong-plugin-prometheus/compare/0.9.0...1.0.0
[0.9.0]: https://github.com/Kong/kong-plugin-prometheus/compare/0.8.0...0.9.0
[0.8.0]: https://github.com/Kong/kong-plugin-prometheus/compare/0.7.1...0.8.0
[0.7.1]: https://github.com/Kong/kong-plugin-prometheus/compare/0.7.0...0.7.1
[0.7.0]: https://github.com/Kong/kong-plugin-prometheus/compare/0.6.0...0.7.0
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
