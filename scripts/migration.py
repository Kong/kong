#!/usr/bin/env python

'''Kong 0.5.0 Migration Script

Usage: python migration.py --config=/path/to/kong/config

Arguments:
  -c, --config   path to your Kong configuration file

Flags:
  -h             print help
'''

import getopt, sys, os.path, logging

log = logging.getLogger()
log.setLevel("INFO")
handler = logging.StreamHandler()
handler.setFormatter(logging.Formatter("[%(levelname)s]: %(message)s"))
log.addHandler(handler)

try:
    import yaml
    from cassandra.cluster import Cluster
except ImportError as err:
    log.error(err)
    log.info("""This script requires cassandra-driver and PyYAML:
    $ pip install cassandra-driver pyyaml""")
    sys.exit(1)

session = None

class ArgumentException(Exception):
    pass

def usage():
    """
    Print usage informations about this script.
    """
    print sys.exit(__doc__)

def shutdown_exit(exit_code):
    """
    Shutdown the Cassandra session and exit the script.
    """
    session.shutdown()
    sys.exit(exit_code)

def load_cassandra_config(kong_config):
    """
    Return a host and port from the first contact point in the Kong configuration.

    :param kong_config: parsed Kong configuration
    :return: host and port tuple
    """
    cass_properties = kong_config["databases_available"]["cassandra"]["properties"]

    host, port = cass_properties["hosts"][0].split(":")
    keyspace = cass_properties["keyspace"]

    return (host, port, keyspace)

def migrate_schema_migrations_table(session):
    """
    Migrate the schema_migrations table whose values changed between < 0.5.0 and 0.5.0

    :param session: opened cassandra session
    """
    query = "INSERT INTO schema_migrations(id, migrations) VALUES(%s, %s)"
    session.execute(query, ["core", ['2015-01-12-175310_skeleton', '2015-01-12-175310_init_schema']])
    session.execute(query, ["basic-auth", ['2015-08-03-132400_init_basicauth']])
    session.execute(query, ["keyauth", ['2015-07-31-172400_init_keyauth']])
    session.execute(query, ["ratelimiting", ['2015-08-03-132400_init_ratelimiting']])
    session.execute(query, ["oauth2", ['2015-08-03-132400_init_oauth2', '2015-08-24-215800_cascade_delete_index']])
    log.info("schema_migrations table migrated")

def migrate_schema_migrations_remove_legacy_row(session):
    session.execute("DELETE FROM schema_migrations WHERE id = 'migrations'")
    log.info("Legacy values removed from schema_migrations table")

def migrate_plugins_renaming(session):
    """
    Migrate the plugins_configurations table by renaming all plugins whose name changed.

    :param session: opened cassandra session
    """
    log.info("Renaming plugins")
    new_names = {
        "keyauth": "key-auth",
        "basicauth": "basic-auth",
        "ratelimiting": "rate-limiting",
        "tcplog": "tcp-log",
        "udplog": "udp-log",
        "filelog": "file-log",
        "httplog": "http-log",
        "request_transformer": "request-transformer",
        "response_transfomer": "response-transfomer",
        "requestsizelimiting": "request-size-limiting",
        "ip_restriction": "ip-restriction"
    }

    for plugin in session.execute("SELECT * FROM plugins_configurations"):
        plugin_name = plugin.name
        if plugin.name in new_names:
            plugin_name = new_names[plugin.name]

        session.execute("DELETE FROM plugins_configurations WHERE id = %s", [plugin.id])
        session.execute("""
            INSERT INTO plugins_configurations(id, name, api_id, consumer_id, created_at, enabled, value)
            VALUES(%s, %s, %s, %s, %s, %s, %s)
        """, [plugin.id, plugin_name, plugin.api_id, plugin.consumer_id, plugin.created_at, plugin.enabled, plugin.value])

def migrate(kong_config):
    """
    Instanciate a Cassandra session and decides if the keyspace needs to be migrated
    by looking at what the schema_migrations table contains.

    :param kong_config: parsed Kong configuration
    :return: True if some migrations were ran, False otherwise
    """
    host, port, keyspace = load_cassandra_config(kong_config)
    cluster = Cluster([host], protocol_version=2, port=port)
    global session
    session = cluster.connect(keyspace)

    rows = session.execute("SELECT * FROM schema_migrations")
    if len(rows) == 1 and rows[0].id == "migrations":
        last_executed_migration = rows[0].migrations[-1]
        if last_executed_migration != "2015-08-10-813213_0.4.2":
            log.error("Please migrate your cluster to Kong 0.4.2 before running this script.")
            shutdown_exit(1)

        log.info("Schema_migrations table needs migration")
        migrate_schema_migrations_table(session)
        migrate_schema_migrations_remove_legacy_row(session)
        migrate_plugins_renaming(session)

    elif len(rows) > 1:
        # apparently kong was restarted without previously running this script
        if any(row.id == "migrations" for row in rows):
            log.info("Already migrated to 0.5.0, but legacy schema found. Purging.")
            migrate_schema_migrations_remove_legacy_row(session)
            migrate_plugins_renaming(session)
        else:
            return False

    return True

def parse_arguments(argv):
    """
    Parse the scripts arguments.

    :param argv: scripts arguments
    :return: parsed kong configuration
    """
    config_path = ""

    opts, args = getopt.getopt(argv, "hc:", ["config="])
    for opt, arg in opts:
        if opt == "-h":
            usage()
        elif opt in ("-c", "--config"):
            config_path = arg

    if config_path == "":
        raise ArgumentException("No Kong configuration given")
    elif not os.path.isfile(config_path):
        raise ArgumentException("No configuration file at path %s" % str(arg))

    log.info("Using Kong configuration file at: %s" % os.path.abspath(config_path))

    with open(config_path, "r") as stream:
        config = yaml.load(stream)

    return config

def main(argv):
    try:
        config = parse_arguments(argv)
        if migrate(config):
            log.info("Schema migrated to Kong 0.5.0.")
        else:
            log.info("Schema already migrated to Kong 0.5.0.")
        shutdown_exit(0)
    except getopt.GetoptError as err:
        log.error(err)
        usage()
    except ArgumentException as err:
        log.error("Bad argument: %s " % err)
        usage()
    except yaml.YAMLError as err:
        log.error("Cannot parse given configuration file: %s" % err)
        sys.exit(1)

if __name__ == "__main__":
    main(sys.argv[1:])
