## [Unreleased][unreleased]

#### Added
**Proxy**:
- APIs/Accounts caching with expiration for faster authentication

**CLI**:
- Easier configuration file (unified in `kong.yml`)
- Keep track of already executed migrations. `rollback` now behaves as expected

## [0.0.1-beta] - 2015/02/25

First beta version running with Cassandra.

**Proxy**:
- Basic proxying
- Built-in authentication plugin (api key, HTTP basic)
- Built-in ratelimiting plugin
- Built-in TCP logging plugin

**API**:
- Configuration API (for accounts, apis, plugins)

**CLI**:
- CLI `bin/kong` script
- Database migrations (`db.lua`)

[unreleased]: https://github.com/mashape/kong/compare/0.0.1-beta...HEAD
[0.0.1-beta]: https://github.com/mashape/kong/compare/ffd70b3101ba38d9acc776038d124f6e2fccac3c...0.0.1-beta
