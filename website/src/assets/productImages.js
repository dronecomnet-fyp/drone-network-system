import moduleStandard from './module_standard.png';
import moduleAux from './module_aux.png';
import systemDrone from './system_drone_img.png';
import heroImg from './hero.png';
import logoImg from './logo.png';

export { heroImg, logoImg, moduleStandard, moduleAux, systemDrone };

/**
 * Returns the matching product image based on model number or product name.
 * @param {string} modelNo 
 * @param {string} name 
 * @returns {string} Image URL/asset
 */
export function getProductImage(modelNo = '', name = '') {
  const m = (modelNo || '').toUpperCase();
  const n = (name || '').toLowerCase();

  // System Drone
  if (m === 'AS5' || n.includes('system drone') || n.includes('aerosync') || n.includes('drone')) {
    if (!n.includes('module')) {
      return systemDrone;
    }
  }

  // Aux Module
  if (m === 'DCM-AUX' || n.includes('aux') || n.includes('sensor')) {
    return moduleAux;
  }

  // Standard Module (default for DCM-STD and general modules)
  return moduleStandard;
}
