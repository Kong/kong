# Kong prometheus plugin

## 1.5.0

Released: 2022-02-09

- Add two new metrics:
  - `kong_db_entities_total` (gauge) total number of entities in the database
  - `kong_db_entity_count_errors` (counter) measures the number of errors
      encountered during the measurement of `kong_db_entities_total`
