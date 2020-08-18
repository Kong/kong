Versioning is strictly based on SemVer
Also make sure to update the version in `handler.lua`

## 1.1.0 (18-aug-2020)

- Bump jsonSchema lib to 1.1.0; see [its changelog](https://github.com/Tieske/lua-resty-ljsonschema#110-18-aug-2020)

## 1.0.0 (15-Jul-2020)

- Bump to 1.0.0; considered production ready, and stable
- Fix: require type in jsonschema for parameters, see [pr #21](https://github.com/Kong/kong-plugin-enterprise-request-validator/pull/21)

## 0.4.2 (16-may-2020)

- Bump ljsonschema lib to 1.0.0, see [pr #3](https://github.com/Tieske/lua-resty-ljsonschema/pull/3)

## 0.4.1

- Add configuration to plugin which allow it to return validation error back
  to the client as part of request response

## 0.4.0

- bump lua-resty-jsonschema to fix issue with too many local variables
  being generated

## 0.3.0

- Add parameter validation support
- Add an option to override validation for specific content type

## 0.2.0

- Add support for JSON Schema Draft 4

## 0.1.0

### Added

- Add initial code of the plugin

