## 0.1.0

### Added

- This is a fork of Kong's [response-transformer][response-transformer-plugin]
plugin with the following additions:
  * Conditional transformations: each transformation type (i.e., replace, remove,
  add, append) can be conditionally applied, depending on the response status -
  fulfilling use cases like "remove the response body if the response code is
  500". The `if_status` configuration item , which is part of each transform type
  (e.g., `replace.if_status`), controls this behavior
  * Introduced an option to replace the entire body of a response, as opposed to
  only a specific JSON field. This allows for replacing the response body with
  arbitrary data. The configuration item `replace.body` controls this behavior


---
[response-transformer-plugin]: https://docs.konghq.com/hub/kong-inc/response-transformer/
