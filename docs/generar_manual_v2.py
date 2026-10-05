# -*- coding: utf-8 -*-
"""Genera el Manual de Usuario V2 del sistema de Transporte de Personal.

Cubre el rediseño de la interfaz: tipografía legible, tablas PrimeNG con
paginación, botones de acción con íconos y tooltips, y comportamiento
responsive para celular.
"""
import os
from docx import Document
from docx.shared import Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT

MORADO = RGBColor(0x7B, 0x1F, 0xA2)
GRIS = RGBColor(0x55, 0x55, 0x55)
OUT = os.path.dirname(os.path.abspath(__file__))


def estilo_base(doc):
    st = doc.styles['Normal']
    st.font.name = 'Calibri'
    st.font.size = Pt(11)
    for h, sz in (('Heading 1', 18), ('Heading 2', 14), ('Heading 3', 12)):
        s = doc.styles[h]
        s.font.name = 'Calibri'
        s.font.size = Pt(sz)
        s.font.color.rgb = MORADO
        s.font.bold = True


def portada(doc, titulo, subtitulo):
    for _ in range(6):
        doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(titulo)
    r.font.size = Pt(28)
    r.font.bold = True
    r.font.color.rgb = MORADO
    p2 = doc.add_paragraph()
    p2.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r2 = p2.add_run(subtitulo)
    r2.font.size = Pt(14)
    r2.font.color.rgb = GRIS
    p3 = doc.add_paragraph()
    p3.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p3.add_run('\nAplicativo de Transporte de Personal Interno\n'
               'Versión 2.0 — Octubre 2026').font.color.rgb = GRIS
    doc.add_page_break()


def tabla(doc, cabecera, filas, anchos=None):
    t = doc.add_table(rows=1, cols=len(cabecera))
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, c in enumerate(cabecera):
        cell = t.rows[0].cells[i]
        cell.text = c
        for p in cell.paragraphs:
            for r in p.runs:
                r.font.bold = True
    for fila in filas:
        cells = t.add_row().cells
        for i, v in enumerate(fila):
            cells[i].text = str(v)
    if anchos:
        for i, w in enumerate(anchos):
            for row in t.rows:
                row.cells[i].width = Cm(w)
    doc.add_paragraph()
    return t


def viñetas(doc, items):
    for it in items:
        doc.add_paragraph(it, style='List Bullet')


def pasos(doc, items):
    for it in items:
        doc.add_paragraph(it, style='List Number')


def imagen(doc, archivo, caption, ancho=Cm(15.5)):
    """Inserta una captura de docs/img/v2 (o docs/img si es reutilizada de V1)."""
    ruta = os.path.join(OUT, 'img', 'v2', archivo)
    if not os.path.exists(ruta):
        ruta = os.path.join(OUT, 'img', archivo)
    if not os.path.exists(ruta):
        print('  (falta imagen: ' + archivo + ')')
        return
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.add_run().add_picture(ruta, width=ancho)
    c = doc.add_paragraph()
    c.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = c.add_run(caption)
    r.font.size = Pt(9)
    r.font.italic = True
    r.font.color.rgb = GRIS


m = Document()
estilo_base(m)
portada(m, 'Manual de Usuario — V2', 'Aplicativo de Transporte de Personal Interno')

# ---------------- 1. INTRODUCCIÓN ----------------
m.add_heading('1. Introducción', 1)
m.add_paragraph(
    'Este manual explica paso a paso, con capturas reales de pantalla, cómo utilizar el aplicativo '
    'web de transporte de personal. El sistema reemplaza la coordinación por WhatsApp y hojas de '
    'cálculo: un supervisor solicita una movilidad, el jefe de transporte asigna la combi y las '
    'paradas, el conductor ejecuta el viaje y la dirección/administración consulta reportes.')
m.add_paragraph('Requisitos para usar el aplicativo:')
viñetas(m, [
    'Un navegador moderno (Chrome, Edge o similar), en computadora o celular.',
    'Un usuario y contraseña asignados por el administrador del sistema.',
    'Conexión a internet para entrar; si la conexión se pierde mientras trabaja, la aplicación '
    'guarda sus acciones en el equipo y las envía automáticamente al volver (modo offline).',
    'Opcionalmente, aceptar el permiso de notificaciones del navegador para recibir avisos '
    'aunque esté en otra pestaña.',
])
m.add_paragraph(
    'Convenio del manual: cada figura muestra la pantalla real del sistema y debajo se indica su '
    'nombre ("Fig. N — descripción"). Los textos entre comillas corresponden a botones o '
    'etiquetas tal como aparecen en pantalla.')

m.add_heading('1.1 Novedades de la versión 2.0', 2)
m.add_paragraph(
    'Esta versión incorpora una actualización visual y de usabilidad sobre toda la aplicación, '
    'pensada para trabajar igual de cómodo en computadora y en celular:')
viñetas(m, [
    'Letra más grande y legible en todo el sistema (tablas, formularios, botones y menús).',
    'Todas las tablas tienen paginador propio: muestran 10 filas por página con el texto '
    '"Mostrando 1 a 10 de N registros", flechas para cambiar de página y un selector para ver '
    '5, 10, 20 o 50 filas.',
    'Los botones de acción de las tablas son solo íconos y están siempre en la columna '
    'ACCIONES. En computadora, al pasar el mouse sobre un botón aparece una etiqueta flotante '
    '(tooltip) que indica qué hace.',
    'En celular, como no hay mouse, cada botón muestra su nombre debajo del ícono '
    '(Iniciar, Editar, Anular, etc.).',
    'El panel de notificaciones y el de cambio de clave ocupan el ancho de la pantalla en '
    'celular, sin cortarse.',
    'Las tablas anchas se desplazan lateralmente en celular; en Administración las filas se '
    'muestran como tarjetas con cada dato etiquetado.',
])

# ---------------- 2. ACCESO ----------------
m.add_heading('2. Acceso al sistema', 1)
pasos(m, [
    'Abra el navegador e ingrese a la dirección del aplicativo (por ejemplo http://localhost:4200 '
    'o la URL interna que le indique el administrador).',
    'Escriba su Usuario y su Clave en el formulario de ingreso.',
    'Presione el botón "Ingresar".',
    'El sistema lo lleva automáticamente a su pantalla principal según su rol.',
])
imagen(m, 'v2_01_login.png',
       'Fig. 1 — Pantalla de inicio de sesión. El ojo junto al campo Clave permite ver lo que escribe.')
m.add_paragraph('La pantalla inicial que verá depende de su rol:')
tabla(m,
      ['Rol', 'Pantalla inicial', 'Opciones del menú'],
      [
          ['Supervisor', 'Solicitudes', 'Solicitudes'],
          ['Jefe de Transporte', 'Coordinación', 'Coordinación, Reportes'],
          ['Conductor', 'Mis servicios', 'Mis servicios'],
          ['Administrador', 'Coordinación', 'Solicitudes, Coordinación, Mis servicios, Reportes, Administración'],
      ],
      anchos=[4.0, 4.0, 8.5])
m.add_paragraph(
    'Si el usuario o la clave son incorrectos aparece un aviso rojo bajo el formulario. Verifique '
    'los datos o pida al administrador que revise su cuenta en Administración → Usuarios.')
m.add_paragraph(
    'Para cerrar sesión presione "Cerrar sesión" (abajo del menú lateral) o el ícono de salida '
    'en el encabezado, junto a su nombre.')

# ---------------- 3. ELEMENTOS COMUNES ----------------
m.add_heading('3. Elementos comunes de la pantalla', 1)
m.add_paragraph(
    'Toda la aplicación comparte la misma estructura: a la izquierda el menú lateral con las '
    'opciones de su rol; arriba el encabezado con el nombre del módulo, la fecha, su nombre de '
    'usuario con su rol, y los íconos de notificaciones, cambio de clave y salir.')
tabla(m,
      ['Elemento', 'Dónde está', 'Para qué sirve'],
      [
          ['Menú lateral', 'Columna izquierda', 'Navegar entre los módulos de su rol. El botón ☰ lo pliega para ganar espacio.'],
          ['Campana', 'Encabezado, derecha', 'Abre el panel de notificaciones. Un punto rojo indica que hay avisos sin leer; toque una para marcarla como leída.'],
          ['Badge amarillo', 'Encabezado, junto a la campana', 'Aparece solo si hay operaciones guardadas sin internet pendientes de sincronizar.'],
          ['Llave', 'Encabezado, junto a su nombre', 'Abre el formulario para cambiar su contraseña (mínimo 6 caracteres).'],
          ['Nombre + rol', 'Encabezado, derecha', 'Muestra su nombre y la etiqueta de su rol (SUPERVISOR, COORDINADOR, CONDUCTOR o ADMINISTRADOR).'],
          ['Salir', 'Encabezado / menú lateral', 'Cierra la sesión y vuelve a la pantalla de ingreso.'],
      ],
      anchos=[3.2, 4.3, 9.0])
imagen(m, 'v2_05_notificaciones.png',
       'Fig. 2 — Panel de notificaciones al presionar la campana: asignaciones, cambios de '
       'estado y pasajeros agregados.')

m.add_heading('3.1 Las tablas y su paginador', 2)
m.add_paragraph(
    'Todos los listados del sistema usan el mismo formato de tabla con paginador en la parte '
    'inferior:')
viñetas(m, [
    '"Mostrando 1 a 10 de N registros": indica qué filas está viendo y el total.',
    'Flechas « ‹ › »: cambiar de página (primera, anterior, siguiente, última).',
    'Selector de filas: elija ver 5, 10, 20 o 50 registros por página.',
    'Encabezados en mayúsculas; la última columna es siempre ACCIONES cuando la tabla tiene botones.',
])

m.add_heading('3.2 Botones de acción con íconos', 2)
m.add_paragraph(
    'Los botones de acción de las tablas son solo íconos, todos del mismo tamaño. Para saber qué '
    'hace cada uno:')
viñetas(m, [
    'En computadora: pase el mouse sobre el botón y aparece una etiqueta flotante (tooltip) '
    'con el nombre de la acción.',
    'En celular: el nombre de la acción se muestra siempre debajo del ícono, porque en pantallas '
    'táctiles no existe "pasar el mouse".',
])
tabla(m,
      ['Ícono', 'Acción', 'Dónde aparece'],
      [
          ['▶ (azul)', 'Iniciar el servicio', 'Mis servicios'],
          ['✓ (verde)', 'Finalizar el servicio', 'Mis servicios'],
          ['Persona+ (rojo)', 'Agregar pasajeros de emergencia', 'Mis servicios'],
          ['Mapa (celeste)', 'Ver ruta y paradas', 'Mis servicios'],
          ['Lápiz (azul)', 'Editar el registro', 'Solicitudes, Coordinación, Administración'],
          ['X (roja)', 'Anular o desactivar', 'Solicitudes, Coordinación'],
          ['⛓ (roja)', 'Separar del traslado', 'Coordinación'],
          ['⚡ (verde)', 'Asignación automática de unidad', 'Coordinación'],
          ['⧉ (gris)', 'Asignación múltiple de unidades', 'Coordinación'],
      ],
      anchos=[3.2, 6.5, 6.0])

m.add_heading('3.3 Uso en celular', 2)
m.add_paragraph(
    'La aplicación se adapta a pantallas pequeñas de forma automática:')
viñetas(m, [
    'El menú lateral se repliega y se abre con el botón ☰ del encabezado.',
    'Los paneles de notificaciones y de cambio de clave ocupan casi todo el ancho de la pantalla '
    'debajo del encabezado.',
    'Las tablas anchas se recorren deslizando el dedo hacia los lados.',
    'En Administración, cada fila se convierte en una tarjeta con sus datos etiquetados.',
    'Los botones de acción muestran su nombre debajo del ícono.',
])
imagen(m, 'v2_m01_solicitudes.png', 'Fig. 3 — Solicitudes en celular: filtros, tabla y paginador.', Cm(7.0))
imagen(m, 'v2_m02_acciones.png',
       'Fig. 4 — Columna ACCIONES en celular: cada ícono muestra su nombre debajo.', Cm(7.0))
imagen(m, 'v2_m03_notificaciones.png',
       'Fig. 5 — Panel de notificaciones en celular: ocupa el ancho de la pantalla sin cortarse.', Cm(7.0))
imagen(m, 'v2_m04_administracion.png',
       'Fig. 6 — Administración en celular: cada registro se muestra como tarjeta etiquetada.', Cm(7.0))

m.add_heading('3.4 Trabajar sin internet (modo offline)', 2)
m.add_paragraph(
    'Si pierde la conexión, la aplicación sigue funcionando con la última información cargada: '
    'puede consultar listados que ya haya visto y ejecutar acciones (crear, asignar, cambiar '
    'estado, etc.). Estas acciones se guardan en el equipo y aparecen contadas en el badge '
    'amarillo del encabezado. Al recuperar internet se envían solas en el mismo orden y el badge '
    'desaparece cuando todo quedó sincronizado.')

# ---------------- 4. SOLICITUDES ----------------
m.add_heading('4. Módulo Solicitudes (Supervisor)', 1)
m.add_paragraph(
    'Es la pantalla principal del supervisor. Muestra el listado de movilidades programadas con '
    'todas sus columnas y permite crear, editar, anular y acoplar solicitudes.')
imagen(m, 'v2_02_solicitudes.png',
       'Fig. 7 — Listado de solicitudes con paginador. Arriba: filtros de fecha y botón "Crear". '
       'La última columna es ACCIONES.')

m.add_heading('4.1 Entender el listado', 2)
tabla(m,
      ['Columna', 'Qué muestra'],
      [
          ['PRIORIDAD', 'NORMAL o EMERGENCIA. Las emergencias van primero y la fila se pinta en rojo.'],
          ['NOMBRE', 'Quién registró la solicitud.'],
          ['FECHA / HORA', 'Fecha y hora programada del viaje.'],
          ['ÁREA', 'Área del solicitante.'],
          ['P. PARTIDA / P. LLEGADA', 'Punto de origen y punto de destino (del catálogo de Puntos).'],
          ['CANTIDAD', 'Número de personas a trasladar.'],
          ['MOTIVO', 'Motivo del viaje (capacitación, actividad, salud, etc.).'],
          ['PLACA', 'Unidad asignada (vacío mientras esté pendiente).'],
          ['CUPO', 'Ocupadas/capacidad de la unidad. Verde = hay espacio, ámbar = casi llena, rojo = llena.'],
          ['ESTADO', 'PENDIENTE, ASIGNADO, EN_RUTA, REALIZADO o ANULADO.'],
          ['ACCIONES', 'Lápiz = editar. X roja = anular (pide confirmación).'],
      ],
      anchos=[4.0, 12.5])
m.add_paragraph(
    'Sobre la tabla hay dos campos de fecha "Desde" / "Hasta": al elegir un rango la lista se '
    'limita a esas fechas, y aparece el botón "Ver todas" para quitar el filtro. Clic sobre '
    'cualquier fila abre el detalle de la solicitud. Debajo de la tabla, el paginador permite '
    'cambiar de página o elegir cuántas filas ver (5, 10, 20 o 50).')

m.add_heading('4.2 Crear una solicitud', 2)
pasos(m, [
    'Presione el botón "Crear" en la parte superior derecha.',
    'Su nombre aparece ya cargado en el campo NOMBRE (no se puede modificar).',
    'Complete los campos obligatorios (marcados con *):',
])
tabla(m,
      ['Campo', 'Obligatorio', 'Descripción'],
      [
          ['FECHA PROGRAMADA', 'Sí', 'Día en que se realizará el viaje.'],
          ['Hr. PROGRAMADA', 'Sí', 'Hora de salida.'],
          ['P. PARTIDA', 'Sí', 'Punto donde sube el personal (lista del catálogo de Puntos).'],
          ['P. LLEGADA', 'Sí', 'Punto de destino.'],
          ['CANTIDAD', 'Sí', 'Personas a trasladar (mínimo 1; con flechas para subir/bajar).'],
          ['MOTIVO', 'Sí', 'Motivo del viaje (lista del catálogo de Motivos).'],
          ['OBSERVACIÓN', 'No', 'Comentario libre para el jefe de transporte o el conductor.'],
          ['Emergencia médica', 'No', 'Marcar solo para urgencias: le da prioridad máxima.'],
      ],
      anchos=[4.5, 2.5, 9.5])
pasos(m, [
    'Presione "Save". El botón "Cancel" cierra sin guardar.',
    'La solicitud aparece en el listado con estado PENDIENTE; el jefe de transporte ya puede verla.',
])
imagen(m, 'v2_03_crear_solicitud.png',
       'Fig. 8 — Formulario de nueva solicitud. Todos los campos con * deben llenarse para habilitar "Save".')

m.add_heading('4.3 Ver el detalle de una solicitud', 2)
m.add_paragraph(
    'Haga clic sobre la fila de la solicitud. Se abre una ventana con todos sus datos: prioridad, '
    'solicitante, fecha y hora, área, puntos, cantidad, motivo, observación, placa, estado y si ya '
    'fue realizada. Si la solicitud está unida a un traslado, la ventana muestra además la ruta, '
    'las paradas con cuántos suben y bajan en cada una, y las demás solicitudes que comparten el viaje.')
imagen(m, 'v2_04_detalle_solicitud.png', 'Fig. 9 — Detalle completo de una solicitud (clic sobre la fila para abrirlo).')

m.add_heading('4.4 Acoplarse a una movilidad existente', 2)
m.add_paragraph(
    'Si otro supervisor ya tiene un traslado programado que pasa cerca de su punto de partida y '
    'destino, puede unir su solicitud a ese viaje sin esperar una nueva asignación.')
pasos(m, [
    'Cree su solicitud y ábrala haciendo clic en su fila.',
    'Al final del detalle aparece la sección "Acoplar a traslado con cupo" con los traslados '
    'compatibles (mismo corredor: origen y destino a menos de 10 km de la ruta).',
    'Cada botón muestra el traslado (T-N), la placa y su ruta. Presione el que le sirva.',
    'El sistema verifica que haya cupo; si lo hay, su solicitud queda ASIGNADA a ese traslado '
    'conservando su registro individual.',
])
m.add_paragraph(
    'Si no aparece la sección "Acoplar", es porque no hay traslados con cupo compatibles con su '
    'ruta; su solicitud esperará la asignación normal del jefe de transporte.')

m.add_heading('4.5 Editar o anular una solicitud', 2)
viñetas(m, [
    'Editar (lápiz azul): abre el mismo formulario de creación con los datos cargados para '
    'corregirlos. Disponible mientras la solicitud no esté realizada ni anulada.',
    'Anular (X roja): el sistema pide confirmación antes de cancelar la solicitud. La acción no '
    'se puede deshacer y queda registrada en la auditoría.',
])
m.add_paragraph(
    'Ambos botones están en la columna ACCIONES. En computadora pase el mouse sobre el ícono '
    'para ver su nombre; en celular el nombre aparece debajo del ícono.')

m.add_heading('4.6 Estados de una solicitud', 2)
tabla(m,
      ['Estado', 'Qué significa', 'Quién lo produce'],
      [
          ['PENDIENTE', 'Recién creada, aún sin unidad asignada.', 'Supervisor'],
          ['ASIGNADO', 'Ya tiene placa (solita o dentro de un traslado).', 'Jefe de transporte / acople'],
          ['EN_RUTA', 'El conductor inició el recorrido.', 'Conductor'],
          ['REALIZADO', 'El conductor finalizó el viaje; se guardan las horas.', 'Conductor'],
          ['ANULADO', 'Solicitud cancelada.', 'Supervisor / jefe de transporte'],
      ],
      anchos=[3.0, 9.0, 4.5])

# ---------------- 5. COORDINACIÓN ----------------
m.add_heading('5. Módulo Coordinación (Jefe de Transporte)', 1)
m.add_paragraph(
    'Es el centro de operaciones del día. La pantalla se divide en dos paneles: a la izquierda '
    'todas las solicitudes con sus acciones, y a la derecha los traslados activos con su ocupación.')
imagen(m, 'v2_06_coordinacion.png',
       'Fig. 10 — Coordinación: solicitudes a la izquierda, "Traslados activos" a la derecha y '
       'badges de disponibilidad de unidades sobre la tabla.')

m.add_heading('5.1 Ver la disponibilidad de las unidades', 2)
m.add_paragraph(
    'Sobre la tabla hay un badge por cada combi con la forma "PLACA · libres/capacidad", por '
    'ejemplo "TP-001 · 15/15 libres". El color resume el estado:')
viñetas(m, [
    'Verde: la unidad está libre o con bastante cupo.',
    'Ámbar: parcialmente ocupada.',
    'Rojo: llena — no acepta más pasajeros.',
])
m.add_paragraph(
    'Los selectores de placa en cada fila muestran el mismo cupo y bloquean automáticamente las '
    'unidades sin espacio, para que no pueda asignar más personas de las que caben.')

m.add_heading('5.2 Asignar unidad a una solicitud', 2)
m.add_paragraph('Cada fila de solicitud sin traslado tiene estos botones en la columna ACCIONES:')
tabla(m,
      ['Botón', 'Acción'],
      [
          ['Selector "Placa" + ✓ azul', 'Elige la unidad en la lista (muestra el cupo de cada una) y presione el check para asignarla.'],
          ['⚡ (rayo verde)', 'Asignación automática: el sistema toma la primera unidad con cupo suficiente.'],
          ['⧉ (ventanas gris)', 'Asignación múltiple: reparte la cantidad entre varias unidades cuando una sola no alcanza.'],
          ['Lápiz (azul)', 'Editar los datos de la solicitud.'],
          ['X (roja)', 'Anular la solicitud.'],
          ['⛓ (roja)', 'Separar del traslado (solo en solicitudes ya unidas).'],
      ],
      anchos=[5.0, 11.5])
pasos(m, [
    'En la columna ACCIONES de la solicitud elija la placa en el selector.',
    'Presione el botón ✓. Confirme el mensaje.',
    'La solicitud pasa a ASIGNADO y el conductor de esa placa recibe una notificación.',
    'Para reasignar a otra unidad (por ejemplo por una urgencia), repita el proceso con otra placa.',
])
m.add_paragraph(
    'Asignación múltiple (⧉): para solicitudes que superan la capacidad de una combi. Se abre un '
    'panel donde agrega tantas unidades como necesite con la cantidad de personas que llevará cada '
    'una; el total repartido debe coincidir exactamente con lo solicitado.')

m.add_heading('5.3 Unir solicitudes en un traslado', 2)
pasos(m, [
    'Marque con los checkboxes de la primera columna dos o más solicitudes compatibles.',
    'Arriba de la tabla aparecen el selector "Placa del traslado" y el botón "Unir (N)".',
    'Elija la placa y presione "Unir". Se crea el traslado T-N que agrupa las solicitudes: cada '
    'una conserva su número, solicitante y cantidad para los reportes.',
])
m.add_paragraph(
    'Separar: en la fila de una solicitud que está dentro de un traslado aparece el botón de '
    'desenlazar (⛓). Tras confirmar, la solicitud vuelve a estado PENDIENTE sin placa y el '
    'traslado recalcula su ocupación.')

m.add_heading('5.4 Definir las paradas y la ruta', 2)
pasos(m, [
    'En la tarjeta del traslado (panel derecho) presione "Editar paradas".',
    'Con "Agregar parada" añada filas: en cada una elija el punto (lista con buscador) y escriba '
    'cuántas personas suben y cuántas bajan ahí.',
    'Use las flechas ↑ ↓ para ordenar la secuencia de recogida y el basurero para quitar una parada.',
    'Presione "Guardar ruta". El conductor verá las paradas en ese orden en su aplicación.',
])
m.add_paragraph(
    'Con "Mapa" se despliega el recorrido dibujado sobre OpenStreetMap con los puntos de la '
    'ruta; "OSM" abre la misma ruta en una pestaña nueva para compartirla o navegarla.')

m.add_heading('5.5 Editar o anular solicitudes', 2)
m.add_paragraph(
    'A diferencia del supervisor, el jefe de transporte puede modificar cualquier solicitud. El '
    'lápiz abre un panel con todos los campos (fecha, hora, puntos, cantidad, motivo, observación '
    'y la marca de emergencia) para corregirlos; la X la anula con confirmación. Todo queda en auditoría.')

# ---------------- 6. MIS SERVICIOS ----------------
m.add_heading('6. Módulo Mis servicios (Conductor)', 1)
m.add_paragraph(
    'El conductor solo ve los servicios asignados a la placa de su unidad, ordenados con las '
    'emergencias primero. El botón "Actualizar" recarga la lista. La franja superior resume la '
    'ruta del día con la secuencia de puntos.')
imagen(m, 'v2_07_mis_servicios.png',
       'Fig. 11 — Mis servicios: solo los viajes de la placa del conductor, con la columna '
       'ACCIONES de íconos y el paginador al pie.')
tabla(m,
      ['Botón (columna ACCIONES)', 'Qué hace'],
      [
          ['▶ Iniciar (azul)', 'Aparece en servicios ASIGNADO. Lo presiona al arrancar: pasa a EN_RUTA y guarda la hora de inicio.'],
          ['✓ Finalizar (verde)', 'Aparece en servicios EN_RUTA. Lo presiona al terminar: pasa a REALIZADO y guarda la hora de fin.'],
          ['Persona+ (rojo)', 'Agregar pasajeros de emergencia si hay cupo libre.'],
          ['Mapa (celeste)', 'Ver la ruta del servicio con sus paradas ordenadas.'],
      ],
      anchos=[5.0, 11.5])
pasos(m, [
    'Al llegar a su turno, abra "Mis servicios" y revise los viajes asignados: origen, destino, '
    'cantidad de personas y motivo.',
    'Antes de arrancar, presione el ícono del mapa para conocer la ruta completa.',
    'Al iniciar el recorrido presione ▶ (Iniciar). El estado cambia a EN_RUTA.',
    'Recorra las paradas en el orden indicado: la tabla del mapa muestra cuántos suben y cuántos '
    'bajan en cada punto.',
    'Si en el camino debe subir pasajeros de emergencia, use el botón persona+ (ver abajo).',
    'Al terminar el viaje presione ✓ (Finalizar). El servicio queda REALIZADO.',
    'Sin señal puede seguir operando: los cambios se guardan en el equipo y se envían al recuperar '
    'internet (badge amarillo en el encabezado).',
])
imagen(m, 'v2_08_ruta_paradas.png',
       'Fig. 12 — Ruta del servicio: mapa con la trayectoria y tabla de paradas ordenadas '
       '(# / punto / suben / bajan). "Abrir en OSM" lleva la ruta a la navegación.')
m.add_heading('6.1 Agregar pasajeros de emergencia', 2)
pasos(m, [
    'En un servicio ASIGNADO o EN_RUTA presione el botón rojo de persona+.',
    'El panel muestra el cupo libre de la unidad ("Cupo libre: X de 15").',
    'Escriba cuántos pasajeros adicionales suben y presione "Agregar".',
    'Si la cantidad supera el cupo disponible el sistema lo rechaza. Al guardar, la solicitud '
    'queda marcada como emergencia y el supervisor recibe una notificación.',
])

# ---------------- 7. REPORTES ----------------
m.add_heading('7. Módulo Reportes (Jefe / Administrador)', 1)
m.add_paragraph('Genera el histórico de movilidades y los indicadores de operación.')
pasos(m, [
    'Elija el rango "Desde" / "Hasta" y presione "Generar".',
    'Opcionalmente refine con los filtros Supervisor, Placa y Estado (se aplican al instante '
    'sobre la tabla, los totales y el CSV).',
    'Revise las tarjetas de indicadores y las tablas de eficiencia.',
    'Use "Exportar CSV" para descargar el detalle (compatible con Excel) o "Imprimir / PDF" '
    'para la versión imprimible.',
])
imagen(m, 'v2_10_reportes.png',
       'Fig. 13 — Reportes: filtros de fecha y supervisor/placa/estado, totales rápidos y '
       'tarjetas de indicadores de operación.')
tabla(m,
      ['Indicador', 'Qué mide'],
      [
          ['Solicitudes / Personas', 'Total de movilidades y de personas trasladadas en el rango.'],
          ['Realizados / Emergencias', 'Viajes completados y cuántos fueron de emergencia.'],
          ['Duración promedio', 'Tiempo medio entre Iniciar y Finalizar.'],
          ['Espera promedio', 'Tiempo medio entre la creación de la solicitud y su atención.'],
          ['Puntualidad ±10 min', 'Porcentaje de servicios realizados dentro de 10 minutos de la hora programada.'],
          ['Eficiencia por unidad', 'Viajes, personas y porcentaje de ocupación por combi.'],
          ['Servicios por conductor', 'Viajes y personas atendidas por cada conductor.'],
          ['Movimiento por área', 'Solicitudes y personas agrupadas por el área que las pidió.'],
      ],
      anchos=[5.0, 11.5])
m.add_paragraph(
    'Todas las tablas del reporte (registros, eficiencia por unidad, servicios por conductor y '
    'movimiento por área) tienen su propio paginador. En celular, los filtros y botones se '
    'acomodan en varias filas para que nada quede fuera de la pantalla.')
imagen(m, 'v2_m05_reportes.png',
       'Fig. 14 — Reportes en celular: los filtros y botones se reparten en filas sin cortarse.', Cm(7.0))
m.add_heading('7.1 Auditoría', 2)
m.add_paragraph(
    'El botón "Cargar auditoría" muestra el historial de todas las acciones del sistema: inicios '
    'de sesión, creación y edición de solicitudes, asignaciones, uniones, separaciones, cambios de '
    'estado y pasajeros agregados, con fecha, entidad afectada y usuario. La tabla pagina de a 5 '
    'filas y permite cambiar a 10 o 20 por página.')
imagen(m, 'v2_11_auditoria.png', 'Fig. 15 — Auditoría del sistema con su paginador.')

# ---------------- 8. ADMINISTRACIÓN ----------------
m.add_heading('8. Módulo Administración (Administrador)', 1)
m.add_paragraph(
    'Gestiona los catálogos del sistema en cinco pestañas. En todas funciona igual: el formulario '
    'de la parte superior sirve para crear (botón "Crear") y para editar: al presionar el lápiz en '
    'una fila, sus datos se cargan en el formulario y el botón cambia a "Actualizar". El botón de '
    'prohibido inhabilita el registro sin borrarlo; en usuarios, si deja la clave vacía al editar '
    'se conserva la actual.')
tabla(m,
      ['Pestaña', 'Campos del formulario', 'Para qué sirve'],
      [
          ['Usuarios', 'Usuario, nombre, rol (supervisor/coordinador/administrador), área y clave.',
           'Cuentas del personal que solicita, coordina o administra.'],
          ['Conductores', 'Usuario, nombre, placa de la unidad asignada, área y clave.',
           'Cuentas de conductor; la placa define qué servicios verá en "Mis servicios".'],
          ['Unidades', 'Placa y capacidad (≈15).',
           'Las combis disponibles para asignar.'],
          ['Puntos', 'Nombre, latitud y longitud.',
           'Orígenes/destinos y paradas. Las coordenadas alimentan el mapa y la validación de rutas al acoplarse.'],
          ['Motivos', 'Nombre.',
           'Catálogo de motivos de viaje que elige el supervisor.'],
      ],
      anchos=[2.8, 6.7, 7.0])
imagen(m, 'v2_12_administracion.png',
       'Fig. 16 — Administración: pestañas del catálogo, formulario arriba y tabla con '
       'paginador y acciones Editar/Desactivar por fila.')
m.add_paragraph(
    'En celular, la tabla de registros se muestra como tarjetas: cada fila se convierte en una '
    'tarjeta con sus datos etiquetados (ver Fig. 6), sin necesidad de deslizar de costado.')

# ---------------- 9. GUÍA RÁPIDA ----------------
m.add_heading('9. Guía rápida por rol', 1)
tabla(m,
      ['Rol', 'Flujo típico'],
      [
          ['Supervisor',
           '1. Ingresar → Solicitudes. 2. "Crear" y llenar el formulario. 3. (Opcional) Abrir el detalle y '
           'acoplarse a un traslado con cupo. 4. Seguir el estado en la columna ESTADO. 5. Editar o anular desde ACCIONES.'],
          ['Jefe de Transporte',
           '1. Ingresar → Coordinación. 2. Revisar badges de cupo por unidad. 3. Asignar placa (✓, ⚡ o ⧉) '
           'o unir solicitudes compatibles en un traslado. 4. "Editar paradas" para ordenar el recorrido. '
           '5. Atender urgencias reasignando. 6. Revisar Reportes al cierre.'],
          ['Conductor',
           '1. Ingresar → Mis servicios. 2. Revisar la ruta y las paradas con el ícono de mapa. '
           '3. ▶ al arrancar. 4. Persona+ solo para pasajeros de emergencia con cupo. '
           '5. ✓ al terminar.'],
          ['Administrador',
           '1. Mantener catálogos en Administración (usuarios, conductores con su placa, unidades, '
           'puntos con coordenadas, motivos). 2. Revisar Reportes y Auditoría. 3. Puede operar '
           'además cualquier pantalla de los demás roles.'],
      ],
      anchos=[3.5, 13.0])

# ---------------- 10. GLOSARIO ----------------
m.add_heading('10. Glosario', 1)
tabla(m,
      ['Término', 'Significado'],
      [
          ['Solicitud', 'Pedido de transporte creado por un supervisor.'],
          ['Traslado (T-N)', 'Agrupación de una o más solicitudes bajo una misma placa, con su ruta y paradas ordenadas.'],
          ['Acoplarse', 'Unir una solicitud nueva a un traslado ya programado que tenga cupo y ruta compatible (máx. 10 km).'],
          ['Parada', 'Punto intermedio de la ruta donde sube o baja personal.'],
          ['Cupo', 'Asientos libres de la unidad (ocupadas/capacidad).'],
          ['Emergencia', 'Solicitud de máxima prioridad: se muestra en rojo y primero en las listas.'],
          ['Badge', 'Etiqueta de color que resume un estado (verde/ámbar/rojo).'],
          ['Tooltip', 'Etiqueta flotante con el nombre de un botón; aparece al pasar el mouse (en celular el nombre se ve debajo del ícono).'],
          ['Paginador', 'Controles al pie de cada tabla para cambiar de página y elegir cuántas filas ver.'],
          ['Auditoría', 'Registro de quién hizo cada cambio y cuándo.'],
          ['Modo offline', 'Trabajo sin internet: las acciones se guardan en el equipo y se sincronizan al volver la conexión.'],
      ],
      anchos=[3.5, 13.0])

m.save(os.path.join(OUT, 'Manual_de_Usuario_Transporte_Personal_V2.docx'))
print('OK Manual V2')
