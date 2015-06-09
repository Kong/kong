## [Unreleased][unreleased]

## [0.3.2] - 2015/06/08

#### Fixed

- Fix uppercase Cassandra keyspace bug that prevented Kong to work with [kongdb.org](http://kongdb.org/)

## [0.3.1] - 2015/06/07

#### Fixed

- Schema migrations are now automatic, which was missing from previous releases. [#303](https://github.com/Mashape/kong/issues/303)

## [0.3.0] - 2015/06/04

#### Added

- Support for SSL.
- Plugins
  - New HTTP logging plugin. [#226](https://github.com/Mashape/kong/issues/226) [#251](https://github.com/Mashape/kong/pull/251)
  - New SSL plugin.
  - New request size limiting plugin. [#292](https://github.com/Mashape/kong/pull/292)
  - Default logging format improvements. [#226](https://github.com/Mashape/kong/issues/226) [#262](https://github.com/Mashape/kong/issues/262)
  - File logging now logs to a custom file. [#202](https://github.com/Mashape/kong/issues/202)
  - Keyauth plugin now defaults `key_names` to "apikey".
- Admin API
  - RESTful routing. Much nicer Admin API routing. Ex: `/apis/{name_or_id}/plugins`. [#98](https://github.com/Mashape/kong/issues/98) [#257](https://github.com/Mashape/kong/pull/257)
  - Support `PUT` method for endpoints such as `/apis/`, `/apis/plugins/`, `/consumers/`
  - Support for `application/json` and `x-www-form-urlencoded` Content Types for all `PUT`, `POST` and `PATCH` endpoints by passing a `Content-Type` header. [#236](https://github.com/Mashape/kong/pull/236)
- Resolver
  - Support resolving APIs by Path as well as by Header. [#192](https://github.com/Mashape/kong/pull/192) [#282](https://github.com/Mashape/kong/pull/282)
  - Support for `X-Host-Override` as an alternative to `Host` for browsers. [#203](https://github.com/Mashape/kong/issues/203) [#246](https://github.com/Mashape/kong/pull/246)
- Auth plugins now send user informations to your upstream services. [#228](https://github.com/Mashape/kong/issues/228)
- Invalid `target_url` value are now being catched when creating an API. [#149](https://github.com/Mashape/kong/issues/149)

#### Fixed

- Fix uppercase Cassandra keyspace causing migration failure. [#249](https://github.com/Mashape/kong/issues/249)
- Guarantee that ratelimiting won't allow requests in case the atomicity of the counter update is not guaranteed. [#289](https://github.com/Mashape/kong/issues/289)

> **internal**
> - Schemas:
>   - New property type: `array`. [#277](https://github.com/Mashape/kong/pull/277)
>   - Entities schemas now live in their own files and are starting to be unit tested.
>   - Subfields are handled better: (notify required subfields and auto-vivify is subfield has default values).
> - Way faster unit tests. Not resetting the DB anymore between tests.
> - Improved coverage computation (exclude `vendor/`).
> - Travis now lints `kong/`.
> - Way faster Travis setup.
> - Added a new HTTP client for in-nginx usage, using the cosocket API.
> - Various refactorings.
> - Fix [#196](https://github.com/Mashape/kong/issues/196).
> - Disabled ipv6 in resolver.

## [0.2.1] - 2015/05/12

This is a maintenance release including several bug fixes and usability improvements.

#### Added
- Support for local DNS resolution. [#194](https://github.com/Mashape/kong/pull/194)
- Support for Debian 8 and Ubuntu 15.04.
- DAO
  - Cassandra version bumped to 2.1.5
  - Support for Cassandra downtime. If Cassandra goes down and is brought back up, Kong will not need to restart anymore, statements will be re-prepared on-the-fly. This is part of an ongoing effort from [jbochi/lua-resty-cassandra#47](https://github.com/jbochi/lua-resty-cassandra/pull/47), [#146](https://github.com/Mashape/kong/pull/146) and [#187](https://github.com/Mashape/kong/pull/187).
Queries effectued during the downtime will still be lost. [#11](https://github.com/Mashape/kong/pull/11)
  - Leverage reused sockets. If the DAO reuses a socket, it will not re-set their keyspace. This should give a small but appreciable performance improvement. [#170](https://github.com/Mashape/kong/pull/170)
  - Cascade delete plugins configurations when deleting a Consumer or an API associated with it. [#107](https://github.com/Mashape/kong/pull/107)
  - Allow Cassandra hosts listening on different ports than the default. [#185](https://github.com/Mashape/kong/pull/185)
- CLI
  - Added a notice log when Kong tries to connect to Cassandra to avoid user confusion. [#168](https://github.com/Mashape/kong/pull/168)
  - The CLI now tests if the ports are already being used before starting and warns.
- Admin API
  - `name` is now an optional property for APIs. If none is being specified, the name will be the API `public_dns`. [#181](https://github.com/Mashape/kong/pull/181)
- Configuration
  - The memory cache size is now configurable. [#208](https://github.com/Mashape/kong/pull/208)

#### Fixed
- Resolver
  - More explicit "API not found" message from the resolver if the Host was not found in the system. "Api not foun with Host: %s".
  - If multiple hosts headers are being sent, Kong will test them all to see if one of the API is in the system. [#186](https://github.com/Mashape/kong/pull/186)
- Admin API: responses now have a new line after the body. [#164](https://github.com/Mashape/kong/issues/164)
- DAO: keepalive property is now properly passed when Kong calls `set_keepalive` on Cassandra sockets.
- Multipart dependency throwing error at startup. [#213](https://github.com/Mashape/kong/pull/213)

> **internal**
> - Separate Migrations from the DAO factory.
> - Update dev config + Makefile rules (`run` becomes `start`).
> - Introducing an `ngx` stub for unit tests and CLI.
> - Switch many PCRE regexes to using patterns.

## [0.2.0-2] - 2015/04/27

First public release of Kong. This version brings a lot of internal improvements as well as more usability and a few additional plugins.

#### Added
- Plugins
  - CORS plugin.
  - Request transformation plugin.
  - NGINX plus monitoring plugin.
- Configuration
  - New properties: `proxy_port` and `api_admin_port`. [#142](https://github.com/Mashape/kong/issues/142)
- CLI
  - Better info, help and error messages. [#118](https://github.com/Mashape/kong/issues/118) [#124](https://github.com/Mashape/kong/issues/124)
  - New commands: `kong reload`, `kong quit`. [#114](https://github.com/Mashape/kong/issues/114) Alias of `version`: `kong --version` [#119](https://github.com/Mashape/kong/issues/119)
  - `kong restart` simply starts Kong if not previously running + better pid file handling. [#131](https://github.com/Mashape/kong/issues/131)
- Package distributions: .rpm, .deb and .pkg for easy installs on most common platforms.

#### Fixed
- Admin API: trailing slash is not necessary anymore for core ressources such as `/apis` or `/consumers`.
- Leaner default configuration. [#156](https://github.com/Mashape/kong/issues/156)

> **internal**
> - All scripts moved to the CLI as "hidden" commands (`kong db`, `kong config`).
> - More tests as always, and they are structured better. The coverage went down mainly because of plugins which will later move to their own repos. We are all eagerly waiting for that!
> - `src/` was renamed to `kong/` for ease of development
> - All system dependencies versions for package building and travis-ci are now listed in `versions.sh`
> - DAO doesn't need to `:prepare()` prior to run queries. Queries can be prepared at runtime. [#146](https://github.com/Mashape/kong/issues/146)

## [0.1.1beta-2] - 2015/03/30

#### Fixed

- Wrong behaviour of auto-migration in `kong start`.

## [0.1.0beta-3] - 2015/03/25

First public beta. Includes caching and better usability.

#### Added
- Required Openresty is now `1.7.10.1`.
- Freshly built CLI, rewritten in Lua
- `kong start` using a new DB keyspace will automatically migrate the schema. [#68](https://github.com/Mashape/kong/issues/68)
- Anonymous error reporting on Proxy and API. [#64](https://github.com/Mashape/kong/issues/64)
- Configuration
  - Simplified configuration file (unified in `kong.yml`).
  - In configuration, `plugins_installed` was renamed to `plugins_available`. [#59](https://github.com/Mashape/kong/issues/59)
  - Order of `plugins_available` doesn't matter anymore. [#17](https://github.com/Mashape/kong/issues/17)
  - Better handling of plugins: Kong now detects which plugins are configured and if they are installed on the current machine.
  - `bin/kong` now defaults on `/etc/kong.yml` for config and `/var/logs/kong` for output. [#71](https://github.com/Mashape/kong/issues/71)
- Proxy: APIs/Consumers caching with expiration for faster authentication.
- Admin API: Plugins now use plain form parameters for configuration. [#70](https://github.com/Mashape/kong/issues/70)
- Keep track of already executed migrations. `rollback` now behaves as expected. [#8](https://github.com/Mashape/kong/issues/8)

#### Fixed
- `Server` header now sends Kong. [#57](https://github.com/Mashape/kong/issues/57)
- migrations not being executed in order on Linux. This issue wasn't noticed until unit testing the migrations because for now we only have 1 migration file.
- Admin API: Errors responses are now sent as JSON. [#58](https://github.com/Mashape/kong/issues/58)

> **internal**
> - We now have code linting and coverage.
> - Faker and Migrations instances don't live in the DAO Factory anymore, they are only used in scripts and tests.
> - `scripts/config.lua` allows environment based configurations. `make dev` generates a `kong.DEVELOPMENT.yml` and `kong_TEST.yml`. Different keyspaces and ports.
> - `spec_helpers.lua` allows tests to not rely on the `Makefile` anymore. Integration tests can run 100% from `busted`.
> - Switch integration testing from [httpbin.org] to [mockbin.com].
> - `core` plugin was renamed to `resolver`.

## [0.0.1alpha-1] - 2015/02/25

First version running with Cassandra.

#### Added
- Basic proxying.
- Built-in authentication plugin (api key, HTTP basic).
- Built-in ratelimiting plugin.
- Built-in TCP logging plugin.
- Configuration API (for consumers, apis, plugins).
- CLI `bin/kong` script.
- Database migrations (using `db.lua`).

[unreleased]: https://github.com/mashape/kong/compare/0.3.0...HEAD
[0.3.2]: https://github.com/mashape/kong/compare/0.3.1...0.3.2
[0.3.1]: https://github.com/mashape/kong/compare/0.3.0...0.3.1
[0.3.0]: https://github.com/mashape/kong/compare/0.2.1...0.3.0
[0.2.1]: https://github.com/mashape/kong/compare/0.2.0-2...0.2.1
[0.2.0-2]: https://github.com/mashape/kong/compare/0.1.1beta-2...0.2.0-2
[0.1.1beta-2]: https://github.com/mashape/kong/compare/0.1.0beta-3...0.1.1beta-2
[0.1.0beta-3]: https://github.com/mashape/kong/compare/2236374d5624ad98ea21340ca685f7584ec35744...0.1.0beta-3
[0.0.1alpha-1]: https://github.com/mashape/kong/compare/ffd70b3101ba38d9acc776038d124f6e2fccac3c...2236374d5624ad98ea21340ca685f7584ec35744
