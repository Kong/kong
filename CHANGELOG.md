## 1.1.2

- chore(*) add copyright

## 1.1.1

- Bump jsonSchema lib to [1.1.1][1.1.1-changelog]

## 1.1.0 (18-aug-2020)

- Bump jsonSchema lib to [1.1.0][1.1.0-changelog]

## 1.0.0 (15-Jul-2020)

- Bump to 1.0.0; considered production ready, and stable
- Fix: require type in jsonschema for parameters, see [#21][pr-21]

## 0.4.2 (16-may-2020)

- Bump ljsonschema lib to 1.0.0, see [jsonSchema #3][jsonschema-pr-3]

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

[jsonschema-pr-3]: https://github.com/Tieske/lua-resty-ljsonschema/pull/3
[pr-21]: https://github.com/Kong/kong-plugin-enterprise-request-validator/pull/21
[1.1.0-changelog]: https://github.com/Tieske/lua-resty-ljsonschema#110-18-aug-2020
[1.1.1-changelog]: https://github.com/Tieske/lua-resty-ljsonschema#111-28-oct-2020
