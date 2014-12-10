-- This scripts create the base structure for the Cassandra cluster

-- Create the Keyspace
CREATE KEYSPACE "apenode" WITH REPLICATION = {'class' : 'SimpleStrategy', 'replication_factor' : 1};

USE apenode;

-- Create the tables
CREATE TABLE accounts (
  id uuid,
  provider_id text,
  status text,
  created_at timestamp,
  PRIMARY KEY (id, created_at)
);

CREATE TABLE applications (
  id uuid,
  account_id uuid,
  public_key text, -- This is the public
  secret_key text, -- This is the secret key, it could be an apikey or basic password
  status text,
  created_at timestamp,
  PRIMARY KEY (id, account_id)
);

CREATE TABLE apis (
  id uuid,
  name text,
  status text,
  public_dns text,
  target_url text,
  authentication_type text, -- This is the secret key, it could be an apikey or basic password
  authentication_key_names list<text>,
  created_at timestamp,
  PRIMARY KEY (id, public_dns)
);