let KONNECT_CP_ID = ''

/**
 * Set the Konnect Control Plane ID for the current run
 * @param {string} konnectCpId - konnect control Plane id
 */
export const setKonnectControlPlaneId = (konnectCpId: string | undefined): void => {
  KONNECT_CP_ID = konnectCpId || '';
};

/**
 * Get the Konnect Control Plane ID for the current run
 * @returns {string} - konnect control plane id
 */
export const getKonnectControlPlaneId = (): string => {
  return KONNECT_CP_ID;
};