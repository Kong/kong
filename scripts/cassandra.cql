-- This scripts create the base structure for the Cassandra cluster

-- Create the Keyspace
CREATE KEYSPACE "apenode" WITH REPLICATION = {'class' : 'SimpleStrategy', 'replication_factor' : 1};

USE apenode;

-- Create the tables
CREATE TABLE accounts (
  id timeuuid,
  provider_id text,
  status text,
  created_at timestamp,
  PRIMARY KEY (id, created_at)
);

CREATE TABLE applications (
  id timeuuid,
  account_id timeuuid,
  public_key text, -- This is the public
  secret_key text, -- This is the secret key, it could be an apikey or basic password
  status text,
  created_at timestamp,
  PRIMARY KEY (id, account_id)
);

CREATE TABLE apis (
  id timeuuid,
  name text,
  status text,
  public_dns text,
  target_url text,
  created_at timestamp,
  PRIMARY KEY (id, public_dns)
);

CREATE TABLE plugins (
  api_id timeuuid,
  application_id timeuuid,
  name text,
  value text, -- We can't use a map because we don't know if the value is a text, int or a list
  PRIMARY KEY ((api_id, application_id, name))
);

CREATE TABLE metrics (
  api_id timeuuid,
  application_id timeuuid,
  name text,
  timestamp timestamp,
  value counter,
  PRIMARY KEY ((api_id, application_id, name), timestamp)
);