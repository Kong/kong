## 0.2

### Added

- Added filter by status code functionality for responses to be logged.
Admin from now on can add status code ranges for responses which want to
be logged and sent to StatsD server. If Admin doesn't provide any status
code, all responses will be logged.

### Changed

- Changed to use new dao

## 0.1.2

- Add workspace support with new metrics `status_count_per_workspace`

## 0.1.1

- Replace string.gsub with JIT-able ngx.re.gsub calls.
- Add optional node name prefix.

## 0.1.0

- Initial release of StatsD EE plugin for Kong.
