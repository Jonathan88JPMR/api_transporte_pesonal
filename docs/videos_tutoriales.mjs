// Graba video-tutoriales por rol del sistema Transporte de Personal.
// Uso: node docs/videos_tutoriales.mjs [supervisor|coordinador|conductor|administrador|all]
// Requiere: ng serve corriendo en http://localhost:4200 y `npm i -D playwright` + `npx playwright install chromium`
import { chromium } from 'playwright';
import fs from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const BASE = 'http://localhost:4200';
const OUT = 'docs/videos';
const RAW = path.join(OUT, 'raw');
const VP = { width: 1366, height: 768 };
const USERS = {
  supervisor:    ['supervisor.transporte', 'Transporte2026!'],
  coordinador:   ['coordinador.transporte', 'Transporte2026!'],
  conductor:     ['conductor.transporte',   'Transporte2026!'],
  administrador: ['admin.transporte',       'Transporte2026!'],
};

fs.mkdirSync(RAW, { recursive: true });
const log = (...a) => console.log('[video]', ...a);

// ---------- inyeccion de UI del tutorial (caption + cursor + titulo) ----------
async function ensureUi(page) {
  await page.evaluate(() => {
    if (document.getElementById('tut-ui')) return;
    const css = document.createElement('style');
    css.id = 'tut-css';
    css.textContent = `
      #tut-cap{position:fixed;left:50%;bottom:18px;transform:translateX(-50%);z-index:999999;
        background:rgba(15,23,42,.92);color:#fff;padding:10px 22px;border-radius:10px;
        font:600 15px/1.3 system-ui,Segoe UI,sans-serif;box-shadow:0 4px 20px rgba(0,0,0,.35);
        max-width:80%;text-align:center;pointer-events:none;opacity:0;transition:opacity .4s}
      #tut-cap.show{opacity:1}
      #tut-cap b{color:#7dd3fc}
      #tut-cur{position:fixed;z-index:999998;width:22px;height:22px;border-radius:50%;
        background:rgba(14,165,233,.85);border:2px solid #fff;box-shadow:0 0 0 3px rgba(14,165,233,.4);
        pointer-events:none;transition:left .55s cubic-bezier(.4,0,.2,1),top .55s cubic-bezier(.4,0,.2,1);
        left:-50px;top:-50px;transform:translate(-50%,-50%)}
      #tut-rip{position:fixed;z-index:999997;width:10px;height:10px;border-radius:50%;
        border:3px solid rgba(14,165,233,.9);pointer-events:none;opacity:0;
        transform:translate(-50%,-50%)}
      #tut-title{position:fixed;inset:0;z-index:1000000;background:linear-gradient(135deg,#0f172a,#1e3a8a);
        display:flex;flex-direction:column;align-items:center;justify-content:center;color:#fff;
        font:600 20px/1.4 system-ui,Segoe UI,sans-serif;opacity:0;transition:opacity .5s;pointer-events:none}
      #tut-title.show{opacity:1}
      #tut-title h1{font-size:40px;margin:0 0 8px}
      #tut-title p{color:#cbd5e1;margin:4px 0;font-weight:400}`;
    document.head.appendChild(css);
    const wrap = document.createElement('div'); wrap.id = 'tut-ui';
    wrap.innerHTML = '<div id="tut-cap"></div><div id="tut-cur"></div><div id="tut-rip"></div><div id="tut-title"></div>';
    document.body.appendChild(wrap);
  });
}

async function titulo(page, tit, sub) {
  await ensureUi(page);
  await page.evaluate(([t, s]) => {
    const el = document.getElementById('tut-title');
    el.innerHTML = `<h1>${t}</h1><p>${s}</p>`;
    el.classList.add('show');
  }, [tit, sub]);
  await page.waitForTimeout(2600);
  await page.evaluate(() => document.getElementById('tut-title').classList.remove('show'));
  await page.waitForTimeout(500);
}

async function fin(page, texto) {
  await titulo(page, 'Fin del tutorial', texto || '');
}

async function paso(page, texto, ms = 1600) {
  await ensureUi(page);
  await page.evaluate(t => {
    const c = document.getElementById('tut-cap');
    c.innerHTML = t;
    c.classList.add('show');
  }, texto);
  await page.waitForTimeout(ms);
}

async function cursorA(page, loc) {
  const el = loc.first();
  const box = await el.boundingBox().catch(() => null);
  if (!box) return;
  await page.evaluate(([x, y]) => {
    const c = document.getElementById('tut-cur');
    c.style.left = x + 'px'; c.style.top = y + 'px';
  }, [box.x + box.width / 2, box.y + box.height / 2]);
  await page.waitForTimeout(650);
}

async function ripple(page, loc) {
  const box = await loc.first().boundingBox().catch(() => null);
  if (!box) return;
  await page.evaluate(([x, y]) => {
    const r = document.getElementById('tut-rip');
    r.style.left = x + 'px'; r.style.top = y + 'px';
    r.style.transition = 'none'; r.style.width = '10px'; r.style.height = '10px'; r.style.opacity = '1';
    requestAnimationFrame(() => {
      r.style.transition = 'all .5s ease-out';
      r.style.width = '46px'; r.style.height = '46px'; r.style.opacity = '0';
    });
  }, [box.x + box.width / 2, box.y + box.height / 2]);
  await page.waitForTimeout(320);
}

async function clic(page, loc, desc) {
  if (desc) await paso(page, desc);
  await cursorA(page, loc);
  await ripple(page, loc);
  await loc.first().click({ timeout: 5000 });
  await page.waitForTimeout(900);
}

async function escribir(page, loc, texto, desc) {
  if (desc) await paso(page, desc);
  await cursorA(page, loc);
  await loc.first().fill('');
  await loc.first().pressSequentially(texto, { delay: 55 });
  await page.waitForTimeout(500);
}

async function pickSelect(page, host, texto, desc) {
  if (desc) await paso(page, desc);
  await cursorA(page, host);
  await host.first().click();
  await page.waitForTimeout(600);
  const opt = texto
    ? page.locator('.p-select-option:visible, li[role="option"]:visible').filter({ hasText: texto }).first()
    : page.locator('.p-select-option:visible, li[role="option"]:visible').first();
  await cursorA(page, opt);
  await opt.click();
  await page.waitForTimeout(500);
}

async function login(page, user, pass, desc) {
  await page.goto(BASE + '/#/auth/login');
  await ensureUi(page);
  await page.evaluate(() => { localStorage.clear(); indexedDB.deleteDatabase('transporte_personal_db'); });
  await page.goto(BASE + '/#/auth/login');
  await page.waitForSelector('input[formcontrolname="usuario"]');
  await ensureUi(page);
  await paso(page, desc || 'Ingresar usuario y clave, luego pulsar <b>Ingresar</b>');
  await escribir(page, page.locator('input[formcontrolname="usuario"]'), user, 'Escribir el <b>usuario</b>');
  await escribir(page, page.locator('input[formcontrolname="clave"]'), pass, 'Escribir la <b>clave</b>');
  await clic(page, page.locator('button[type="submit"]'), 'Pulsar <b>Ingresar</b>');
  await page.waitForTimeout(3000);
  await ensureUi(page);
}

const dialogoVisible = (page) => page.locator('.p-dialog-mask:visible, .p-dialog:visible').first();
async function cerrarDialogo(page) {
  await page.keyboard.press('Escape'); await page.waitForTimeout(400);
  if (await dialogoVisible(page).count()) {
    const x = page.locator('.p-dialog:visible .p-dialog-close-button, .p-dialog:visible .p-dialog-header-close, .p-dialog:visible button:has(.pi-times)').first();
    if (await x.count()) { try { await x.click({ timeout: 1000 }); } catch {} }
    await page.waitForTimeout(400);
  }
  if (await dialogoVisible(page).count()) {
    await page.locator('p-dialog:visible button:has-text("Cancel")').first().click().catch(() => {});
    await page.waitForTimeout(400);
  }
}
async function cerrarSwal(page, cancel = false) {
  const b = page.locator(cancel ? '.swal2-cancel' : '.swal2-confirm');
  if (await b.count()) { try { await b.click({ timeout: 1500 }); } catch {} }
  await page.waitForTimeout(600);
}

// ---------- grabacion ----------
async function grabar(nombre, browser, fn) {
  const ctx = await browser.newContext({ viewport: VP, recordVideo: { dir: RAW, size: VP } });
  const page = await ctx.newPage();
  page.setDefaultTimeout(8000);
  try {
    await fn(page);
  } catch (e) {
    log(`!! ${nombre}:`, e.message.split('\n')[0]);
  }
  await page.waitForTimeout(600);
  const vpath = await page.video().path();
  await ctx.close();
  const webm = path.join(OUT, `tutorial_${nombre}.webm`);
  fs.renameSync(vpath, webm);
  // limpiar restos del directorio raw
  for (const f of fs.readdirSync(RAW)) { try { fs.unlinkSync(path.join(RAW, f)); } catch {} }
  try {
    execSync(`ffmpeg -y -loglevel error -i "${webm}" -c:v libx264 -pix_fmt yuv420p -crf 23 "${webm.replace('.webm', '.mp4')}"`);
    fs.unlinkSync(webm);
    log(`OK ${path.basename(webm.replace('.webm', '.mp4'))}`);
  } catch (e) {
    log(`OK ${path.basename(webm)} (sin conversion mp4: ${e.message.split('\n')[0]})`);
  }
}

// ---------- videos por rol ----------
async function videoSupervisor(page) {
  await titulo(page, 'Transporte de Personal', 'Tutorial - Rol: SUPERVISOR');
  await login(page, ...USERS.supervisor, 'El <b>Supervisor</b> ingresa con su usuario y clave');
  await paso(page, 'Pantalla principal: lista de <b>Solicitudes</b> del día con su estado', 2500);

  // crear solicitud
  await clic(page, page.locator('button:has-text("Crear")'), 'Pulsar <b>Crear</b> para registrar una solicitud');
  await page.waitForSelector('.p-dialog:visible', { timeout: 5000 });
  const dlg = page.locator('.p-dialog:visible');
  await paso(page, 'Completar el formulario: puntos, cantidad, motivo y prioridad', 2200);
  await cursorA(page, dlg.locator('input[disabled]').first());
  await paso(page, 'El <b>nombre</b>, fecha y hora se completan automáticamente', 2200);
  await pickSelect(page, dlg.locator('p-select[formcontrolname="puntoPartida"]'), '', 'Elegir el <b>punto de partida</b>');
  await pickSelect(page, dlg.locator('p-select[formcontrolname="puntoLlegada"]'), '', 'Elegir el <b>punto de llegada</b>');
  await escribir(page, dlg.locator('p-inputnumber[formcontrolname="cantidad"] input'), '3', 'Indicar la <b>cantidad</b> de personas');
  await pickSelect(page, dlg.locator('p-select[formcontrolname="motivo"]'), '', 'Elegir el <b>motivo</b> del traslado');
  await escribir(page, dlg.locator('textarea[formcontrolname="observacion"]'), 'Traslado de prueba', 'La <b>observación</b> es opcional');
  await clic(page, dlg.locator('select[formcontrolname="prioridad"]'), 'Elegir la <b>prioridad</b>: Normal, Alta o Emergencia');
  await dlg.locator('select[formcontrolname="prioridad"]').selectOption('ALTA').catch(() => {});
  await page.waitForTimeout(700);
  await clic(page, dlg.locator('#esEmergencia'), 'Marcar <b>Es emergencia médica</b> si aplica');
  await dlg.locator('#esEmergencia').click().catch(() => {}); // desmarcar para el demo
  await page.waitForTimeout(500);
  await clic(page, dlg.locator('button:has-text("Save"), button:has-text("Guardar")'), 'Pulsar <b>Guardar</b>');
  await page.waitForTimeout(1500);
  await cerrarSwal(page);
  await paso(page, 'La solicitud queda en estado <b>PENDIENTE</b> a la espera de asignación', 2500);

  // detalle
  try {
    await clic(page, page.locator('p-table table tbody tr').first(), 'Clic en una fila para ver el <b>detalle</b> de la solicitud');
    await page.waitForSelector('.p-dialog:visible', { timeout: 4000 });
    await paso(page, 'El detalle muestra datos, estado y opción de <b>acoplar</b> a un traslado compatible', 2600);
    await cerrarDialogo(page);
  } catch (e) { log('sup detalle', e.message.split('\n')[0]); }

  // filtro fecha / ver todas
  try {
    await clic(page, page.locator('button:has-text("Ver todas"), button:has-text("Todas")'), 'Con <b>Todas</b> se ven solicitudes de cualquier fecha');
    await page.waitForTimeout(1200);
  } catch {}

  // notificaciones
  try {
    await clic(page, page.locator('button[title="Notificaciones"]'), 'La campana muestra las <b>notificaciones</b> del usuario');
    await page.waitForTimeout(1500);
    await page.keyboard.press('Escape');
    await page.click('body', { position: { x: 10, y: 400 } }).catch(() => {});
  } catch {}

  await fin(page, 'Rol Supervisor: crear, editar, anular y hacer seguimiento de solicitudes');
}

async function videoCoordinador(page) {
  await titulo(page, 'Transporte de Personal', 'Tutorial - Rol: COORDINADOR');
  await login(page, ...USERS.coordinador, 'El <b>Coordinador</b> ingresa con su usuario y clave');
  await paso(page, 'Bandeja de <b>Coordinación</b>: solicitudes pendientes del día', 2600);

  // asignar unidad a la primera pendiente
  try {
    const fila = page.locator('p-table table tbody tr').first();
    await pickSelect(page, fila.locator('p-select'), 'TP-002', 'En cada solicitud elegir la <b>unidad</b> (placa) disponible');
    await clic(page, fila.locator('button:has-text("Asignar")'), 'Pulsar <b>Asignar</b> para crear el traslado');
    await page.waitForTimeout(1500);
    await cerrarSwal(page);
    await paso(page, 'Se creó el <b>traslado T-#</b> y la solicitud pasa a ASIGNADO', 2600);
  } catch (e) { log('coo asignar', e.message.split('\n')[0]); }

  // asignacion automatica
  try {
    const auto = page.locator('p-table tbody tr button[ptooltip*="automática" i], p-table tbody tr button:has(i.pi-bolt)').first();
    if (await auto.count()) {
      await cursorA(page, auto);
      await paso(page, 'Con <b>Asignación automática</b> el sistema elige la primera unidad con capacidad', 2600);
    }
  } catch {}

  // editor de paradas
  try {
    await clic(page, page.locator('button:has-text("Editar paradas")').first(), 'Con <b>Editar paradas</b> se define la ruta del traslado');
    await page.waitForTimeout(800);
    const editor = page.locator('div.card').filter({ has: page.locator('h6:has-text("Ruta T-")') }).last();
    const sug = page.locator('button:has-text("Ruta sugerida"), button:has-text("sugerida")').first();
    if (await sug.count()) {
      await clic(page, sug, 'Se puede usar la <b>ruta sugerida</b> según origen/destino de las solicitudes');
      await page.waitForTimeout(1200);
      await cerrarSwal(page);
    }
    const guardar = page.locator('button:has-text("Guardar ruta")').first();
    if (await guardar.count()) { await clic(page, guardar, 'Guardar la ruta de paradas'); await cerrarSwal(page); }
    await page.locator('.card .btn-close').last().click().catch(() => {});
  } catch (e) { log('coo paradas', e.message.split('\n')[0]); }

  // progreso
  try {
    const prog = page.locator('button:has-text("Progreso")').first();
    if (await prog.count()) {
      await clic(page, prog, 'La vista <b>Progreso</b> muestra el avance del traslado en tiempo real');
      await page.waitForTimeout(1800);
      await page.locator('.card .btn-close, .p-dialog:visible .p-dialog-close-button').last().click().catch(() => {});
      await page.keyboard.press('Escape');
    }
  } catch (e) { log('coo progreso', e.message.split('\n')[0]); }

  // pestañas
  try {
    await clic(page, page.locator('button:has-text("Todas")'), 'El filtro <b>Todas</b> muestra solicitudes de todas las fechas');
    await page.waitForTimeout(1200);
    for (const tab of ['Realizadas', 'Anuladas']) {
      const t = page.locator(`button:has-text("${tab}")`).first();
      if (await t.count()) { await clic(page, t, `Pestaña <b>${tab}</b>: histórico de solicitudes`); await page.waitForTimeout(900); }
    }
    await clic(page, page.locator('button:has-text("Activas")'), 'Volver a <b>Activas</b>');
  } catch {}

  // reportes
  await page.goto(BASE + '/#/main/reportes');
  await page.waitForTimeout(2200); await ensureUi(page);
  await paso(page, '<b>Reportes</b>: filtros por fecha/estado y exportación a Excel o CSV', 2600);

  // dashboard
  await page.goto(BASE + '/#/main/dashboard');
  await page.waitForTimeout(2500); await ensureUi(page);
  await paso(page, '<b>Dashboard</b>: indicadores y gráficos del servicio', 2600);
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(1800);

  await fin(page, 'Rol Coordinador: asignar unidades, rutas, seguimiento, reportes y dashboard');
}

async function videoConductor(page) {
  await titulo(page, 'Transporte de Personal', 'Tutorial - Rol: CONDUCTOR');
  await login(page, ...USERS.conductor, 'El <b>Conductor</b> ingresa con su usuario y clave');
  await paso(page, '<b>Mis servicios</b>: traslados asignados a la unidad del conductor', 2800);

  try {
    await clic(page, page.locator('button:has-text("Todas"), button:has-text("Ver todas")').first(), 'Filtrar por fecha o ver <b>todas</b> las programadas');
    await page.waitForTimeout(1200);
    await clic(page, page.locator('button:has-text("Hoy")').first(), 'Volver a <b>Hoy</b>');
  } catch {}

  // checklist de paradas
  try {
    const paradas = page.locator('button:has-text("Paradas"), [title*="parada" i]').first();
    if (await paradas.count()) {
      await clic(page, paradas, 'Abrir el <b>checklist de paradas</b> del servicio');
      await page.waitForTimeout(1500);
      await paso(page, 'En cada parada se marca la llegada y se registran pasajeros que suben/bajan', 2800);
      await page.locator('.card .btn-close, .p-dialog:visible .p-dialog-close-button').last().click().catch(() => {});
      await page.keyboard.press('Escape');
    }
  } catch (e) { log('con paradas', e.message.split('\n')[0]); }

  // pasajeros emergencia
  try {
    const pax = page.locator('button[title="Agregar pasajeros de emergencia"]').first();
    if (await pax.count()) {
      await clic(page, pax, 'Se pueden <b>agregar pasajeros de emergencia</b> si hay capacidad');
      await page.waitForTimeout(1200);
      await page.locator('.card .btn-close').last().click().catch(() => {});
    }
  } catch (e) { log('con pax', e.message.split('\n')[0]); }

  await paso(page, 'Con un servicio EN RUTA la app reporta el <b>GPS cada 30 segundos</b>', 2600);
  await fin(page, 'Rol Conductor: ver servicios, checklist de paradas y registro de pasajeros');
}

async function videoAdministrador(page) {
  await titulo(page, 'Transporte de Personal', 'Tutorial - Rol: ADMINISTRADOR');
  await login(page, ...USERS.administrador, 'El <b>Administrador</b> ingresa con su usuario y clave');

  await page.goto(BASE + '/#/main/dashboard');
  await page.waitForTimeout(2500); await ensureUi(page);
  await paso(page, '<b>Dashboard</b>: KPIs del día, solicitudes por estado y gráficos', 2600);
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(1800);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.waitForTimeout(600);

  await page.goto(BASE + '/#/main/reportes');
  await page.waitForTimeout(2200); await ensureUi(page);
  await paso(page, '<b>Reportes</b>: filtrar por fechas/estado y exportar Excel/CSV', 2600);

  await page.goto(BASE + '/#/main/administracion');
  await page.waitForTimeout(1800); await ensureUi(page);
  await paso(page, '<b>Administración</b>: catálogos del sistema. Pestaña Usuarios', 2400);
  await paso(page, 'El formulario superior permite <b>crear usuarios</b>: usuario, nombre, DNI, rol, área y clave', 3000);
  try {
    await clic(page, page.locator('table tbody tr button:has(i.pi-pencil)').first(), 'El lápiz activa el <b>modo edición</b> de un usuario');
    await page.waitForTimeout(1500);
    const cancel = page.locator('button:has-text("Cancelar"), button:has-text("Cancel")').first();
    if (await cancel.count()) await cancel.click().catch(() => {});
  } catch (e) { log('adm usr', e.message.split('\n')[0]); }
  await cerrarSwal(page);

  for (const tab of ['Conductores', 'Unidades', 'Tipos vehículo', 'Puntos', 'Motivos', 'Áreas', 'Comunicados', 'Auditoría']) {
    try {
      const b = page.locator(`button:has-text("${tab}")`).first();
      if (await b.count()) {
        await clic(page, b, `Pestaña <b>${tab}</b>`);
        await page.waitForTimeout(1300);
      }
      await cerrarSwal(page);
    } catch {}
  }

  try {
    await clic(page, page.locator('button[title="Cambiar clave"]'), 'Cada usuario puede <b>cambiar su clave</b> desde el menú');
    await page.waitForTimeout(1200);
    await cerrarDialogo(page);
  } catch {}

  await fin(page, 'Rol Administrador: todos los módulos + catálogos, comunicados y auditoría');
}

// ---------- limpieza de datos de prueba ----------
async function limpiarDatos(page) {
  log('limpieza de datos de prueba...');
  await login(page, ...USERS.coordinador);
  await page.waitForTimeout(1500);
  try {
    // separar solicitudes unidas a traslados
    for (let i = 0; i < 4; i++) {
      const b = page.locator('p-table tbody tr button:has-text("Separar")').first();
      if (!(await b.count())) break;
      await b.click(); await page.waitForTimeout(800);
      await cerrarSwal(page);
      await page.waitForTimeout(800);
    }
    // desasignar unidades de solicitudes asignadas
    for (let i = 0; i < 4; i++) {
      const b = page.locator('p-table tbody tr button:has-text("Desasignar")').first();
      if (!(await b.count())) break;
      await b.click(); await page.waitForTimeout(800);
      await cerrarSwal(page);
      await page.waitForTimeout(800);
    }
    // anular pendientes de la demo
    for (let i = 0; i < 4; i++) {
      const b = page.locator('p-table tbody tr button:has-text("Anular")').first();
      if (!(await b.count())) break;
      await b.click(); await page.waitForTimeout(800);
      await cerrarSwal(page);
      await page.waitForTimeout(800);
    }
  } catch (e) { log('limpieza:', e.message.split('\n')[0]); }
  log('limpieza terminada');
}

// ---------- main ----------
const arg = (process.argv[2] || 'all').toLowerCase();
const browser = await chromium.launch({ headless: true });
const videos = { supervisor: videoSupervisor, coordinador: videoCoordinador, conductor: videoConductor, administrador: videoAdministrador };

if (arg === 'all') {
  await grabar('supervisor', browser, videoSupervisor);
  await grabar('coordinador', browser, videoCoordinador);
  await grabar('conductor', browser, videoConductor);
  await grabar('administrador', browser, videoAdministrador);
  const ctx = await browser.newContext({ viewport: VP });
  await limpiarDatos(await ctx.newPage());
  await ctx.close();
} else if (videos[arg]) {
  await grabar(arg, browser, videos[arg]);
} else if (arg === 'limpiar') {
  const ctx = await browser.newContext({ viewport: VP });
  await limpiarDatos(await ctx.newPage());
  await ctx.close();
} else {
  console.error('Rol desconocido:', arg, '| opciones: all, supervisor, coordinador, conductor, administrador');
}
await browser.close();
log('listo');
