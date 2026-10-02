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
  const dialogoVisible = () => page.locator('.p-dialog-mask:visible, .p-dialog:visible').first();
  const cerrarDialogo = async () => {
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
    if (await dialogoVisible().count()) {
      const x = page.locator('.p-dialog:visible .p-dialog-close-button, .p-dialog:visible .p-dialog-header-close, .p-dialog:visible button:has(.pi-times)').first();
      if (await x.count()) { try { await x.click({ timeout: 1000 }); } catch {} }
      await page.waitForTimeout(400);
    }
    if (await dialogoVisible().count()) {
      await page.locator('p-dialog:visible button:has-text("Cancel")').first().click().catch(() => {});
      await page.waitForTimeout(400);
    }
  };
  const cerrarSwal = async () => {
    const ok = page.locator('.swal2-confirm');
    if (await ok.count()) { try { await ok.click({ timeout: 800 }); } catch {} }
    await page.waitForTimeout(400);
  };

  await page.setViewportSize({ width: 1366, height: 860 });

  // ===== SUPERVISOR =====
  await login('supervisor.transporte', 'Transporte2026!');
  try {
    await page.click('button:has-text("Crear")');
    await page.waitForSelector('.p-dialog:visible', { timeout: 4000 });
    await shot('03_crear_solicitud');
  } catch (e) { hechas.push('ERR crear ' + e.message); }
  await cerrarDialogo();
  try {
    await page.locator('p-table table tbody tr').first().click({ timeout: 4000 });
    await page.waitForSelector('.p-dialog:visible', { timeout: 4000 });
    await shot('04_detalle_solicitud');
  } catch (e) { hechas.push('ERR detalle ' + e.message); }
  await cerrarDialogo();
  try {
    await page.click('button[title="Notificaciones"]', { timeout: 3000 });
    await shot('05_notificaciones');
    await page.keyboard.press('Escape');
    await page.click('body', { position: { x: 10, y: 400 } });
  } catch (e) { hechas.push('ERR notif ' + e.message); }

  // ===== COORDINADOR: asignar TP-002 =====
  await login('coordinador.transporte', 'Transporte2026!');
  try {
    const fila = page.locator('p-table table tbody tr').first();
    await fila.locator('p-select').click();
    await page.waitForTimeout(600);
    await page.locator('.p-select-option:visible, li[role="option"]:visible').filter({ hasText: 'TP-002' }).first().click();
    await page.waitForTimeout(400);
    await shot('06b_asignacion_placa');
    await fila.locator('button[title="Asignar unidad"]').click();
    await page.waitForTimeout(1500);
    await cerrarSwal();
    await shot('06c_traslado_activo');
  } catch (e) { hechas.push('ERR asignar ' + e.message); }

  // editor de paradas
  try {
    await page.click('button:has-text("Editar paradas")', { timeout: 3000 });
    await page.waitForTimeout(600);
    for (const [idx, sube, baja] of [[0, 3, 0], [1, 0, 3]]) {
      await page.click('button:has-text("Agregar parada")');
      await page.waitForTimeout(400);
      const row = page.locator('h6:has-text("Ruta T-")').locator('..').locator('..').locator('.row.g-2').nth(idx);
      await row.locator('p-select').click();
      await page.waitForTimeout(500);
      await page.locator('.p-select-option:visible, li[role="option"]:visible').nth(idx).click();
      await page.waitForTimeout(300);
      await row.locator('input[type="number"]').nth(0).fill(String(sube));
      await row.locator('input[type="number"]').nth(1).fill(String(baja));
    }
    await shot('06d_editor_paradas');
    await page.click('button:has-text("Guardar ruta")');
    await page.waitForTimeout(1200);
    await cerrarSwal();
  } catch (e) { hechas.push('ERR paradas ' + e.message); }

  // ===== CONDUCTOR =====
  await login('conductor.transporte', 'Transporte2026!');
  await shot('07_mis_servicios');
  try {
    const mapBtn = page.locator('button[title="Ver mapa y paradas"]').first();
    if (await mapBtn.count()) {
      await mapBtn.click();
      await page.waitForTimeout(2200);
      await shot('08_ruta_paradas');
      await page.locator('.card .btn-close').last().click();
      await page.waitForTimeout(300);
    } else { hechas.push('INFO sin boton mapa'); }
  } catch (e) { hechas.push('ERR mapa ' + e.message); }
  try {
    const paxBtn = page.locator('button[title="Agregar pasajeros de emergencia"]').first();
    if (await paxBtn.count()) {
      await paxBtn.click();
      await page.waitForTimeout(500);
      await shot('09_agregar_pasajeros');
      await page.locator('.card .btn-close').last().click();
    } else { hechas.push('INFO sin boton pax'); }
  } catch (e) { hechas.push('ERR pax ' + e.message); }

  return { hechas };
}
