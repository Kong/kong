## 1.0.0

### Changed

- Convert to new dao
- Use PDK

## 0.31.4

### Changed
 - Internal improvements

## 0.31.3

### Fixed

- Fix issue preventing the plugin to load configuration and create sync timers
- Fix issue preventing the plugin to correctly propagate configuration changes
among Kong Nginx workers

## 0.31.2

### Fixed

- Fix a typo in Cassandra migration
- Fix selection of dictionary used for counters

## 0.31.1

### Changed

- The default shared dictionary for storing RL counters is now
  `kong_rate_limiting_counters` - which is also used by Kong CE rate-limiting

### Added

## 0.31.0

- Plugin was moved out of Kong Enterprise core into its own repository
