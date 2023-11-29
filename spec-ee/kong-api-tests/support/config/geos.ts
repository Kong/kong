/**
 * Enum of available geos
 */
export enum Geo {
  us = 'us',
  eu = 'eu',
  au = 'au',
  global = 'global',
}

/**
 * Get the API Geo (us/eu/au) env var (Konnect Apps)
 * @returns {string} us/eu
 */
export const getApiGeo = (): Geo => {
  return (process.env.TEST_API_GEO || Geo.us) as Geo;
};