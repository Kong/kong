## [Unreleased][unreleased]

#### Fixed
- Admin API: responses now have a new line after the body. [#164](https://github.com/Mashape/kong/issues/164)
- keepalive property is now properly passed when Kong calls `set_keepalive` on Cassandra sockets.

## [0.2.0-2] - 2015/04/27

First public release of Kong. This version brings a lot of internal improvements as well as more usability and a few additional plugins.

#### Added
- Request transformation plugin.
- NGINX plus monitoring plugin.
- New configuration properties: `proxy_port` and `api_admin_port`. [#142](https://github.com/Mashape/kong/issues/142)
- CLI improvements:
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
- Configuration:
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

[unreleased]: https://github.com/mashape/kong/compare/0.2.0-2...HEAD
[0.2.0-2]: https://github.com/mashape/kong/compare/0.1.1beta-2...0.2.0-2
[0.1.1beta-2]: https://github.com/mashape/kong/compare/0.1.0beta-3...0.1.1beta-2
[0.1.0beta-3]: https://github.com/mashape/kong/compare/2236374d5624ad98ea21340ca685f7584ec35744...0.1.0beta-3
[0.0.1alpha-1]: https://github.com/mashape/kong/compare/ffd70b3101ba38d9acc776038d124f6e2fccac3c...2236374d5624ad98ea21340ca685f7584ec35744
