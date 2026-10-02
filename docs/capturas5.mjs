export default async function run(page, ui) {
  const dir = 'docs/img';
  const hechas = [];
  const shot = async (name) => {
    await page.waitForTimeout(700);
    await page.screenshot({ path: `${dir}/${name}.png` });
    hechas.push(name);
  };
  const limpiarSwal = async () => {
    for (const sel of ['.swal2-confirm', '.swal2-cancel', '.swal2-close']) {
      const b = page.locator(sel);
      if (await b.count()) { try { await b.click({ timeout: 800 }); } catch {} }
    }
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
  };

  await page.setViewportSize({ width: 1366, height: 860 });
  await page.evaluate(() => { localStorage.clear(); indexedDB.deleteDatabase('transporte_personal_db'); });
  await page.goto('http://localhost:4200/#/auth/login');
  await page.waitForSelector('input[formcontrolname="usuario"]');
  await page.fill('input[formcontrolname="usuario"]', 'admin.transporte');
  await page.fill('input[formcontrolname="clave"]', 'Transporte2026!');
  await page.click('button[type="submit"]');
  await page.waitForTimeout(2800);

  await page.goto('http://localhost:4200/#/main/administracion');
  await page.waitForTimeout(1800);
  await limpiarSwal();

  try {
    await page.click('button:has-text("Crear")', { timeout: 4000 });
    await page.waitForSelector('.p-dialog:visible', { timeout: 4000 });
    await shot('16_form_usuario');
    await page.keyboard.press('Escape');
    await page.waitForTimeout(400);
    const x = page.locator('.p-dialog:visible .p-dialog-close-button, .p-dialog:visible button:has(.pi-times)').first();
    if (await x.count()) await x.click().catch(() => {});
    await page.waitForTimeout(400);
  } catch (e) { hechas.push('ERR formusr ' + e.message); }

  await limpiarSwal();
  try {
    await page.click('button:has-text("Unidades")', { timeout: 3000 });
    await page.waitForTimeout(900);
    await shot('17_unidades');
    await page.click('button:has-text("Motivos")', { timeout: 3000 });
    await page.waitForTimeout(900);
    await shot('18_motivos');
  } catch (e) { hechas.push('ERR tabs ' + e.message); }

  return { hechas };
}
