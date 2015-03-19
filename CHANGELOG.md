## [Unreleased][unreleased]

#### Added
- Required Openresty is now `1.7.10.1`.
- Anonymous error reporting on Proxy and API. #64
- Better handling of plugins: Kong now detects which plugins are configured and if they are installed on the current machine. Order of `enabled_plugins` doesn't matter anymore.
- **Proxy**: APIs/Accounts caching with expiration for faster authentication.
- **API**: Plugins now use plain form parameters for configuration. #70
- Easier configuration file (unified in `kong.yml`).
- `bin/kong` now defaults on `/etc/kong.yml` for config and `/var/logs/kong` for output. #71
- Embed migrations execution in the first `kong start`. `migrate` is not a CLI command anymore, one need to use `db.lua`. #68
- Keep track of already executed migrations. `rollback` now behaves as expected.
- In configuration, `plugins_installed` was renamed to `plugins_available` #59.

#### Fixed
- `Server` header now sends Kong.
- migrations not being executed in order on Linux. This issue wasn't noticed until unit testing the migrations because for now we only have 1 migration file.
- **API**: Errors responses are now sent as JSON.

**Nerds stuff**
- We now have code linting and coverage (496c1e6).
- Code is linted (517e7fb).
- Sub-schema validation (1b5064e).
- Faker and Migrations instances don't live in the DAO Factory anymore, they are only used in scripts and tests.
- `scripts/config.lua` allows environment based configurations. `make dev` generates a `kong.DEVELOPMENT.yml` and `kong_TEST.yml`. Different keyspaces, ports...
- `spec_helpers.lua` allows tests to not rely on the `Makefile` anymore. Integration tests can run 100% from busted.
- Switch from httpbin.org to mockbin.com
- Renamed `core` plugin to `resolver`.

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

[unreleased]: https://github.com/mashape/kong/compare/0.0.1-beta...HEAD
[0.0.1-beta]: https://github.com/mashape/kong/compare/ffd70b3101ba38d9acc776038d124f6e2fccac3c...0.0.1-beta
