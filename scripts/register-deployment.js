/**
 * Script: register-deployment.js
 *
 * Registra el deployment actual en la API seleccionada (api_transporte_personal o api_maestros).
 * Se ejecuta automaticamente DESPUES de `ng build` via los scripts de npm.
 *
 * Lee la version desde src/assets/version.json (generado por update-version.js).
 * Lee el nombre de la app desde package.json.
 * Elige la API segun:
 *   1. Variable de entorno DEPLOY_VERSION_API (TRANSPORTE | MAESTRA)
 *   2. Argumento CLI: --api=MAESTRA
 *   3. Lee `versionControlApi` de src/environments/environment.ts
 *   4. Fallback: MAESTRA
 *
 * Uso:
 *   node scripts/register-deployment.js
 *   node scripts/register-deployment.js --api=MAESTRA
 *   node scripts/register-deployment.js --environment=production --notes="Deploy manual"
 *
 * Flags utiles:
 *   --skip        No hace nada (escape rapido en pipelines)
 *   --dry-run     Muestra lo que enviaria sin hacer la peticion
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const https = require('https');
const http = require('http');
const { URL } = require('url');

// ------------------------------------------------------------------
// Argumentos CLI
// ------------------------------------------------------------------
const args = process.argv.slice(2).reduce((acc, a) => {
  const m = a.match(/^--([^=]+)(?:=(.*))?$/);
  if (m) acc[m[1]] = m[2] ?? true;
  return acc;
}, {});

if (args.skip || process.env.DEPLOY_SKIP_REGISTER === '1') {
  console.log('[register-deployment] Saltado (--skip o DEPLOY_SKIP_REGISTER=1)');
  process.exit(0);
}

// ------------------------------------------------------------------
// Determinar API
// ------------------------------------------------------------------
const ENV_FILE = path.resolve('src/environments/environment.ts');

function readVersionControlApiFromEnv() {
  try {
    const content = fs.readFileSync(ENV_FILE, 'utf8');
    const m = content.match(/versionControlApi\s*:\s*'(TRANSPORTE|MAESTRA)'/);
    return m ? m[1] : null;
  } catch {
    return null;
  }
}

function readApiUrlsFromEnv() {
  const content = fs.readFileSync(ENV_FILE, 'utf8');
  const base = content.match(/baseUrl\s*:\s*'([^']+)'/);
  const maestra = content.match(/apiMaestra\s*:\s*'([^']+)'/);
  return {
    baseUrl: base ? base[1] : 'https://apitransportepersonal.agroapps.net:7643',
    apiMaestra: maestra ? maestra[1] : 'https://apimaestra.agroapps.net:7003'
  };
}

const apiSelected = (
  args.api ||
  process.env.DEPLOY_VERSION_API ||
  readVersionControlApiFromEnv() ||
  'MAESTRA'
).toUpperCase();

if (apiSelected !== 'TRANSPORTE' && apiSelected !== 'MAESTRA') {
  console.error(`[register-deployment] API invalida: ${apiSelected}`);
  process.exit(1);
}

const { baseUrl, apiMaestra } = readApiUrlsFromEnv();

const endpoint = apiSelected === 'MAESTRA'
  ? `${apiMaestra}/api/app-deployments/register`
  : `${baseUrl}/api/app-deployments`;

// ------------------------------------------------------------------
// Leer datos del deploy
// ------------------------------------------------------------------
const pkg = JSON.parse(fs.readFileSync(path.resolve('package.json'), 'utf8'));
const versionJsonPath = path.resolve('src/assets/version.json');

if (!fs.existsSync(versionJsonPath)) {
  console.error(`[register-deployment] ERROR: No se encontro ${versionJsonPath}`);
  console.error('  Corre primero: node scripts/update-version.js');
  process.exit(1);
}
const versionJson = JSON.parse(fs.readFileSync(versionJsonPath, 'utf8'));

const payload = {
  appName: pkg.name,
  environment: args.environment || process.env.DEPLOY_ENV || 'production',
  version: versionJson.version,
  build: versionJson.build || 0,
  buildTime: versionJson.buildTime,
  deployedAt: new Date().toISOString(),
  deployedBy: os.userInfo().username,
  serverName: os.hostname(),
  notes: args.notes || 'Registro automatico desde ng build',
  isActive: true
};

// ------------------------------------------------------------------
// Resumen y dry-run
// ------------------------------------------------------------------
console.log('');
console.log('========== REGISTRO DE DEPLOYMENT ==========');
console.log(`  API seleccionada: ${apiSelected}`);
console.log(`  Endpoint:         ${endpoint}`);
console.log(`  AppName:          ${payload.appName}`);
console.log(`  Version:          ${payload.version} (build ${payload.build})`);
console.log(`  Environment:      ${payload.environment}`);
console.log(`  Deployed by:      ${payload.deployedBy}@${payload.serverName}`);
console.log('============================================');

if (args['dry-run']) {
  console.log('[register-deployment] DRY-RUN activo. Payload que se enviaria:');
  console.log(JSON.stringify(payload, null, 2));
  process.exit(0);
}

// ------------------------------------------------------------------
// POST al endpoint (soporta http y https, ignora cert self-signed en dev)
// ------------------------------------------------------------------
const urlObj = new URL(endpoint);
const body = JSON.stringify(payload);
const lib = urlObj.protocol === 'https:' ? https : http;

const req = lib.request(
  {
    method: 'POST',
    hostname: urlObj.hostname,
    port: urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
    path: urlObj.pathname + urlObj.search,
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body)
    },
    rejectUnauthorized: false,
    timeout: 20000
  },
  (res) => {
    let chunks = '';
    res.on('data', (d) => (chunks += d));
    res.on('end', () => {
      if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
        console.log(`[register-deployment] OK (${res.statusCode})`);
        if (chunks) {
          try {
            const parsed = JSON.parse(chunks);
            console.log('  Respuesta:', JSON.stringify(parsed, null, 2));
          } catch {
            console.log('  Respuesta:', chunks);
          }
        }
        process.exit(0);
      } else {
        console.error(`[register-deployment] FALLO HTTP ${res.statusCode}`);
        if (chunks) console.error('  Cuerpo:', chunks);
        // No bloqueamos el build: salimos con 0 para no romper CI pero avisamos.
        // Cambia a process.exit(1) si quieres que falle el build.
        process.exit(0);
      }
    });
  }
);

req.on('error', (err) => {
  console.error('[register-deployment] ERROR de red:', err.message);
  // No bloqueamos el build (los archivos ya fueron compilados).
  process.exit(0);
});

req.on('timeout', () => {
  console.error('[register-deployment] TIMEOUT (20s)');
  req.destroy();
  process.exit(0);
});

req.write(body);
req.end();
