/* ============================================================
   018 — Catálogo de centros de costo + previa/edición de la OS
   - TP_CECOS: ceco con su imputación completa (cuenta, proyecto, fundo, cultivo, labor)
   - administrarCatalogo: entidad CECO
   - TRANSPORTE_generarOS: soporta { previa: true } (simula sin grabar)
     y { detalle: [{idTransportista,idArea,idCeco}] } (cecos elegidos)
   Ejecutar con: sqlcmd -f 65001 (UTF-8)
   ============================================================ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID('TP_CECOS') IS NULL
CREATE TABLE TP_CECOS (
    idCeco      INT IDENTITY(1,1) PRIMARY KEY,
    ceco        NVARCHAR(20) NOT NULL,
    cuenta      NVARCHAR(30) NULL,
    idproyecto  NVARCHAR(20) NULL,
    codfundo    NVARCHAR(20) NULL,
    idcultivo   NVARCHAR(10) NULL,
    idlabor     NVARCHAR(10) NULL,
    descripcion NVARCHAR(120) NULL,
    activo      BIT NOT NULL DEFAULT 1
);
GO

CREATE OR ALTER PROCEDURE TRANSPORTE_administrarCatalogo
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @entidad NVARCHAR(20) = UPPER(JSON_VALUE(@json, '$.entidad'));
    DECLARE @accion NVARCHAR(20) = UPPER(JSON_VALUE(@json, '$.accion'));
    DECLARE @id INT = TRY_CAST(JSON_VALUE(@json, '$.id') AS INT);
    DECLARE @actor NVARCHAR(50) = COALESCE(JSON_VALUE(@json, '$.actor'), JSON_VALUE(@json, '$.usuario'));
    IF @accion <> 'LISTAR' INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle) VALUES(@entidad,@id,@accion,@actor,@json);
    IF @entidad = 'PUNTO'
    BEGIN
        IF @accion = 'GUARDAR'
            IF @id IS NULL INSERT INTO TP_PUNTOS(nombre, latitud, longitud) VALUES(JSON_VALUE(@json, '$.nombre'), TRY_CAST(JSON_VALUE(@json, '$.latitud') AS DECIMAL(9,6)), TRY_CAST(JSON_VALUE(@json, '$.longitud') AS DECIMAL(9,6)));
            ELSE UPDATE TP_PUNTOS SET nombre = JSON_VALUE(@json, '$.nombre'), latitud = TRY_CAST(JSON_VALUE(@json, '$.latitud') AS DECIMAL(9,6)), longitud = TRY_CAST(JSON_VALUE(@json, '$.longitud') AS DECIMAL(9,6)), activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo) WHERE idPunto = @id;
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_PUNTOS SET activo = 0 WHERE idPunto = @id;
        SELECT idPunto, nombre, latitud, longitud, activo FROM TP_PUNTOS ORDER BY nombre FOR JSON PATH; RETURN;
    END
    IF @entidad = 'MOTIVO'
    BEGIN
        IF @accion = 'GUARDAR'
            IF @id IS NULL INSERT INTO TP_MOTIVOS(nombre) VALUES(JSON_VALUE(@json, '$.nombre'));
            ELSE UPDATE TP_MOTIVOS SET nombre = JSON_VALUE(@json, '$.nombre'), activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo) WHERE idMotivo = @id;
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_MOTIVOS SET activo = 0 WHERE idMotivo = @id;
        SELECT idMotivo, nombre, activo FROM TP_MOTIVOS ORDER BY nombre FOR JSON PATH; RETURN;
    END
    IF @entidad = 'AREA'
    BEGIN
        IF @accion = 'GUARDAR'
            IF @id IS NULL INSERT INTO TP_AREAS(nombre, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor)
                VALUES(JSON_VALUE(@json, '$.nombre'), JSON_VALUE(@json, '$.ceco'), JSON_VALUE(@json, '$.cuenta'),
                       JSON_VALUE(@json, '$.idproyecto'), JSON_VALUE(@json, '$.codfundo'),
                       JSON_VALUE(@json, '$.idcultivo'), JSON_VALUE(@json, '$.idlabor'));
            ELSE UPDATE TP_AREAS SET nombre = JSON_VALUE(@json, '$.nombre'),
                 ceco = JSON_VALUE(@json, '$.ceco'), cuenta = JSON_VALUE(@json, '$.cuenta'),
                 idproyecto = JSON_VALUE(@json, '$.idproyecto'), codfundo = JSON_VALUE(@json, '$.codfundo'),
                 idcultivo = JSON_VALUE(@json, '$.idcultivo'), idlabor = JSON_VALUE(@json, '$.idlabor'),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo) WHERE idArea = @id;
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_AREAS SET activo = 0 WHERE idArea = @id;
        SELECT idArea, nombre, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, activo
        FROM TP_AREAS ORDER BY nombre FOR JSON PATH; RETURN;
    END
    IF @entidad = 'CECO'
    BEGIN
        IF @accion = 'GUARDAR'
        BEGIN
            IF JSON_VALUE(@json, '$.ceco') IS NULL
            BEGIN RAISERROR(N'El centro de costo es obligatorio',16,1); RETURN; END
            IF @id IS NULL AND EXISTS(SELECT 1 FROM TP_CECOS WHERE ceco = JSON_VALUE(@json, '$.ceco'))
            BEGIN RAISERROR(N'Ya existe un centro de costo con ese código',16,1); RETURN; END
            IF @id IS NULL INSERT INTO TP_CECOS(ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, descripcion)
                VALUES(JSON_VALUE(@json, '$.ceco'), JSON_VALUE(@json, '$.cuenta'), JSON_VALUE(@json, '$.idproyecto'),
                       JSON_VALUE(@json, '$.codfundo'), JSON_VALUE(@json, '$.idcultivo'), JSON_VALUE(@json, '$.idlabor'),
                       JSON_VALUE(@json, '$.descripcion'));
            ELSE UPDATE TP_CECOS SET ceco = JSON_VALUE(@json, '$.ceco'), cuenta = JSON_VALUE(@json, '$.cuenta'),
                 idproyecto = JSON_VALUE(@json, '$.idproyecto'), codfundo = JSON_VALUE(@json, '$.codfundo'),
                 idcultivo = JSON_VALUE(@json, '$.idcultivo'), idlabor = JSON_VALUE(@json, '$.idlabor'),
                 descripcion = JSON_VALUE(@json, '$.descripcion'),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo)
                 WHERE idCeco = @id;
        END
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_CECOS SET activo = 0 WHERE idCeco = @id;
        SELECT idCeco, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, descripcion, activo
        FROM TP_CECOS ORDER BY ceco FOR JSON PATH; RETURN;
    END
    IF @entidad = 'UNIDAD'
    BEGIN
        IF @accion = 'GUARDAR'
            IF @id IS NULL INSERT INTO TP_UNIDADES(placa, capacidad, idTransportista)
                VALUES(JSON_VALUE(@json, '$.placa'), TRY_CAST(JSON_VALUE(@json, '$.capacidad') AS INT),
                       TRY_CAST(JSON_VALUE(@json, '$.idTransportista') AS INT));
            ELSE UPDATE TP_UNIDADES SET placa = JSON_VALUE(@json, '$.placa'),
                 capacidad = TRY_CAST(JSON_VALUE(@json, '$.capacidad') AS INT),
                 idTransportista = TRY_CAST(JSON_VALUE(@json, '$.idTransportista') AS INT),
                 activa = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activa) WHERE idUnidad = @id;
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_UNIDADES SET activa = 0 WHERE idUnidad = @id;
        SELECT u.idUnidad, u.placa, u.capacidad, u.idTransportista, t.razonSocial AS transportista, u.activa AS activo
        FROM TP_UNIDADES u LEFT JOIN TP_TRANSPORTISTAS t ON t.idTransportista = u.idTransportista
        ORDER BY u.placa FOR JSON PATH; RETURN;
    END
    IF @entidad = 'TRANSPORTISTA'
    BEGIN
        IF @accion = 'GUARDAR'
        BEGIN
            IF @id IS NULL AND EXISTS(SELECT 1 FROM TP_TRANSPORTISTAS WHERE ruc = JSON_VALUE(@json, '$.ruc'))
            BEGIN RAISERROR(N'Ya existe un transportista con ese RUC',16,1); RETURN; END
            IF @id IS NULL INSERT INTO TP_TRANSPORTISTAS(ruc, razonSocial, telefono, email)
                VALUES(JSON_VALUE(@json, '$.ruc'), JSON_VALUE(@json, '$.razonSocial'),
                       JSON_VALUE(@json, '$.telefono'), JSON_VALUE(@json, '$.email'));
            ELSE UPDATE TP_TRANSPORTISTAS SET ruc = JSON_VALUE(@json, '$.ruc'),
                 razonSocial = JSON_VALUE(@json, '$.razonSocial'), telefono = JSON_VALUE(@json, '$.telefono'),
                 email = JSON_VALUE(@json, '$.email'),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo)
                 WHERE idTransportista = @id;
        END
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_TRANSPORTISTAS SET activo = 0 WHERE idTransportista = @id;
        SELECT idTransportista, ruc, razonSocial, telefono, email, activo
        FROM TP_TRANSPORTISTAS ORDER BY razonSocial FOR JSON PATH; RETURN;
    END
    IF @entidad = 'TARIFA'
    BEGIN
        IF @accion = 'GUARDAR'
        BEGIN
            IF JSON_VALUE(@json, '$.idTransportista') IS NULL OR TRY_CAST(JSON_VALUE(@json, '$.monto') AS DECIMAL(12,2)) IS NULL
            BEGIN RAISERROR(N'Transportista y monto son obligatorios',16,1); RETURN; END
            IF @id IS NULL INSERT INTO TP_TARIFAS(idTransportista, puntoOrigen, puntoDestino, monto, porPasajero)
                VALUES(TRY_CAST(JSON_VALUE(@json, '$.idTransportista') AS INT),
                       NULLIF(JSON_VALUE(@json, '$.puntoOrigen'), ''), NULLIF(JSON_VALUE(@json, '$.puntoDestino'), ''),
                       TRY_CAST(JSON_VALUE(@json, '$.monto') AS DECIMAL(12,2)),
                       COALESCE(TRY_CAST(JSON_VALUE(@json, '$.porPasajero') AS BIT), 0));
            ELSE UPDATE TP_TARIFAS SET idTransportista = TRY_CAST(JSON_VALUE(@json, '$.idTransportista') AS INT),
                 puntoOrigen = NULLIF(JSON_VALUE(@json, '$.puntoOrigen'), ''),
                 puntoDestino = NULLIF(JSON_VALUE(@json, '$.puntoDestino'), ''),
                 monto = TRY_CAST(JSON_VALUE(@json, '$.monto') AS DECIMAL(12,2)),
                 porPasajero = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.porPasajero') AS BIT), porPasajero),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo)
                 WHERE idTarifa = @id;
        END
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_TARIFAS SET activo = 0 WHERE idTarifa = @id;
        SELECT tf.idTarifa, tf.idTransportista, t.razonSocial AS transportista,
               tf.puntoOrigen, tf.puntoDestino, tf.monto, tf.porPasajero, tf.activo
        FROM TP_TARIFAS tf JOIN TP_TRANSPORTISTAS t ON t.idTransportista = tf.idTransportista
        ORDER BY t.razonSocial, tf.puntoOrigen FOR JSON PATH; RETURN;
    END
    IF @entidad = 'USUARIO'
    BEGIN
        DECLARE @idAreaU INT = TRY_CAST(JSON_VALUE(@json, '$.idArea') AS INT);
        DECLARE @areaNombre NVARCHAR(100) = COALESCE(
            (SELECT nombre FROM TP_AREAS WHERE idArea = @idAreaU),
            JSON_VALUE(@json, '$.area'));
        DECLARE @rolSol NVARCHAR(10) = JSON_VALUE(@json, '$.rolSolicitante');
        DECLARE @idrolNuevo NVARCHAR(10) = JSON_VALUE(@json, '$.idrol');
        DECLARE @usuarioNuevo NVARCHAR(50) = JSON_VALUE(@json, '$.usuario');
        DECLARE @rolObj NVARCHAR(10), @usuarioObj NVARCHAR(50), @eliminadoObj BIT, @placaObj NVARCHAR(20);
        IF @id IS NOT NULL
            SELECT @rolObj = idrol, @usuarioObj = usuario, @eliminadoObj = eliminado, @placaObj = placa
            FROM TP_USUARIOS WHERE idUsuario = @id;
        IF @accion = 'GUARDAR'
        BEGIN
            -- un coordinador solo gestiona conductores y supervisores
            IF @rolSol = 'COTRANS' AND (@idrolNuevo IS NULL OR @idrolNuevo NOT IN ('CHTRANS','SPTRANS')
                OR (@id IS NOT NULL AND @rolObj NOT IN ('CHTRANS','SPTRANS')))
            BEGIN RAISERROR(N'El coordinador solo puede gestionar conductores y supervisores',16,1); RETURN; END
            IF @id IS NOT NULL AND @eliminadoObj = 1
            BEGIN RAISERROR(N'El usuario esta eliminado; no se puede editar',16,1); RETURN; END
            IF @id IS NULL AND EXISTS(SELECT 1 FROM TP_USUARIOS WHERE usuario = @usuarioNuevo)
            BEGIN RAISERROR(N'Ya existe un usuario con ese nombre de acceso',16,1); RETURN; END
            IF @id IS NULL INSERT INTO TP_USUARIOS(usuario, claveHash, nombre, idrol, placa, area, idArea, dni)
                VALUES(@usuarioNuevo, JSON_VALUE(@json, '$.claveHash'),
                       JSON_VALUE(@json, '$.nombre'), @idrolNuevo, JSON_VALUE(@json, '$.placa'), @areaNombre, @idAreaU,
                       JSON_VALUE(@json, '$.dni'));
            ELSE UPDATE TP_USUARIOS SET nombre = JSON_VALUE(@json, '$.nombre'), idrol = @idrolNuevo,
                 placa = JSON_VALUE(@json, '$.placa'), area = @areaNombre, idArea = @idAreaU,
                 dni = JSON_VALUE(@json, '$.dni'),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo),
                 claveHash = COALESCE(NULLIF(JSON_VALUE(@json, '$.claveHash'), ''), claveHash)
                 WHERE idUsuario = @id;
        END
        ELSE IF @accion = 'ELIMINAR'
        BEGIN
            IF @id IS NULL OR @rolObj IS NULL
            BEGIN RAISERROR(N'Usuario no encontrado',16,1); RETURN; END
            IF @eliminadoObj = 1
            BEGIN RAISERROR(N'El usuario ya esta eliminado',16,1); RETURN; END
            IF @usuarioObj = @actor
            BEGIN RAISERROR(N'No puede eliminar su propio usuario',16,1); RETURN; END
            IF @rolSol = 'COTRANS' AND @rolObj NOT IN ('CHTRANS','SPTRANS')
            BEGIN RAISERROR(N'El coordinador solo puede eliminar conductores y supervisores',16,1); RETURN; END
            -- conductor con traslados activos no se puede eliminar
            IF @rolObj = 'CHTRANS' AND @placaObj IS NOT NULL AND EXISTS(
                SELECT 1 FROM TP_TRASLADOS t WHERE t.placa = @placaObj AND t.estado IN ('PENDIENTE','ASIGNADO','EN_RUTA'))
            BEGIN RAISERROR(N'El conductor tiene traslados activos; no se puede eliminar',16,1); RETURN; END
            -- supervisor con solicitudes activas no se puede eliminar
            IF @rolObj = 'SPTRANS' AND EXISTS(
                SELECT 1 FROM TP_SOLICITUDES s WHERE s.usuarioRegistra = @usuarioObj AND s.estado IN ('PENDIENTE','ASIGNADO','EN_RUTA'))
            BEGIN RAISERROR(N'El supervisor tiene solicitudes activas; no se puede eliminar',16,1); RETURN; END
            UPDATE TP_USUARIOS SET eliminado = 1, activo = 0,
                fechaEliminado = GETDATE(), usuarioElimina = @actor
                WHERE idUsuario = @id;
        END
        -- LISTAR: el coordinador solo ve conductores y supervisores
        SELECT idUsuario, usuario, nombre, idrol, placa, area, idArea, dni, activo, eliminado, fechaEliminado, usuarioElimina
        FROM TP_USUARIOS
        WHERE (@rolSol <> 'COTRANS' OR @rolSol IS NULL OR idrol IN ('CHTRANS','SPTRANS'))
        ORDER BY nombre FOR JSON PATH; RETURN;
    END
    RAISERROR(N'Entidad administrativa invalida', 16, 1);
END
GO

/* Genera (o simula con previa:1) las OS del período: una por transportista.
   detalle opcional: [{"idTransportista":N,"idArea":N,"idCeco":N}] — cecos elegidos. */
CREATE OR ALTER PROCEDURE TRANSPORTE_generarOS
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @desde DATE = TRY_CAST(JSON_VALUE(@json,'$.desde') AS DATE);
    DECLARE @hasta DATE = TRY_CAST(JSON_VALUE(@json,'$.hasta') AS DATE);
    DECLARE @usuario NVARCHAR(50) = JSON_VALUE(@json,'$.usuario');
    DECLARE @dni NVARCHAR(15) = JSON_VALUE(@json,'$.usuarioGenera');
    DECLARE @idOperacion NVARCHAR(64) = JSON_VALUE(@json,'$.idOperacion');
    DECLARE @previa BIT = COALESCE(TRY_CAST(JSON_VALUE(@json,'$.previa') AS BIT), 0);
    -- Si no llega el DNI, se resuelve desde la cuenta del usuario que genera
    IF @dni IS NULL SET @dni = (SELECT dni FROM TP_USUARIOS WHERE usuario = @usuario);

    IF @desde IS NULL OR @hasta IS NULL
    BEGIN RAISERROR(N'Las fechas desde y hasta son obligatorias',16,1); RETURN; END

    -- Idempotencia: misma operación devuelve las OS ya creadas (no aplica a previa)
    IF @previa = 0 AND @idOperacion IS NOT NULL AND EXISTS(SELECT 1 FROM TP_ORDENES_SERVICIO WHERE idOperacion = @idOperacion)
    BEGIN
        SELECT (SELECT o.*, (SELECT d.* FROM TP_OS_DETALLE d WHERE d.idOS = o.idOS FOR JSON PATH) AS detalle
                FROM TP_ORDENES_SERVICIO o WHERE o.idOperacion = @idOperacion
                ORDER BY o.idOS FOR JSON PATH) AS ordenes,
               JSON_QUERY('[]') AS excluidos
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    DECLARE @rucEmpresa NVARCHAR(11) = (SELECT valor FROM TP_PARAMETROS WHERE clave='RUC_EMPRESA');
    DECLARE @idEmpresa NVARCHAR(20)  = (SELECT valor FROM TP_PARAMETROS WHERE clave='ID_EMPRESA');

    -- Overrides de ceco elegidos por el coordinador en la previa
    SELECT idTransportista, idArea, idCeco INTO #OVR
    FROM OPENJSON(JSON_QUERY(@json,'$.detalle'))
    WITH (idTransportista INT '$.idTransportista', idArea INT '$.idArea', idCeco INT '$.idCeco');

    -- Pasajeros reales por solicitud (subidas registradas en paradas; si no hay, lo planificado)
    SELECT s.idSolicitud, s.idTraslado, s.idArea, s.area,
           ISNULL((SELECT SUM(d.cantidadReal) FROM TP_PARADA_DETALLE d
                   JOIN TP_TRASLADO_PARADAS p ON p.idParada = d.idParada
                   WHERE p.idTraslado = s.idTraslado AND d.idSolicitud = s.idSolicitud AND d.tipo = 'B'),
                  s.cantidad) AS pasajeros
    INTO #PAX
    FROM TP_SOLICITUDES s
    WHERE s.estado = 'REALIZADO';

    -- Traslados elegibles: realizados en el período y aún no incluidos en una OS
    SELECT t.idTraslado, t.placa, u.idTransportista, tr.ruc, tr.razonSocial,
           LTRIM(RTRIM(LEFT(t.ruta, CASE WHEN CHARINDEX('>',t.ruta) > 0 THEN CHARINDEX('>',t.ruta)-1 ELSE LEN(t.ruta) END))) AS origen,
           LTRIM(RTRIM(REVERSE(LEFT(REVERSE(t.ruta), CASE WHEN CHARINDEX('>',REVERSE(t.ruta)) > 0 THEN CHARINDEX('>',REVERSE(t.ruta))-1 ELSE LEN(t.ruta) END)))) AS destino,
           ISNULL(px.pasajeros,0) AS pasajeros,
           CAST(NULL AS DECIMAL(12,2)) AS tarifa,
           CAST(NULL AS DECIMAL(18,6)) AS costo
    INTO #TR
    FROM TP_TRASLADOS t
    JOIN TP_UNIDADES u ON u.placa = t.placa
    LEFT JOIN TP_TRANSPORTISTAS tr ON tr.idTransportista = u.idTransportista
    OUTER APPLY (SELECT SUM(x.pasajeros) AS pasajeros FROM #PAX x WHERE x.idTraslado = t.idTraslado) px
    WHERE t.estado = 'REALIZADO'
      AND NOT EXISTS (SELECT 1 FROM TP_OS_TRASLADOS ot WHERE ot.idTraslado = t.idTraslado)
      AND (SELECT MAX(COALESCE(s.fechaFin, s.fechaProgramada)) FROM TP_SOLICITUDES s
           WHERE s.idTraslado = t.idTraslado AND s.estado = 'REALIZADO') BETWEEN @desde AND DATEADD(day,1,@hasta);

    -- Tarifa por traslado: match exacto ruta, luego parcial, luego default (origen/destino NULL)
    UPDATE x SET tarifa = tf.monto,
        costo = CASE WHEN tf.porPasajero = 1 THEN tf.monto * x.pasajeros ELSE tf.monto END
    FROM #TR x
    OUTER APPLY (
        SELECT TOP 1 monto, porPasajero FROM TP_TARIFAS tf
        WHERE tf.idTransportista = x.idTransportista AND tf.activo = 1
          AND (tf.puntoOrigen  IS NULL OR tf.puntoOrigen  = x.origen)
          AND (tf.puntoDestino IS NULL OR tf.puntoDestino = x.destino)
        ORDER BY (CASE WHEN tf.puntoOrigen  IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN tf.puntoDestino IS NOT NULL THEN 1 ELSE 0 END) DESC
    ) tf;

    -- Resumen de lo no facturable para devolverlo como advertencia
    SELECT placa, origen, destino,
           CASE WHEN idTransportista IS NULL THEN 'SIN_TRANSPORTISTA' ELSE 'SIN_TARIFA' END AS motivo
    INTO #EXCLUIDOS FROM #TR WHERE idTransportista IS NULL OR tarifa IS NULL;

    -- Grupos por transportista
    SELECT idTransportista, MIN(ruc) AS ruc, MIN(razonSocial) AS razonSocial,
           COUNT(*) AS viajes, ISNULL(SUM(pasajeros),0) AS pax, ISNULL(SUM(costo),0) AS totalTarifa
    INTO #G FROM #TR WHERE idTransportista IS NOT NULL AND tarifa IS NOT NULL
    GROUP BY idTransportista;

    -- Detalle resuelto por grupo y área: ceco del override elegido, si no el del área
    SELECT t.idTransportista, px.idArea, px.area,
           COALESCE(cc.idCeco, def.idCeco) AS idCeco,
           COALESCE(cc.ceco, a.ceco) AS ceco,
           COALESCE(cc.cuenta, a.cuenta) AS cuenta,
           COALESCE(cc.idproyecto, a.idproyecto) AS idproyecto,
           COALESCE(cc.codfundo, a.codfundo) AS codfundo,
           COALESCE(cc.idcultivo, a.idcultivo) AS idcultivo,
           COALESCE(cc.idlabor, a.idlabor) AS idlabor,
           SUM(px.pasajeros) AS cantidad,
           ROUND(g.totalTarifa * SUM(px.pasajeros) / NULLIF(g.pax,0), 6) AS costo
    INTO #OSDET
    FROM #PAX px
    JOIN #TR t ON t.idTraslado = px.idTraslado AND t.tarifa IS NOT NULL
    JOIN #G g ON g.idTransportista = t.idTransportista
    LEFT JOIN TP_AREAS a ON a.idArea = px.idArea
    LEFT JOIN #OVR o ON o.idTransportista = t.idTransportista AND (o.idArea = px.idArea OR (o.idArea IS NULL AND px.idArea IS NULL))
    LEFT JOIN TP_CECOS cc ON cc.idCeco = o.idCeco
    LEFT JOIN TP_CECOS def ON def.ceco = a.ceco AND def.activo = 1
    WHERE g.pax > 0
    GROUP BY t.idTransportista, px.idArea, px.area, cc.idCeco, def.idCeco, cc.ceco, a.ceco,
             cc.cuenta, a.cuenta, cc.idproyecto, a.idproyecto, cc.codfundo, a.codfundo,
             cc.idcultivo, a.idcultivo, cc.idlabor, a.idlabor, g.totalTarifa, g.pax;

    -- Previa: devuelve lo que se generaría sin grabar nada
    IF @previa = 1
    BEGIN
        SELECT (SELECT g.idTransportista, g.razonSocial AS nombreTransportista, g.ruc AS rucTransportista,
                       g.viajes AS totalViajes, g.pax AS totalPasajeros, g.totalTarifa,
                       ROUND(g.totalTarifa*0.18,2) AS igvTotalTarifa,
                       (SELECT d.* FROM #OSDET d WHERE d.idTransportista = g.idTransportista FOR JSON PATH) AS detalle
                FROM #G g ORDER BY g.idTransportista FOR JSON PATH) AS ordenes,
               (SELECT * FROM #EXCLUIDOS FOR JSON PATH) AS excluidos
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    -- Toda fila del detalle debe tener ceco, cuenta y proyecto antes de generar
    IF EXISTS (SELECT 1 FROM #OSDET WHERE ceco IS NULL OR cuenta IS NULL OR idproyecto IS NULL)
    BEGIN
        DECLARE @faltantes NVARCHAR(MAX) = STUFF((SELECT DISTINCT ', ' + area FROM #OSDET
            WHERE ceco IS NULL OR cuenta IS NULL OR idproyecto IS NULL
            FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)'), 1, 2, '');
        RAISERROR(N'Falta centro de costo, cuenta o proyecto para: %s. Elija el ceco en la previa.', 16, 1, @faltantes);
        RETURN;
    END
    -- y toda OS debe llevar distribución por área (sin distribución = sin ceco)
    IF EXISTS (SELECT 1 FROM #G g WHERE NOT EXISTS (SELECT 1 FROM #OSDET d WHERE d.idTransportista = g.idTransportista))
    BEGIN
        DECLARE @sinDet NVARCHAR(MAX) = STUFF((SELECT ', ' + razonSocial FROM #G g
            WHERE NOT EXISTS (SELECT 1 FROM #OSDET d WHERE d.idTransportista = g.idTransportista)
            FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)'), 1, 2, '');
        RAISERROR(N'No se pudo distribuir el costo por área para: %s', 16, 1, @sinDet);
        RETURN;
    END

    BEGIN TRAN;
    DECLARE @idT INT, @idOS INT, @viajes INT, @pax INT, @tarifa DECIMAL(14,2), @rucT NVARCHAR(11), @razT NVARCHAR(150);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT idTransportista, ruc, razonSocial, viajes, pax, totalTarifa FROM #G;
    OPEN cur;
    FETCH NEXT FROM cur INTO @idT, @rucT, @razT, @viajes, @pax, @tarifa;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO TP_ORDENES_SERVICIO(fechaDesde, fechaHasta, fechaProceso, idTransportista,
            rucTransportista, nombreTransportista, totalViajes, totalPasajeros, totalTarifa, igvTotalTarifa,
            usuarioGenera, usuario, idOperacion)
        VALUES(@desde, @hasta, @hasta, @idT, @rucT, @razT, @viajes, @pax, @tarifa,
            ROUND(@tarifa * 0.18, 2), @dni, @usuario, @idOperacion);
        SET @idOS = SCOPE_IDENTITY();

        -- Detalle: costo por area con el ceco elegido (o el del area)
        INSERT INTO TP_OS_DETALLE(idOS, idArea, area, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, cantidad, costo)
        SELECT @idOS, idArea, area, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, cantidad, costo
        FROM #OSDET WHERE idTransportista = @idT;

        INSERT INTO TP_OS_TRASLADOS(idOS, idTraslado)
            SELECT @idOS, idTraslado FROM #TR WHERE idTransportista = @idT AND tarifa IS NOT NULL;

        -- Payload listo para logistica (contrato orden-servicio/ingresar-transporte)
        UPDATE o SET payloadEnvio = (
            SELECT @idEmpresa AS idempresa, @rucEmpresa AS ruc_empresa, @rucT AS ruc_transportista,
                   @viajes AS total_viajes, @tarifa AS total_tarifa, ROUND(@tarifa*0.18,2) AS igv_total_tarifa,
                   CONVERT(NVARCHAR(10),@hasta,120) AS fechaProceso, @dni AS usuario,
                   CONVERT(NVARCHAR(10),@desde,120) AS fechaInicioServicio,
                   CONVERT(NVARCHAR(10),@hasta,120) AS fechaFinServicio,
                   (SELECT @rucT AS ruc_transportista, d.idcultivo, d.idproyecto, d.ceco,
                           d.cantidad AS TotalHoras, d.idlabor, d.cuenta, d.codfundo, d.costo
                    FROM TP_OS_DETALLE d WHERE d.idOS = @idOS FOR JSON PATH) AS detalle
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM TP_ORDENES_SERVICIO o WHERE o.idOS = @idOS;

        FETCH NEXT FROM cur INTO @idT, @rucT, @razT, @viajes, @pax, @tarifa;
    END
    CLOSE cur; DEALLOCATE cur;
    COMMIT;

    SELECT (SELECT o.*, (SELECT d.* FROM TP_OS_DETALLE d WHERE d.idOS = o.idOS FOR JSON PATH) AS detalle
            FROM TP_ORDENES_SERVICIO o
            WHERE o.idOperacion = @idOperacion OR (o.idOperacion IS NULL AND o.fechaGeneracion >= DATEADD(minute,-1,GETDATE()) AND o.fechaDesde=@desde AND o.fechaHasta=@hasta)
            ORDER BY o.idOS FOR JSON PATH) AS ordenes,
           (SELECT * FROM #EXCLUIDOS FOR JSON PATH) AS excluidos
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO
