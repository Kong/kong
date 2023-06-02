local queue_parameter_migration_340 = require('kong.db.migrations.core.queue_parameter_migration_340')
return {
  postgres = {
    up = queue_parameter_migration_340,
  }
}
