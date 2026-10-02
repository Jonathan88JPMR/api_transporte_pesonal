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
  const cerrarSwal = async () => {
    const ok = page.locator('.swal2-confirm');
    if (await ok.count()) { try { await ok.click({ timeout: 1500 }); } catch {} }
    await page.waitForTimeout(500);
  };

  await page.setViewportSize({ width: 1366, height: 860 });

  // ===== SUPERVISOR: crear una solicitud adicional =====
  await login('supervisor.transporte', 'Transporte2026!');
  try {
    await page.click('button:has-text("Crear")');
    await page.waitForSelector('.p-dialog:visible', { timeout: 4000 });
    const dlg = page.locator('.p-dialog:visible');
    await dlg.locator('input[type="date"]').fill('2026-10-02');
    await dlg.locator('input[type="time"]').fill('08:00');
    const selects = dlg.locator('p-select');
    // P. partida -> opcion 0
    await selects.nth(0).click(); await page.waitForTimeout(400);
    await page.locator('.p-select-option:visible, li[role="option"]:visible').nth(0).click();
    await page.waitForTimeout(300);
    // P. llegada -> opcion 1
    await selects.nth(1).click(); await page.waitForTimeout(400);
    await page.locator('.p-select-option:visible, li[role="option"]:visible').nth(1).click();
    await page.waitForTimeout(300);
    // cantidad
    await dlg.locator('input[type="number"], input[inputmode="numeric"]').first().fill('5');
    // motivo -> opcion 0
    await selects.nth(2).click(); await page.waitForTimeout(400);
    await page.locator('.p-select-option:visible, li[role="option"]:visible').nth(0).click();
    await page.waitForTimeout(300);
    await dlg.locator('button:has-text("Save"), button:has-text("Guardar")').click();
    await page.waitForTimeout(1500);
    await cerrarSwal();
    hechas.push('solicitud_creada');
  } catch (e) { hechas.push('ERR crearSol ' + e.message); }

  // ===== COORDINADOR: unir las 2 pendientes =====
  await login('coordinador.transporte', 'Transporte2026!');
  try {
    const filas = page.locator('p-table table tbody tr');
    const n = await filas.count();
    hechas.push('filas=' + n);
    // marcar las dos ultimas filas (pendientes)
    await filas.nth(n - 1).locator('.p-checkbox, p-tablecheckbox').first().click();
    await page.waitForTimeout(300);
    await filas.nth(n - 2).locator('.p-checkbox, p-tablecheckbox').first().click();
    await page.waitForTimeout(500);
    // select placa del traslado
    await page.locator('p-select:visible').first().click();
    await page.waitForTimeout(400);
    await page.locator('.p-select-option:visible, li[role="option"]:visible').filter({ hasText: 'TP-001' }).first().click();
    await page.waitForTimeout(300);
    await page.click('button:has-text("Unir")');
    await page.waitForTimeout(1500);
    await cerrarSwal();
    await shot('06e_traslado_unido');
  } catch (e) { hechas.push('ERR unir ' + e.message); }

  // editor de paradas
  try {
    await page.click('button:has-text("Editar paradas")', { timeout: 4000 });
    await page.waitForTimeout(600);
    const editor = page.locator('div.card').filter({ has: page.locator('h6:has-text("Ruta T-")') }).last();
    for (const [idx, sube, baja] of [[0, 12, 0], [1, 0, 12]]) {
      await editor.locator('button:has-text("Agregar parada")').click();
      await page.waitForTimeout(400);
      const row = editor.locator('.row.g-2').nth(idx);
      await row.locator('p-select').click();
      await page.waitForTimeout(500);
      await page.locator('.p-select-option:visible, li[role="option"]:visible').nth(idx).click();
      await page.waitForTimeout(300);
      await row.locator('input[type="number"]').nth(0).fill(String(sube));
      await row.locator('input[type="number"]').nth(1).fill(String(baja));
    }
    await shot('06d_editor_paradas');
    await editor.locator('button:has-text("Guardar ruta")').click();
    await page.waitForTimeout(1200);
    await cerrarSwal();
  } catch (e) { hechas.push('ERR paradas ' + e.message); }

  // ===== ADMIN: auditoria con scroll =====
  await login('admin.transporte', 'Transporte2026!');
  await page.goto('http://localhost:4200/#/main/reportes');
  await page.waitForTimeout(2000);
  try {
    await page.click('button:has-text("Cargar auditoría")', { timeout: 3000 });
    await page.waitForTimeout(1800);
    await page.locator('p-table').last().scrollIntoViewIfNeeded();
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await shot('11_auditoria');
  } catch (e) { hechas.push('ERR audit ' + e.message); }

  return { hechas };
}
