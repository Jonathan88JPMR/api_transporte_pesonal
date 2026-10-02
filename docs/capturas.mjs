export default async function run(page, ui) {
  const dir = 'docs/img';
  const hechas = [];
  const shot = async (name) => {
    await page.waitForTimeout(700);
    await page.screenshot({ path: `${dir}/${name}.png` });
    hechas.push(name);
  };
  const login = async (user, pass) => {
    await page.evaluate(() => { localStorage.clear(); indexedDB.deleteDatabase('transporte_personal_db'); });
    await page.goto('http://localhost:4200/#/auth/login');
    await page.waitForSelector('input[formcontrolname="usuario"]');
    await page.fill('input[formcontrolname="usuario"]', user);
    await page.fill('input[formcontrolname="clave"]', pass);
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2800);
  };
  const cerrarDialogo = async () => {
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    const x = page.locator('.p-dialog-header-close, .p-dialog-close-button, .p-dialog [aria-label="Close"]').first();
    if (await x.count()) { try { await x.click({ timeout: 500 }); } catch {} }
    await page.waitForTimeout(300);
  };

  await page.setViewportSize({ width: 1366, height: 860 });
  await shot('01_login');

  // ===== SUPERVISOR =====
  await login('supervisor.transporte', 'Transporte2026!');
  await shot('02_solicitudes');
  try {
    await page.click('button:has-text("Crear")', { timeout: 3000 });
    await page.waitForSelector('p-dialog', { timeout: 3000 });
    await shot('03_crear_solicitud');
    await cerrarDialogo();
  } catch (e) { hechas.push('ERR crear: ' + e.message); }
  try {
    await page.locator('p-table table tbody tr').first().click({ timeout: 3000 });
    await page.waitForSelector('p-dialog', { timeout: 3000 });
    await shot('04_detalle_solicitud');
    await cerrarDialogo();
  } catch (e) { hechas.push('ERR detalle: ' + e.message); }
  try {
    await page.click('button[title="Notificaciones"]', { timeout: 2000 });
    await shot('05_notificaciones');
    await page.keyboard.press('Escape');
    await page.click('body', { position: { x: 10, y: 400 } });
  } catch (e) { hechas.push('ERR notif: ' + e.message); }

  // ===== COORDINADOR =====
  await login('coordinador.transporte', 'Transporte2026!');
  await shot('06_coordinacion');

  // ===== CONDUCTOR =====
  await login('conductor.transporte', 'Transporte2026!');
  await shot('07_mis_servicios');
  try {
    const mapBtn = page.locator('button[title="Ver mapa y paradas"]').first();
    if (await mapBtn.count()) {
      await mapBtn.click();
      await page.waitForTimeout(2000);
      await shot('08_ruta_paradas');
      const x = page.locator('.card .btn-close').last();
      if (await x.count()) await x.click();
    }
  } catch (e) { hechas.push('ERR mapa: ' + e.message); }
  try {
    const paxBtn = page.locator('button[title="Agregar pasajeros de emergencia"]').first();
    if (await paxBtn.count()) {
      await paxBtn.click();
      await page.waitForTimeout(500);
      await shot('09_agregar_pasajeros');
      const x = page.locator('.card .btn-close').last();
      if (await x.count()) await x.click();
    }
  } catch (e) { hechas.push('ERR pax: ' + e.message); }

  // ===== ADMINISTRADOR =====
  await login('admin.transporte', 'Transporte2026!');
  await page.goto('http://localhost:4200/#/main/reportes');
  await page.waitForTimeout(2200);
  await shot('10_reportes');
  try {
    await page.click('button:has-text("Cargar auditoría")', { timeout: 3000 });
    await page.waitForTimeout(1500);
    await shot('11_auditoria');
  } catch (e) { hechas.push('ERR audit: ' + e.message); }
  await page.goto('http://localhost:4200/#/main/administracion');
  await page.waitForTimeout(1500);
  await shot('12_administracion_usuarios');
  try {
    await page.click('button:has-text("Conductores")', { timeout: 2000 });
    await page.waitForTimeout(900);
    await shot('13_administracion_conductores');
    await page.click('button:has-text("Puntos")', { timeout: 2000 });
    await page.waitForTimeout(900);
    await shot('14_administracion_puntos');
  } catch (e) { hechas.push('ERR admin tabs: ' + e.message); }
  try {
    await page.click('button[title="Cambiar clave"]', { timeout: 2000 });
    await shot('15_cambiar_clave');
  } catch (e) { hechas.push('ERR clave: ' + e.message); }

  return { hechas };
}
