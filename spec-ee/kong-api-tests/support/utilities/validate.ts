/**
 * Check if the given string is a valid date
 * @param {string} date target date string
 * @returns {boolean} if valid date - true; else - false
 */
export const isValidDate = (date: string): boolean => {
  return !isNaN(Date.parse(date));
};

/**
 * Check if the given string is a valid URL
 * @param {string} url  target url string
 * @returns {boolean} if valid url - true; else - false
 */
export const isValidUrl = (url: string): boolean => {
  try {
    return Boolean(new URL(url));
  } catch {
    return false;
  }
};
