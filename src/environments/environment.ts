export const environment = {
  production: false,
  appVersion: '3.0.3', // se reemplaza automáticamente

  updateMode: 'AUTO',      // 'AUTO' | 'MANUAL' | 'DISABLED'
  showUpdateModal: true,   // true | false
  versionControlApi: 'MAESTRA', // 'TRANSPORTE' | 'MAESTRA' (default; override runtime en localStorage)
  // baseUrl: 'https://localhost:7026'
  baseUrl: 'https://apitransportepersonal.agroapps.net:7643',
  apiMaestra: 'https://apimaestra.agroapps.net:7003'
};
