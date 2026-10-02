export default async function run(page, ui) {
  const dir = 'docs/img';
  const hechas = [];
  const shot = async (name, clip) => {
    await page.waitForTimeout(700);
    const opt = { path: `${dir}/${name}.png` };
    if (clip) opt.clip = clip;
    await page.screenshot(opt);
    hechas.push(name);
  };
  const menuClip = { x: 0, y: 0, width: 230, height: 620 };
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
    await page.waitForTimeout(400);
    const x = page.locator('.p-dialog:visible .p-dialog-close-button, .p-dialog:visible .p-dialog-header-close, .p-dialog:visible button:has(.pi-times)').first();
    if (await x.count()) { try { await x.click({ timeout: 800 }); } catch {} }
    await page.waitForTimeout(300);
  };
  const cerrarSwal = async (cancel) => {
    const btn = page.locator(cancel ? '.swal2-cancel' : '.swal2-confirm');
    if (await btn.count()) { try { await btn.click({ timeout: 1500 }); } catch {} }
    await page.waitForTimeout(500);
  };
  const pickSelect = async (host, texto) => {
    await host.click();
    await page.waitForTimeout(500);
    const opt = page.locator('.p-select-option:visible, li[role="option"]:visible').filter({ hasText: texto }).first();
    await opt.click();
    await page.waitForTimeout(300);
  };

  await page.setViewportSize({ width: 1366, height: 860 });

  // ===== error de login =====
  try {
    await page.evaluate(() => { localStorage.clear(); indexedDB.deleteDatabase('transporte_personal_db'); });
    await page.goto('http://localhost:4200/#/auth/login');
    await page.waitForSelector('input[formcontrolname="usuario"]');
    await page.fill('input[formcontrolname="usuario"]', 'supervisor.transporte');
    await page.fill('input[formcontrolname="clave"]', 'clave_incorrecta');
    await page.click('button[type="submit"]');
    await page.waitForTimeout(2500);
    await shot('00_login_error');
  } catch (e) { hechas.push('ERR loginerr ' + e.message); }

  // ===== SUPERVISOR =====
  await login('supervisor.transporte', 'Transporte2026!');
  await shot('menu_supervisor', menuClip);
  try {
    await page.locator('input[type="date"]').first().fill('2026-09-30');
    await page.locator('input[type="date"]').first().dispatchEvent('change');
    await page.waitForTimeout(1200);
    await shot('02b_filtro_fecha');
    await page.click('button:has-text("Ver todas")').catch(() => {});
    await page.waitForTimeout(800);
  } catch (e) { hechas.push('ERR filtro ' + e.message); }
  try {
    await page.locator('p-table tbody tr button[title="Editar"]').first().click({ timeout: 3000 });
    await page.waitForSelector('.p-dialog:visible', { timeout: 3000 });
    await shot('03b_editar_solicitud');
    await cerrarDialogo();
  } catch (e) { hechas.push('ERR editar ' + e.message); }
  try {
    await page.locator('p-table tbody tr button[title="Anular"]').first().click({ timeout: 3000 });
    await page.waitForSelector('.swal2-container', { timeout: 3000 });
    await shot('03c_anular_confirm');
    await cerrarSwal(true);
  } catch (e) { hechas.push('ERR anular ' + e.message); }
  // crear solicitud nueva (compatible con T-2) para capturar acoplar
  try {
    await page.click('button:has-text("Crear")');
    await page.waitForSelector('.p-dialog:visible', { timeout: 4000 });
    const dlg = page.locator('.p-dialog:visible');
    await dlg.locator('input[type="date"]').fill('2026-10-02');
    await dlg.locator('input[type="time"]').fill('08:00');
    const selects = dlg.locator('p-select');
    await pickSelect(selects.nth(0), 'Acopio');
    await pickSelect(selects.nth(1), 'Oficina');
    await dlg.locator('p-inputnumber input').fill('4');
    await pickSelect(selects.nth(2), '');
    await dlg.locator('button:has-text("Save")').click();
    await page.waitForTimeout(1500);
    await cerrarSwal(false);
    hechas.push('sol_creada');
  } catch (e) { hechas.push('ERR crear ' + e.message); }
  try {
    await page.locator('p-table table tbody tr').last().click({ timeout: 4000 });
    await page.waitForSelector('.p-dialog:visible', { timeout: 4000 });
    await shot('04b_acoplar');
    await cerrarDialogo();
  } catch (e) { hechas.push('ERR acoplar ' + e.message); }

  // ===== COORDINADOR =====
  await login('coordinador.transporte', 'Transporte2026!');
  await shot('menu_coordinador', menuClip);
  try {
    await page.locator('button[title="Asignar varias unidades"]').first().click({ timeout: 3000 });
    await page.waitForTimeout(800);
    await page.locator('h6:has-text("Distribuir")').scrollIntoViewIfNeeded();
    await shot('06f_asignacion_multiple');
    await page.locator('.card .btn-close').last().click().catch(() => {});
  } catch (e) { hechas.push('ERR multi ' + e.message); }
  try {
    await page.locator('button[title="Editar solicitud"]').first().click({ timeout: 3000 });
    await page.waitForTimeout(700);
    await page.locator('h6:has-text("Editar solicitud")').scrollIntoViewIfNeeded();
    await shot('06g_editar_solicitud');
    await page.locator('.card .btn-close').last().click().catch(() => {});
  } catch (e) { hechas.push('ERR edsol ' + e.message); }
  try {
    await page.locator('button:has-text("Mapa")').first().click({ timeout: 3000 });
    await page.waitForTimeout(2200);
    await page.locator('.card:has(h6:has-text("Ruta T-")), .card:has(.leaflet-container)').last().scrollIntoViewIfNeeded();
    await shot('06h_mapa_traslado');
    await page.locator('.card .btn-close').last().click().catch(() => {});
  } catch (e) { hechas.push('ERR mapatras ' + e.message); }
  try {
    await page.locator('button[title="Separar del traslado"]').first().click({ timeout: 3000 });
    await page.waitForSelector('.swal2-container', { timeout: 3000 });
    await shot('06i_separar_confirm');
    await cerrarSwal(true);
  } catch (e) { hechas.push('ERR sep ' + e.message); }

  // ===== CONDUCTOR (menu) =====
  await login('conductor.transporte', 'Transporte2026!');
  await shot('menu_conductor', menuClip);

  // ===== ADMINISTRADOR =====
  await login('admin.transporte', 'Transporte2026!');
  await shot('menu_admin', menuClip);
  try {
    await page.goto('http://localhost:4200/#/main/administracion');
    await page.waitForTimeout(1500);
    await page.click('button:has-text("Crear")', { timeout: 3000 });
    await page.waitForSelector('.p-dialog:visible', { timeout: 3000 });
    await shot('16_form_usuario');
    await cerrarDialogo();
  } catch (e) { hechas.push('ERR formusr ' + e.message); }
  try {
    await page.click('button:has-text("Unidades")', { timeout: 2000 });
    await page.waitForTimeout(900);
    await shot('17_unidades');
    await page.click('button:has-text("Motivos")', { timeout: 2000 });
    await page.waitForTimeout(900);
    await shot('18_motivos');
  } catch (e) { hechas.push('ERR tabs ' + e.message); }
  try {
    await page.goto('http://localhost:4200/#/main/reportes');
    await page.waitForTimeout(2000);
    await page.locator('p-table').first().scrollIntoViewIfNeeded();
    await shot('10b_reporte_tabla');
  } catch (e) { hechas.push('ERR reptabla ' + e.message); }

  return { hechas };
}
