## [Unreleased][unreleased]

## [0.1.0-beta] - 2015/03/19

New beta with caching, easier usability and the usual fixes.

#### Added
- Required Openresty is now `1.7.10.1`.
- New CLI, rewritten in Lua
- `kong start` using a new DB keyspace will automatically migrate the schema. [#68](https://github.com/Mashape/kong/issues/68)
- Anonymous error reporting on Proxy and API. [#64](https://github.com/Mashape/kong/issues/64)
- Configuration:
  - Simplified configuration file (unified in `kong.yml`).
  - In configuration, `plugins_installed` was renamed to `plugins_available`. [#59](https://github.com/Mashape/kong/issues/59)
  - Order of `plugins_available` doesn't matter anymore. [#17](https://github.com/Mashape/kong/issues/17)
  - Better handling of plugins: Kong now detects which plugins are configured and if they are installed on the current machine.
  - `bin/kong` now defaults on `/etc/kong.yml` for config and `/var/logs/kong` for output. [#71](https://github.com/Mashape/kong/issues/71)
- **Proxy**: APIs/Accounts caching with expiration for faster authentication.
- **API**: Plugins now use plain form parameters for configuration. [#70](https://github.com/Mashape/kong/issues/70)
- Keep track of already executed migrations. `rollback` now behaves as expected. [#8](https://github.com/Mashape/kong/issues/8)

#### Fixed
- `Server` header now sends Kong. [#57](https://github.com/Mashape/kong/issues/57)
- migrations not being executed in order on Linux. This issue wasn't noticed until unit testing the migrations because for now we only have 1 migration file.
- **API**: Errors responses are now sent as JSON. [#58](https://github.com/Mashape/kong/issues/58)

> **Nerds stuff**
> - We now have code linting and coverage.
> - Faker and Migrations instances don't live in the DAO Factory anymore, they are only used in scripts and tests.
> - `scripts/config.lua` allows environment based configurations. `make dev` generates a `kong.DEVELOPMENT.yml` and `kong_TEST.yml`. Different keyspaces and ports.
> - `spec_helpers.lua` allows tests to not rely on the `Makefile` anymore. Integration tests can run 100% from `busted`.
> - Switch integration testing from [httpbin.org] to [mockbin.com].
> - `core` plugin was renamed to `resolver`.

## [0.0.1-beta] - 2015/02/25

First beta version running with Cassandra.

#### Added
- Basic proxying.
- Built-in authentication plugin (api key, HTTP basic).
- Built-in ratelimiting plugin.
- Built-in TCP logging plugin.
- Configuration API (for accounts, apis, plugins).
- CLI `bin/kong` script.
- Database migrations (using `db.lua`).

[unreleased]: https://github.com/mashape/kong/compare/0.1.0-beta...HEAD
[0.1.0-beta]: https://github.com/mashape/kong/compare/0.0.1-beta...0.1.0-beta
[0.0.1-beta]: https://github.com/mashape/kong/compare/ffd70b3101ba38d9acc776038d124f6e2fccac3c...0.0.1-beta
