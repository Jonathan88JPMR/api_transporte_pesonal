/**
 * Script: version-major.js
 * Incrementa MAJOR (cambios grandes): 1.4.2 -> 2.0.0
 * Usar cuando hay breaking changes, refactorización mayor, o cambios de arquitectura
 */

const fs = require('fs');
const path = require('path');

const versionJsonPath = path.resolve('src/assets/version.json');
const pkgPath = path.resolve('package.json');
const envPaths = [
  path.resolve('src/environments/environment.ts'),
  path.resolve('src/environments/environment.development.ts')
];

// Leer versión actual
let versionData;
try {
  versionData = JSON.parse(fs.readFileSync(versionJsonPath, 'utf8'));
} catch (e) {
  versionData = { version: '1.0.0', build: 0 };
}

// Incrementar MAJOR, resetear MINOR y PATCH
const [major, minor, patch] = versionData.version.split('.').map(Number);
const newVersion = `${major + 1}.0.0`;

// Guardar con build reseteado a 0
versionData.version = newVersion;
versionData.build = 0;
fs.writeFileSync(versionJsonPath, JSON.stringify(versionData, null, 2));

// Sincronizar package.json
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
pkg.version = newVersion;
fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2));

// Actualizar environments
for (const envPath of envPaths) {
  if (!fs.existsSync(envPath)) continue;
  let content = fs.readFileSync(envPath, 'utf8');
  content = content.replace(/(\/\/\s*appVersion:\s*')[^']*('.*se reemplaza automáticamente)/, `$1${newVersion}$2`);
  content = content.replace(/^\s*appVersion:\s*'[^']*',/m, `  appVersion: '${newVersion}',`);
  fs.writeFileSync(envPath, content);
}

console.log(`✅ MAJOR incrementado: ${versionData.version} -> ${newVersion}`);
console.log('   🚀 Cambio grande / Breaking change / Nueva arquitectura');
