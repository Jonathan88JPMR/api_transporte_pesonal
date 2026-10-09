# Diseño — Seguimiento de paradas intermedias (A → a1 → a2 → … → B)

## 1. Objetivo

Controlar el recorrido completo de una unidad cuando un traslado (o una solicitud
individual) tiene paradas intermedias entre el punto de partida A y el destino B:

- El **coordinador** define la ruta ordenada de paradas y cuántos pasajeros
  suben/bajan en cada una (planeado), y luego ve el progreso en tiempo real.
- El **conductor** marca la llegada a cada parada y registra los conteos reales
  de pasajeros que suben y bajan.
- El sistema calcula los **pasajeros a bordo por tramo**, valida capacidad y
  deja auditoría de cada evento con hora y posición GPS.

## 2. Modelo de datos (SQL Server)

### 2.1 Tabla `Parada` (extender la existente)

```sql
CREATE TABLE Parada (
    idParada          INT IDENTITY(1,1) PRIMARY KEY,
    idTraslado        INT NULL,              -- FK → Traslado
    idSolicitud       INT NULL,              -- FK → Solicitud (asignación simple sin traslado)
    idPunto           INT NULL,              -- FK → catálogo Puntos (nullable si es texto libre)
    punto             NVARCHAR(150) NOT NULL,
    orden             INT NOT NULL,

    -- Planeado (lo define el coordinador)
    cantidadSube      INT NOT NULL DEFAULT 0,
    cantidadBaja      INT NOT NULL DEFAULT 0,

    -- Real (lo registra el conductor)
    subieronReal      INT NULL,
    bajaronReal       INT NULL,

    estado            VARCHAR(12) NOT NULL DEFAULT 'PENDIENTE'
                      CHECK (estado IN ('PENDIENTE','EN_PARADA','REALIZADA','OMITIDA')),
    horaLlegada       DATETIME2 NULL,
    horaSalida        DATETIME2 NULL,

    -- GPS del dispositivo al momento de marcar
    latitud           DECIMAL(9,6) NULL,
    longitud          DECIMAL(9,6) NULL,

    motivoOmision     NVARCHAR(200) NULL,
    usuarioRegistra   NVARCHAR(60) NULL,
    fechaRegistro     DATETIME2 NOT NULL DEFAULT SYSDATETIME(),

    CHECK ((idTraslado IS NOT NULL AND idSolicitud IS NULL)
        OR (idTraslado IS NULL AND idSolicitud IS NOT NULL))
);
```

> Una parada pertenece a un traslado **o** a una solicitud suelta (asignación
> de una sola unidad sin unir). El CHECK garantiza exactamente uno de los dos.

### 2.2 Tabla nueva `ParadaDetalle` — vínculo parada ↔ solicitud

Responde "qué grupo de pasajeros sube o baja en esta parada". Permite
autogenerar la ruta al unir solicitudes y validar los conteos por solicitud.

```sql
CREATE TABLE ParadaDetalle (
    idParadaDetalle      INT IDENTITY(1,1) PRIMARY KEY,
    idParada             INT NOT NULL REFERENCES Parada(idParada),
    idSolicitud          INT NOT NULL REFERENCES Solicitud(idSolicitud),
    idSolicitudUnidad    INT NULL,          -- porción cuando la solicitud usa varias unidades
    tipo                 CHAR(1) NOT NULL CHECK (tipo IN ('S','B')),  -- Sube / Baja
    cantidadPlaneada     INT NOT NULL,
    cantidadReal         INT NULL,
    UNIQUE (idParada, idSolicitud, tipo)
);
```

### 2.3 Datos derivados (no se persisten)

- **A bordo en el tramo k** = `Σ(suben) − Σ(bajan)` de las paradas 1..k.
  Se calcula sobre lo planeado o sobre lo real según el contexto.
- **Parada actual** = primera parada con `estado IN ('PENDIENTE','EN_PARADA')`
  ordenada por `orden`.
- **Progreso** = `paradas REALIZADAS / total`.

## 3. Reglas de negocio

### 3.1 Generación de la ruta (coordinador)

- Al **unir solicitudes** (`traslados/unir`), el SP autogenera paradas:
  - cada `puntoPartida` produce un detalle `S` con `cantidad`;
  - cada `puntoLlegada` produce un detalle `B` con `cantidad`;
  - puntos repetidos se **fusionan** en una sola parada (una parada puede
    tener varios detalles S y B de distintas solicitudes);
  - orden inicial sugerido: por `horaProgramada` de la solicitud, partida
    antes que llegada de la misma solicitud.
- El coordinador puede reordenar, agregar o quitar paradas (paradas
  intermedias sin solicitud, p. ej. un punto de control, se permiten con
  sube/baja en 0).
- `cantidadSube`/`cantidadBaja` de `Parada` = totales; si existe
  `ParadaDetalle`, deben ser la suma de sus detalles (el SP los recalcula).

### 3.2 Validaciones al guardar la ruta

- Σ suben planeada = Σ bajan planeada (la unidad termina vacía). Si no cuadra,
  advertir (o rechazar, configurable).
- En ningún tramo el "a bordo" puede exceder la capacidad de la unidad.
- No se puede editar la ruta si ya hay paradas `REALIZADA`/`EN_PARADA`
  salvo que solo se modifiquen las paradas aún `PENDIENTE`.

### 3.3 Ejecución (conductor)

Transición por parada: `PENDIENTE → EN_PARADA → REALIZADA` (o `OMITIDA`).

1. **Llegar**: `EN_PARADA`, graba `horaLlegada`, `latitud/longitud`, usuario.
   Solo se puede activar la primera parada `PENDIENTE` (la "parada actual"),
   salvo omisión explícita de las anteriores.
2. **Registrar**: graba `subieronReal`/`bajaronReal` (prellenados con lo
   planeado), opcionalmente `cantidadReal` por detalle, `horaSalida`,
   estado `REALIZADA`.
3. **Omitir**: estado `OMITIDA` + `motivoOmision` (p. ej. pasajeros no se
   presentaron). Requiere motivo si tenía suben/bajan planeados > 0.
4. El servicio/traslado solo puede pasar a `REALIZADO` cuando no quedan
   paradas `PENDIENTE`/`EN_PARADA` (o con advertencia confirmable).
5. **Pasajeros extra de emergencia** (`conductor/agregar-pasajeros`) deben
   recibir `idParada` para saber dónde subieron; el SP incrementa
   `subieronReal` de esa parada y crea un `ParadaDetalle` tipo `S`.

### 3.4 Seguimiento (coordinador)

- Vista por traslado: línea de tiempo con cada parada (punto, estado, hora
  real vs. nada, suben/bajan planeado vs. real, a bordo del tramo).
- Resumen: "T-12 · ABC-123 · parada 2/5 · 14 a bordo".
- Refresco: polling cada ~30 s (endpoint liviano `traslados/progreso`) o
  SignalR si más adelante se quiere push.

### 3.5 Offline / auditoría

- Las mutaciones del frontend ya se encolan en Dexie si no hay red
  (`TransporteService.mutar`). Los eventos de parada deben enviar
  `horaCliente` para conservar el timestamp real del evento, no el de
  sincronización.
- Cada evento (llegada, registro, omisión, edición de ruta) inserta en la
  tabla `Auditoria` existente: entidad `PARADA`, acción, usuario, detalle JSON.

## 4. Stored procedures

### 4.1 `sp_Traslado_GuardarParadas` (extender el actual)

Entrada: `@idTraslado INT`, `@paradas NVARCHAR(MAX)` (JSON), `@usuario`.

```json
[
  { "idParada": 12, "idPunto": 3, "punto": "Planta Norte", "orden": 1,
    "cantidadSube": 10, "cantidadBaja": 0,
    "detalle": [{"idSolicitud": 7, "tipo": "S", "cantidadPlaneada": 10}] }
]
```

Lógica: upsert por `idParada` (los nuevos sin id se insertan), borrar las
paradas PENDIENTE ausentes del JSON, recalcular totales desde `ParadaDetalle`,
rechazar si se intenta tocar una parada ya ejecutada.

### 4.2 `sp_Parada_Llegada`

Entrada: `@idParada`, `@horaCliente`, `@latitud`, `@longitud`, `@usuario`.

- Valida que sea la parada actual (primera PENDIENTE por orden).
- `estado='EN_PARADA'`, `horaLlegada=@horaCliente`, GPS, auditoría.
- Salida: la parada actualizada + progreso (FOR JSON PATH).

### 4.3 `sp_Parada_Registrar`

Entrada: `@idParada`, `@subieronReal`, `@bajaronReal`,
`@detalle NVARCHAR(MAX)` (opcional), `@horaCliente`, `@latitud`,
`@longitud`, `@usuario`.

- Requiere `estado='EN_PARADA'` (o la marca llegada+salida en un paso).
- Valida que el a bordo resultante no exceda la capacidad de la unidad.
- Actualiza `cantidadReal` de cada `ParadaDetalle` enviado.
- `estado='REALIZADA'`, `horaSalida=@horaCliente`, auditoría.
- Si era la última parada del traslado, sugerir `REALIZADO` del servicio
  (el SP puede hacerlo automático o devolver una bandera).

### 4.4 `sp_Parada_Omitir`

Entrada: `@idParada`, `@motivo`, `@usuario`. Estado `OMITIDA` + auditoría.

### 4.5 `sp_Traslado_Progreso` (polling liviano)

Entrada: `@idTraslado`. Salida (FOR JSON PATH):

```json
[{ "idTraslado": 12, "placa": "ABC-123", "paradaActual": 2, "totalParadas": 5,
   "aBordo": 14, "estadoTraslado": "EN_RUTA",
   "paradas": [ {"idParada":1,"punto":"A","estado":"REALIZADA",
                 "horaLlegada":"...","subieronReal":10,"bajaronReal":0}, ... ] }]
```

### 4.6 Modificar SPs existentes

- `sp_Traslado_Listar` / `sp_Conductor_Servicios`: incluir `paradas` con
  `estado`, horas y conteos reales en el JSON anidado.
- `sp_Traslado_Unir`: generar `Parada` + `ParadaDetalle` automáticamente.
- `sp_Conductor_AgregarPasajeros`: aceptar `@idParada`.
- `sp_Solicitud_Asignar`: crear estructura para que una solicitud simple
  también pueda tener paradas (o crear un traslado implícito de una sola
  solicitud — más simple y uniforme; recomendado).

> **Recomendación:** que toda asignación cree un `Traslado` (incluso de una
> sola solicitud). Así las paradas, el progreso y el conductor trabajan sobre
> un solo concepto, y desaparece el caso especial de `idSolicitud` en `Parada`
> y el de solicitudes "MULTIPLE" sin traslado.

## 5. Endpoints REST (api/transporte)

| Método | Ruta | Body |
|---|---|---|
| POST | `traslados/paradas` | `{ idTraslado, paradas[], usuario }` (existe) |
| POST | `paradas/llegada` | `{ idParada, horaCliente, latitud, longitud }` |
| POST | `paradas/registrar` | `{ idParada, subieronReal, bajaronReal, detalle[], horaCliente, latitud, longitud }` |
| POST | `paradas/omitir` | `{ idParada, motivo }` |
| POST | `paradas/imprevista` | `{ idTraslado \| idSolicitud, punto, cantidadSube }` |
| POST | `traslados/progreso` | `{ idTraslado }` |

Todas devuelven `FOR JSON PATH` como el resto de endpoints; el frontend ya
aplana la respuesta con `unwrap()` y encola mutaciones offline con
`idOperacion` (idempotencia: el SP debe ignorar un `idOperacion` repetido).

## 6. Cambios en el frontend (resumen)

- **`Parada` (models)**: agregar `estado`, `horaLlegada`, `horaSalida`,
  `subieronReal`, `bajaronReal`, `motivoOmision`, `detalle`.
- **Coordinador**: botón "Generar ruta sugerida" en el editor; vista de
  progreso por traslado (timeline con estado/hora/a-bordo); polling.
- **Conductor**: las paradas pasan de tabla de solo lectura a checklist:
  botón "Llegué" en la parada actual → formulario suben/bajan prellenado →
  "Confirmar y seguir". Enviar GPS al marcar.
- **TransporteService**: métodos `llegadaParada`, `registrarParada`,
  `omitirParada`, `progresoTraslado` (usan `mutar`, así quedan offline).

## 7. Casos borde

- **Parada compartida**: mismo punto es llegada de una solicitud y partida de
  otra → una sola `Parada` con detalles `B` y `S`.
- **Solicitud anulada en ruta**: sus detalles quedan en 0; los conteos reales
  no se alteran retroactivamente.
- **Multi-unidad (MULTIPLE)**: cada porción lleva su propio traslado/ruta;
  con la recomendación de 4.6 cada `idSolicitudUnidad` genera su traslado.
- **Parada sin movimiento** (punto de control/peaje): permitida con 0/0.
- **Reloj del dispositivo**: `horaCliente` puede venir desfasado; guardar
  también `fechaRegistro` del servidor para auditoría.
