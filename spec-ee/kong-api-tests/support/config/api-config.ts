import { Configuration as KAuthConfiguration } from '@kong/kauth-client-typescript-axios';
import { Configuration as KonnectV2Configuration } from '@kong/runtime-groups-api-client';

import {
  App,
  getApp,
  getBasePath,
  isPreview,
} from './environment';

const API_CONFIG = {
  konnect_v2: (): KonnectV2Configuration => {
    const basePath = getBasePath({ app: App.konnect_v2 });
    return new KonnectV2Configuration({
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
  | KonnectV2Configuration => {
  return API_CONFIG[app]({ preview });
};
