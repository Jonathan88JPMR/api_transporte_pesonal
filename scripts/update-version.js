/**
 * Script: update-version.js
 * Función: Incrementa automáticamente el BUILD number en cada compilación.
 * La versión semántica (MAJOR.MINOR.PATCH) debe ser modificada manualmente por el desarrollador.
 * 
 * Estructura de versión:
 * {
 *   "version": "1.4.2",   // MAJOR.MINOR.PATCH (manual)
 *   "build": 187,         // Build automático (incrementa en cada build)
 *   "buildTime": "2026-06-17T20:00:00.000Z"
 * }
 * 
 * Cuándo cambiar cada parte (manual):
 * - MAJOR: Cambios grandes, breaking changes, refactorización mayor
 * - MINOR: Nuevas funcionalidades, módulos nuevos
 * - PATCH: Bugfixes, hotfixes, correcciones menores
 * 
 * Uso manual de versión:
 * npm run version:patch  -> Incrementa PATCH (1.4.2 -> 1.4.3)
 * npm run version:minor  -> Incrementa MINOR (1.4.2 -> 1.5.0)
 * npm run version:major  -> Incrementa MAJOR (1.4.2 -> 2.0.0)
 */

const fs = require('fs');
const path = require('path');

const pkgPath = path.resolve('package.json');
const envPaths = [
  path.resolve('src/environments/environment.ts'),
  path.resolve('src/environments/environment.development.ts')
];
const versionJsonPath = path.resolve('src/assets/version.json');

// 📦 Leer versión actual desde version.json (fuente de verdad)
let versionData;
try {
  versionData = JSON.parse(fs.readFileSync(versionJsonPath, 'utf8'));
} catch (e) {
  // Si no existe, crear estructura inicial
  versionData = {
    version: '1.0.0',
    build: 0,
    buildTime: new Date().toISOString()
  };
}

// 🔄 Incrementar SOLO el build number automáticamente
const newBuild = (versionData.build || 0) + 1;
const currentVersion = versionData.version || '1.0.0';

// 📝 Preparar nueva estructura
const newVersionData = {
  version: currentVersion,    // MAJOR.MINOR.PATCH (el dev lo controla manualmente)
  build: newBuild,            // Número de build (automático)
  buildTime: new Date().toISOString()
};

// 💾 Guardar version.json
fs.writeFileSync(versionJsonPath, JSON.stringify(newVersionData, null, 2));

// 📦 Sincronizar con package.json (solo metadata, sin alterar versión semántica)
const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
pkg.version = currentVersion;
fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2));

// 🔁 Actualizar environments con formato: version (build)
for (const envPath of envPaths) {
  if (!fs.existsSync(envPath)) continue;

  let content = fs.readFileSync(envPath, 'utf8');

  // Actualizar comentario
  content = content.replace(
    /(\/\/\s*appVersion:\s*')[^']*('.*se reemplaza automáticamente)/,
    `$1${currentVersion}$2`
  );

  // Actualizar línea real
  content = content.replace(
    /^\s*appVersion:\s*'[^']*',/m,
    `  appVersion: '${currentVersion}',`
  );

  fs.writeFileSync(envPath, content);
}

// 📊 Mostrar resumen
console.log('');
console.log('╔════════════════════════════════════════════════════════╗');
console.log('║           ✅ VERSIÓN ACTUALIZADA                      ║');
console.log('╠════════════════════════════════════════════════════════╣');
console.log(`║  📌 Versión semántica: ${currentVersion.padEnd(27)} ║`);
console.log(`║  🔨 Build número:      ${String(newBuild).padEnd(27)} ║`);
console.log(`║  🕐 Build time:         ${newVersionData.buildTime.slice(0, 19).padEnd(27)} ║`);
console.log('╚════════════════════════════════════════════════════════╝');
console.log('');
console.log('💡 Para cambiar MAJOR/MINOR/PATCH manualmente:');
console.log('   npm run version:patch  (bugfixes)');
console.log('   npm run version:minor  (nuevas funcionalidades)');
console.log('   npm run version:major  (cambios grandes)');
console.log('');

// Exportar para uso en otros scripts si es necesario
module.exports = { version: currentVersion, build: newBuild };
