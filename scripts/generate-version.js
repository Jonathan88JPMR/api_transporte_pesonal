const fs = require('fs');
const pkg = require('../package.json');

const versionInfo = {
  version: pkg.version,
  buildTime: new Date().toISOString()
};

fs.writeFileSync(
  './src/assets/version.json',
  JSON.stringify(versionInfo, null, 2)
);

console.log('✔ version.json generado:', versionInfo.version);
