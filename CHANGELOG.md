## [Unreleased][unreleased]

#### Added
**Proxy**:
- Required Openresty is now `1.7.10.1`.
- APIs/Accounts caching with expiration for faster authentication.
- Better handling of plugins: Kong now detects which plugins are configured and if they are installed on the current machine. Order of `enabled_plugins` doesn't matter anymore.
- `Server` header now sends Kong.

**API**:
- Errors responses are now sent as JSON.

**CLI**:
- Easier configuration file (unified in `kong.yml`).
- In configuration, "plugins_installed" was renamed to "plugins_available" #59.
- Keep track of already executed migrations. `rollback` now behaves as expected.
- Fix: migrations not being executed in order on Linux. This issue wasn't noticed until unit testing the migrations because for now we only have 1 migration file.

**Nerds stuff**
- We now have code linting and coverage (496c1e6).
- Code is linted (517e7fb).
- Sub-schema validation (1b5064e).
- Faker and Migrations instances don't live in the DAO Factory anymore, they are only used in scripts and tests.
- `scripts/config.lua` allows environment based configurations. `make dev` generates a `kong.DEVELOPMENT.yml` and `kong_TEST.yml`. Different keyspaces, ports...
- `spec_helpers.lua` allows tests to not rely on the `Makefile` anymore. Integration tests can run 100% from busted.
- Switch from httpbin.org to mockbin.com

## [0.0.1-beta] - 2015/02/25

First beta version running with Cassandra.

**Proxy**:
- Basic proxying.
- Built-in authentication plugin (api key, HTTP basic).
- Built-in ratelimiting plugin.
- Built-in TCP logging plugin.

**API**:
- Configuration API (for accounts, apis, plugins).

**CLI**:
- CLI `bin/kong` script.
- Database migrations (`db.lua`).

[unreleased]: https://github.com/mashape/kong/compare/0.0.1-beta...HEAD
[0.0.1-beta]: https://github.com/mashape/kong/compare/ffd70b3101ba38d9acc776038d124f6e2fccac3c...0.0.1-beta
