import { Configuration as KAuthConfiguration } from '@kong/kauth-client-typescript-axios';
import { Configuration as KonnectConfiguration } from '@kong/khcp-api-client';

import {
  App,
  getApp,
  getBasePath,
  isPreview,
} from './environment';

const API_CONFIG = {
  konnect: (): KonnectConfiguration => {
    const basePath = getBasePath({ app: App.konnect });
    return new KonnectConfiguration({
      basePath,
      baseOptions: { validateStatus: false },
    });
  },
};

/**
 * Get the API config for the target app
 * @param {string} app optional target app (default from env)
 * @returns app API config
 */
export const getApiConfig = (
  app: string = getApp(),
  preview: boolean = isPreview()
):
  | KAuthConfiguration
  | KonnectConfiguration => {
  return API_CONFIG[app]({ preview });
};
