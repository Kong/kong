import { gatewayAuthHeader } from '../config/gateway-vars';
import { logDebug } from './logging';
import * as fs from 'fs';
const { authHeaderKey, authHeaderValue } = gatewayAuthHeader();

/**
 * Construct a decK command with the given cmd component
 * @param {object} string - the actual deck command
 */
export const constructDeckCommand = (cmd) => {
  const finalCommand = `deck gateway ${cmd} --headers "${authHeaderKey}: ${authHeaderValue}"`;

  logDebug(`built deck cmd -> ${finalCommand}`);
  return finalCommand;
};

export const read_deck_config = (deckFileName) => {
  return JSON.parse(fs.readFileSync(`./${deckFileName}`, 'utf8'));
};
