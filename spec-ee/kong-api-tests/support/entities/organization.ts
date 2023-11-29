import { constants } from "../config/constants";

let ORG_NAME = ''
let ORG_ID = ''
let ORG_CREATED = false;

/**
 * Set the organization name for the current run
 * @param {string} orgName organization name
 */
export const setOrgName = (orgName: string): void => {
  ORG_NAME = orgName;
};

/**
 * Get the organization name for the current run
 * @param {boolean} isKonnect option to use short name for konnect
 * @returns {string} organization name
 */
export const getOrgName = (isKonnect = false): string => {
  return (
    ORG_NAME ||
    (isKonnect ? 'Quality Engineering' : constants.kauth.BASE_USER.organization)
  );
};

/**
 * Set the organization ID for the current run
 * @param {string} orgId organization id
 */
export const setOrgId = (orgId: string | undefined): void => {
  ORG_ID = orgId || '';
};

/**
 * Get the organization ID for the current run
 * @returns {string} organization id
 */
export const getOrgId = (): string => {
  return ORG_ID;
};

/**
 * Set the organization created flag for cleanup
 * @param {string} wasCreated whether the set org was created
 */
export const setOrgCreated = (wasCreated: boolean): void => {
  ORG_CREATED = wasCreated;
};

/**
 * Get whether the organization was created for cleanup
 * @returns {boolean} whether the set org was created
 */
export const wasOrgCreated = (): boolean => {
  return ORG_CREATED;
};