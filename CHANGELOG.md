# Table of Contents

 - [1.5.1](#151---20190926)
 - [1.5.0](#150---20190813)

## Unreleased

## [1.5.1] - 2019/09/26

#### Summary

This release includes bug fixes and non breaking changes.

#### Under the hood

- `/collector/status` and `/collector/alerts` returns response_code returned by collector server
- `/service_maps` API endpioint proxies the request to `collector` and no longer relies on local storage

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
