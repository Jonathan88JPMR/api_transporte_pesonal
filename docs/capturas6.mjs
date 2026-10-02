export default async function run(page, ui) {
  const dir = 'docs/img';
  const hechas = [];
  const shot = async (name) => {
    await page.waitForTimeout(700);
    await page.screenshot({ path: `${dir}/${name}.png` });
    hechas.push(name);
  };

  await page.setViewportSize({ width: 1366, height: 860 });
  await page.evaluate(() => { localStorage.clear(); indexedDB.deleteDatabase('transporte_personal_db'); });
  await page.goto('http://localhost:4200/#/auth/login');
  await page.waitForSelector('input[formcontrolname="usuario"]');
  await page.fill('input[formcontrolname="usuario"]', 'admin.transporte');
  await page.fill('input[formcontrolname="clave"]', 'Transporte2026!');
  await page.click('button[type="submit"]');
  await page.waitForTimeout(2800);

  // listado solicitudes fresco (con tags T-2)
  await page.goto('http://localhost:4200/#/main/solicitudes');
  await page.waitForTimeout(1500);
  await shot('02_solicitudes');

  // coordinacion con traslado activo
  await page.goto('http://localhost:4200/#/main/coordinador');
  await page.waitForTimeout(1500);
  await shot('06_coordinacion');

  // notificaciones (admin tiene varias)
  try {
    await page.click('button[title="Notificaciones"]', { timeout: 3000 });
    await shot('05_notificaciones');
    await page.keyboard.press('Escape');
    await page.click('body', { position: { x: 10, y: 400 } });
  } catch (e) { hechas.push('ERR notif ' + e.message); }

  // reportes: tabla de solicitudes sin modal
  await page.goto('http://localhost:4200/#/main/reportes');
  await page.waitForTimeout(2200);
  try {
    await page.locator('p-table').first().scrollIntoViewIfNeeded();
    await shot('10b_reporte_tabla');
  } catch (e) { hechas.push('ERR reptabla ' + e.message); }

  return { hechas };
}
