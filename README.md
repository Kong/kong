# Kong Azure Functions Plugin

[![Build Status][badge-travis-image]][badge-travis-url]


This plugin invokes
[Azure Functions](https://azure.microsoft.com/en-us/services/functions/).
It can be used in combination with other request plugins to secure, manage
or extend the function.

Please see the [plugin documentation](https://docs.konghq.com/hub/kong-inc/azure-functions/)
for details on installation and usage.

# History

Version is strictly based on [SemVer](https://semver.org/)

### Releasing new versions

- update changelog below
- update rockspec version
- update version in `handler.lua`
- commit as `release x.y.z`
- tag commit as `x.y.z`
- push commit and tags
- upload to luarocks; `luarocks upload kong-plugin-azure-functions-x.y.z-1.rockspec --api-key=abc...`
- test rockspec; `luarocks install kong-plugin-azure-functions`

### 1.0.0 19-Nov-2020
- Fix: pass incoming headers, issue [#15](https://github.com/Kong/kong-plugin-azure-functions/issues/15)

### 0.4.2 06-Dec-2019
- Updated tests

### 0.4.1 13-Nov-2019
- Remove the no-longer supported `run_on` field from plugin config schema

### 0.4.0
- Fix #7 (run_on in schema should be in toplevel fields table)
- Remove BasePlugin inheritance (not needed anymore)

### 0.3.1
- Fix invalid references to functions invoked in the handler module
- Strip connections headers disallowed by HTTP/2

### 0.3.0
- Restrict the `config.run_on` field to `first`

### 0.2.0
- Use of new db & PDK functions
- kong version compatibility bumped to >= 0.15.0

### 0.1.1
- Fix delayed response
- Change "Server" header to "Via" header and only add it when configured

### 0.1.0 Initial release

[badge-travis-url]: https://travis-ci.com/Kong/kong-plugin-azure-functions/branches
[badge-travis-image]: https://travis-ci.com/Kong/kong-plugin-azure-functions.svg?branch=master
