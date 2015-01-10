-- This scripts create the base structure for the Cassandra cluster

-- Create the Keyspace
CREATE KEYSPACE "apenode" WITH REPLICATION = {'class' : 'SimpleStrategy', 'replication_factor' : 1};

USE apenode;

-- Create the tables
CREATE TABLE accounts (
  id uuid,
  provider_id text,
  created_at timestamp,
  PRIMARY KEY (id)
);
-- Create index
CREATE INDEX ON accounts(provider_id);
CREATE INDEX ON accounts(created_at);

CREATE TABLE applications (
  id uuid,
  account_id uuid,
  public_key text, -- This is the public
  secret_key text, -- This is the secret key, it could be an apikey or basic password
  created_at timestamp,
  PRIMARY KEY (id)
);
-- Create index
CREATE INDEX ON applications(created_at);
CREATE INDEX ON applications(public_key);
CREATE INDEX ON applications(secret_key);
CREATE INDEX ON applications(account_id);

CREATE TABLE apis (
  id uuid,
  name text,
  public_dns text,
  target_url text,
  created_at timestamp,
  PRIMARY KEY (id)
);
-- Create index
CREATE INDEX ON apis(created_at);
CREATE INDEX ON apis(name);
CREATE INDEX ON apis(public_dns);
CREATE INDEX ON apis(target_url);

CREATE TABLE plugins (
  id uuid,
  api_id uuid,
  application_id uuid,
  name text,
  value text, -- We can't use a map because we don't know if the value is a text, int or a list
  created_at timestamp,
  PRIMARY KEY (id)
);

CREATE INDEX ON plugins(created_at);
CREATE INDEX ON plugins(api_id);
CREATE INDEX ON plugins(application_id);
CREATE INDEX ON plugins(name);

CREATE TABLE metrics (
  api_id uuid,
  application_id uuid,
  name text,
  timestamp timestamp,
  value counter,
  PRIMARY KEY ((api_id, application_id, name), timestamp)
);
