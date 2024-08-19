import { getApiGeo } from '../config/geos';

const CONTROL_PLANE_IDS: { [key: string]: { [key: string]: string } } = {};

/**
 * Set the control plane ID for the current run
 * @param {string} controlPlaneId control plane id
 * @param {string} controlPlaneName control plane name (default: default)
 * @param {Geo} geo optional api geo of control plane
 */
export const setControlPlaneId = (
  controlPlaneId: string,
  controlPlaneName = 'default',
  geo = getApiGeo()
): void => {
  const geos = CONTROL_PLANE_IDS[controlPlaneName];
  CONTROL_PLANE_IDS[controlPlaneName] = { ...geos, [geo]: controlPlaneId };
};

/**
 * Get the control plane ID for the current run
 * @param {string} controlPlaneName control plane name (default: default)
 * @param {Geo} geo optional api geo of control plane
 * @returns {string} control plane id
 */
export const getControlPlaneId = (
  controlPlaneName = 'default',
  geo = getApiGeo()
): string => {
  return CONTROL_PLANE_IDS[controlPlaneName]?.[geo];
};