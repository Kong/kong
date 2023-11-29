// const Influx = require('influx');
import { InfluxDB } from 'influx';
import { Environment, getBasePath, isGateway } from '../config/environment';

export let influx: any;

// for debugging you can enter the influxdb CLI via the below command from influx container
// influx -precision rfc3339

// for npm influx documentation
// https://node-influx.github.io/class/src/index.js~InfluxDB.html#instance-method-query

// Measurements in InfluxDB for Kong
const SERIES = {
  KONG_REQUEST: 'kong_request',
  KONG_DATASTORE_CACHE: 'kong_datastore_cache',
};

/**
 * Initialize new influxDB connection
 * @returns {object}
 */
export const createInfluxDBConnection = () => {
  const host = getBasePath({ environment: isGateway() ? Environment.gateway.hostName : undefined });

  const influxDBUrl = `http://${host}:8086/kong`;

  influx = new InfluxDB(influxDBUrl);
  return influx;
};

/**
 * Retrieves all entries from the kong_request mesurement
 * @param {number} expectedEntryCount - total expected entry count to wait for
 * @param {number} retries - how many times to retry
 * @param {number} interval - interval to check again
 * @returns {Array}
 */
export const getAllEntriesFromKongRequest = async (
  expectedEntryCount?: number,
  retries = 10,
  interval = 2000
): Promise<object> => {
  let entries = await influx.query(`select * from ${SERIES.KONG_REQUEST}`);
  let actualCount = 0;

  // wait for expected entry count to appear in influxdb
  if (expectedEntryCount && entries.length !== expectedEntryCount) {
    while (entries.length !== expectedEntryCount) {
      await new Promise((resolve) => setTimeout(resolve, interval));
      entries = await influx.query(`select * from ${SERIES.KONG_REQUEST}`);

      if (retries === actualCount) break;
      actualCount++;
    }
  }

  return entries;
};

/**
 * Retrieves all entries from the kong_request mesurement
 * @returns {Array}
 */
export const getAllEntriesFromKongDatastoreCache =
  async (): Promise<object> => {
    const entries = await influx.query(
      `select * from ${SERIES.KONG_DATASTORE_CACHE}`
    );

    return entries;
  };

/**
 * Get all existing data from a particular TAG or field
 * @param {number} indexOfEntry
 * @returns {object}
 */
export const getAllDataFromTargetTagOrField = async (
  indexOfEntry: number
): Promise<object> => {
  const entries = await influx.query(`select * from ${indexOfEntry}`);
  return entries;
};

/**
 * Execute custom query in influxDB
 * @param {string} customQuery
 * @returns {object}
 */
export const executeCustomQuery = async (
  customQuery: string
): Promise<object> => {
  const result = await influx.query(customQuery);
  return result;
};

/**
 * Delete all data from kong_request meaasurements
 */
export const deleteAllDataFromKongRequest = async () => {
  await influx.dropSeries({ measurement: SERIES.KONG_REQUEST });
  return;
};

/**
 * Delete all data from kong_datastore_cache meaasurements
 */
export const deleteAllDataFromKongDatastoreCache = async () => {
  await influx.dropSeries({ measurement: SERIES.KONG_DATASTORE_CACHE });
  return;
};
