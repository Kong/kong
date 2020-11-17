# Table of Contents

 - [2.0.1](#201---20201117)
 - [2.0.0](#200---20200928)
 - [1.7.9](#179---20200703)
 - [1.7.8](#178---20200617)
 - [1.7.7](#177---20200616)
 - [1.7.4](#174---20200409)
 - [1.7.3](#173---20200408)
 - [1.7.2](#172---20200326)
 - [1.7.1](#171---20200221)
 - [1.6.1](#161---20191021)
 - [1.5.1](#151---20190926)
 - [1.5.0](#150---20190813)

## [2.0.1] - 2020/11/17
- Add copyright headers

## [2.0.0] - 2020/09/28
### Fixed
- Remove /service_maps endpoint
- Update serializer (drops basic_serializer)

## [1.7.9] - 2020/07/03
### Fixed
- Fix a bug that would make the plugin try to parse request/response body regardless of the content-type
- Adapts the plugin to select_all removal. drops basic_serializer usage in access stage

## 1.7.8 - 2020/06/17

#### Summary
- Removing an error log line for when a situation occurs that is normal/expected

## 1.7.7 - 2020/06/16

#### Summary
- Handle the case where the `access` phase doesn't execute.

## [1.7.5] - 2020/05/08

#### Summary
- Remove flush_timeout parameter for collector configuration, set default to 1 when used.

## [1.7.4] - 2020/04/09

#### Summary

- Fixed a bug when content type is unset / body is string type

## [1.7.3] - 2020/04/08

#### Summary

- Fixed a bug that would make the plugin fail to send hars to collector if `log_bodies` is false

## [1.7.2] - 2020/03/26

#### Summary

- Removes unused configuration options

## [1.7.1] - 2020/02/21

#### Summary

- Changes plugin PRIORITY so that it runs before `request-transformer` and `request-transformer-advanced` plugins.
- Changes how we collect request data making collector plugin compatible with `request-transformer` and `request-transformer-advanced`

## [1.7.0] - 2020/02/05

#### Summary

- Added Consumer information to har
- Removed legacy code for har generation. Now we use log features from Kong

#### Breaking changes

- Plugin configuration takes a http_endpoint parameter rather than https, host and port.

## [1.6.1] - 2019/10/21

#### Summary

This release includes bug fixes and non breaking changes.

#### Under the hood

- `/collector/status` and `/collector/alerts` returns response_code returned by collector server
- `/service_maps` API endpoint proxies the request to `collector` and no longer relies on local storage

## [1.5.1] - 2019/09/26

#### Summary

This release includes bug fixes and non breaking changes.

#### Under the hood

- `/collector/status` and `/collector/alerts` returns response_code returned by collector server
- `/service_maps` API endpoint proxies the request to `collector` and no longer relies on local storage

## [1.5.0] - 2019/08/13

#### Summary

This release adds `/collector/alerts` endpoint, which exposes the collector `/alerts` endpoint.
It also changes how `/collector/status` work by not requiring a plugin id anymore.
As a result, the endpoint `/collector/configuration` is not needed anymore and has been removed.
Finally, it adds tests for each of the admin API enpoints.

#### Breaking changes

- `/collector/:collector_id/status` is now just `/collector/status`.
- `/collector/configurations/` has been removed

#### Added

- `/collector/alerts` for exposing `/alerts` from collector server.


#### Under the hood

- Added tests for all admin API endpionts
