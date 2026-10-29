import packageJson from '../../package.json';

export const APP_VERSION = packageJson.version;

export const APP_INFO = {
  version: packageJson.version,
  buildDate: new Date().toISOString()
};
