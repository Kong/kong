import { v4 as uuidv4, validate as uuidValidate } from 'uuid';
import { teams } from '@fixtures';
import { constants } from '@support';

let EMAIL = '';
let PASSWORD = '';
let EXISTING = false;
const FULL_NAMES: { [key: string]: string } = {};

/**
 * Add a UUID as an alias to the base email and return both
 * @param {string} baseEmail current base email
 * @returns {{ email: string; password: string  }} email alias and password
 */
export const createUuidEmail = (
  baseEmail: string
): {
  email: string;
  password: string;
} => {
  const uuid = uuidv4().toUpperCase();
  const emailParts = baseEmail.split('@');
  const email = `${emailParts[0]}+${uuid}@${emailParts[1]}`;
  EMAIL = email;
  PASSWORD = uuid;
  return { email, password: uuid };
};

/**
 * Set the optional quality base user email and password
 * @param {string} email base quality user email
 */
export const setQualityBaseUser = (email: string) => {
  const emailParts = email.split('@');
  const password = emailParts[0].split('+')[1];
  if (uuidValidate(password)) {
    EMAIL = email;
    PASSWORD = password;
    EXISTING = true;
  } else {
    throw new Error(
      'Quality Base User does not match the quality+<uuid>@konghq.com pattern'
    );
  }
};

/**
 * Get the base user email and password
 * @returns {{ email: string; password: string; existing: boolean  }} base user email and password
 */
export const getBaseUserCredentials = (): {
  email: string;
  password: string;
  existing: boolean;
} => {
  return { email: EMAIL, password: PASSWORD, existing: EXISTING };
};

/**
 * Get the aliased email for the target default team
 * @param {string} team target default team
 * @returns {{ teamEmail: string; password: string  }} email alias and password
 */
export const getTeamUser = (
  team: string
): {
  teamEmail: string;
  password: string;
} => {
  const emailParts = EMAIL.split('@');
  let teamEmail = `${emailParts[0]}+${team}`.substring(0, 64);
  teamEmail = `${teamEmail}@${emailParts[1]}`;
  return { teamEmail, password: PASSWORD };
};

/**
 * Set the user full name for the given default team
 * @param {string} team target default team
 * @param {string} fullName team user full name
 */
export const setTeamFullName = (team: string, fullName: string): void => {
  FULL_NAMES[team] = fullName;
};

/**
 * Get the user full name of the given default team
 * @param {string} team target default team
 * @returns {string} team user full name
 */
export const getTeamFullName = (team: string): string => {
  return FULL_NAMES[team] || `Quality ${team}`;
};

/**
 * Get the AUTH0 konnect admin credentials from the env vars
 * @returns {Credentials} username, password
 */
export const getAuth0UserCreds = () => {
  const username = constants.kauth.GATEWAY_USER.email;
  const password = process.env.KONNECT_USER_PASSWORD;

  if (!password) {
    throw new Error('No KONNECT_USER_PASSWORD env var found, please set the variable to authenticate with Konnect');
  }
  EMAIL = username;
  PASSWORD = password;
  // Auth0 full name for a new org is set to the username
  FULL_NAMES[teams.DefaultTeamNames.ORGANIZATION_ADMIN] = username;
  return { username, password };
};