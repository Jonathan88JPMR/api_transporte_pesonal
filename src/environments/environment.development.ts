export const environment = {
  production: false,
  appVersion: '1.0.1', // se reemplaza automáticamente

  updateMode: 'AUTO',      // 'AUTO' | 'MANUAL' | 'DISABLED'
  showUpdateModal: true,   // true | false
  versionControlApi: 'MAESTRA', // 'TRANSPORTE' | 'MAESTRA' (default; override runtime en localStorage)
  baseUrl: 'https://localhost:7026',
  apiMaestra: 'https://apimaestra.agroapps.net:7003'
};
