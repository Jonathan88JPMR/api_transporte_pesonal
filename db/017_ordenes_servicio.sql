/* ============================================================
   017 — Órdenes de Servicio (OS) con migración a logística/SPRING
   - TP_ORDENES_SERVICIO: una OS por transportista por período
   - TP_OS_DETALLE: distribución del costo por área (ceco/cuenta/proyecto)
   - TP_OS_TRASLADOS: traslados incluidos (evita duplicar en otra OS)
   - TRANSPORTE_generarOS: genera OS desde traslados REALIZADO
   - TRANSPORTE_listarOS / TRANSPORTE_marcarOS
   Ejecutar con: sqlcmd -f 65001 (UTF-8)
   ============================================================ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

IF OBJECT_ID('TP_ORDENES_SERVICIO') IS NULL
CREATE TABLE TP_ORDENES_SERVICIO (
    idOS                INT IDENTITY(1,1) PRIMARY KEY,
    fechaDesde          DATE NOT NULL,
    fechaHasta          DATE NOT NULL,
    fechaProceso        DATE NOT NULL,
    idTransportista     INT NOT NULL REFERENCES TP_TRANSPORTISTAS(idTransportista),
    rucTransportista    NVARCHAR(11)  NOT NULL,
    nombreTransportista NVARCHAR(150) NOT NULL,
    totalViajes         INT NOT NULL DEFAULT 0,
    totalPasajeros      INT NOT NULL DEFAULT 0,
    totalTarifa         DECIMAL(14,2) NOT NULL DEFAULT 0,
    igvTotalTarifa      DECIMAL(14,2) NOT NULL DEFAULT 0,
    estado              NVARCHAR(20) NOT NULL DEFAULT 'GENERADA', -- GENERADA|MIGRADA|ERROR
    payloadEnvio        NVARCHAR(MAX) NULL,
    respuesta           NVARCHAR(MAX) NULL,
    numeroOSExterno     NVARCHAR(50) NULL,
    intentos            INT NOT NULL DEFAULT 0,
    ultimoError         NVARCHAR(500) NULL,
    usuarioGenera       NVARCHAR(15) NULL,   -- dni del coordinador
    usuario             NVARCHAR(50) NULL,   -- usuario del sistema
    idOperacion         NVARCHAR(64) NULL,   -- idempotencia del cliente
    fechaGeneracion     DATETIME NOT NULL DEFAULT GETDATE(),
    fechaMigracion      DATETIME NULL
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_OS_Operacion' AND object_id = OBJECT_ID('TP_ORDENES_SERVICIO'))
    CREATE UNIQUE INDEX UX_OS_Operacion ON TP_ORDENES_SERVICIO(idOperacion) WHERE idOperacion IS NOT NULL;

IF OBJECT_ID('TP_OS_DETALLE') IS NULL
CREATE TABLE TP_OS_DETALLE (
    idDetalle   INT IDENTITY(1,1) PRIMARY KEY,
    idOS        INT NOT NULL REFERENCES TP_ORDENES_SERVICIO(idOS),
    idArea      INT NULL,
    area        NVARCHAR(100) NULL,
    ceco        NVARCHAR(20) NULL,
    cuenta      NVARCHAR(30) NULL,
    idproyecto  NVARCHAR(20) NULL,
    codfundo    NVARCHAR(20) NULL,
    idcultivo   NVARCHAR(10) NULL,
    idlabor     NVARCHAR(10) NULL,
    cantidad    INT NOT NULL DEFAULT 0,  -- pasajeros transportados (peso de distribución)
    costo       DECIMAL(18,6) NOT NULL DEFAULT 0
);

IF OBJECT_ID('TP_OS_TRASLADOS') IS NULL
CREATE TABLE TP_OS_TRASLADOS (
    idOS       INT NOT NULL REFERENCES TP_ORDENES_SERVICIO(idOS),
    idTraslado INT NOT NULL REFERENCES TP_TRASLADOS(idTraslado),
    PRIMARY KEY (idOS, idTraslado)
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_OS_Traslado' AND object_id = OBJECT_ID('TP_OS_TRASLADOS'))
    CREATE UNIQUE INDEX UX_OS_Traslado ON TP_OS_TRASLADOS(idTraslado); -- un traslado solo entra a una OS
GO

/* Genera las OS del período: una por transportista. Solo toma traslados
   REALIZADO cuyo servicio cayó en [desde,hasta] y que no estén ya en otra OS. */
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
    -- Si no llega el DNI, se resuelve desde la cuenta del usuario que genera
    IF @dni IS NULL SET @dni = (SELECT dni FROM TP_USUARIOS WHERE usuario = @usuario);

    IF @desde IS NULL OR @hasta IS NULL
    BEGIN RAISERROR(N'Las fechas desde y hasta son obligatorias',16,1); RETURN; END

    -- Idempotencia: misma operación devuelve las OS ya creadas
    IF @idOperacion IS NOT NULL AND EXISTS(SELECT 1 FROM TP_ORDENES_SERVICIO WHERE idOperacion = @idOperacion)
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

    BEGIN TRAN;
    DECLARE @idT INT, @idOS INT, @viajes INT, @pax INT, @tarifa DECIMAL(14,2), @rucT NVARCHAR(11), @razT NVARCHAR(150);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT idTransportista, MIN(ruc), MIN(razonSocial), COUNT(*), ISNULL(SUM(pasajeros),0), ISNULL(SUM(costo),0)
        FROM #TR WHERE idTransportista IS NOT NULL AND tarifa IS NOT NULL
        GROUP BY idTransportista;
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

        -- Detalle: costo distribuido por área proporcional a pasajeros
        IF @pax > 0
            INSERT INTO TP_OS_DETALLE(idOS, idArea, area, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, cantidad, costo)
            SELECT @idOS, px.idArea, px.area, a.ceco, a.cuenta, a.idproyecto, a.codfundo, a.idcultivo, a.idlabor,
                   SUM(px.pasajeros), ROUND(@tarifa * SUM(px.pasajeros) / @pax, 6)
            FROM #PAX px JOIN #TR t ON t.idTraslado = px.idTraslado
            LEFT JOIN TP_AREAS a ON a.idArea = px.idArea
            WHERE t.idTransportista = @idT AND t.tarifa IS NOT NULL
            GROUP BY px.idArea, px.area, a.ceco, a.cuenta, a.idproyecto, a.codfundo, a.idcultivo, a.idlabor;
        ELSE
            INSERT INTO TP_OS_DETALLE(idOS, area, cantidad, costo) VALUES(@idOS, 'SIN DISTRIBUCION', @viajes, @tarifa);

        INSERT INTO TP_OS_TRASLADOS(idOS, idTraslado)
            SELECT @idOS, idTraslado FROM #TR WHERE idTransportista = @idT AND tarifa IS NOT NULL;

        -- Payload listo para logística (mismo contrato que orden-servicio/ingresar-transporte)
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

CREATE OR ALTER PROCEDURE TRANSPORTE_listarOS
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @desde DATE = TRY_CAST(JSON_VALUE(@json,'$.desde') AS DATE);
    DECLARE @hasta DATE = TRY_CAST(JSON_VALUE(@json,'$.hasta') AS DATE);
    DECLARE @estado NVARCHAR(20) = JSON_VALUE(@json,'$.estado');
    DECLARE @idOS INT = TRY_CAST(JSON_VALUE(@json,'$.idOS') AS INT);
    SELECT o.*, (SELECT d.* FROM TP_OS_DETALLE d WHERE d.idOS = o.idOS FOR JSON PATH) AS detalle,
           (SELECT ot.idTraslado, tr.placa, tr.ruta FROM TP_OS_TRASLADOS ot
            JOIN TP_TRASLADOS tr ON tr.idTraslado = ot.idTraslado
            WHERE ot.idOS = o.idOS FOR JSON PATH) AS traslados
    FROM TP_ORDENES_SERVICIO o
    WHERE (@desde IS NULL OR o.fechaDesde >= @desde)
      AND (@hasta IS NULL OR o.fechaHasta <= @hasta)
      AND (@estado IS NULL OR o.estado = @estado)
      AND (@idOS IS NULL OR o.idOS = @idOS)
    ORDER BY o.idOS DESC FOR JSON PATH;
END
GO

/* Marca el resultado de un intento de migración a logística */
CREATE OR ALTER PROCEDURE TRANSPORTE_marcarOS
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idOS INT = TRY_CAST(JSON_VALUE(@json,'$.idOS') AS INT);
    DECLARE @estado NVARCHAR(20) = JSON_VALUE(@json,'$.estado');
    DECLARE @numeroOS NVARCHAR(50) = JSON_VALUE(@json,'$.numeroOS');
    DECLARE @respuesta NVARCHAR(MAX) = JSON_VALUE(@json,'$.respuesta');
    DECLARE @ultimoError NVARCHAR(500) = JSON_VALUE(@json,'$.ultimoError');
    IF @idOS IS NULL OR @estado NOT IN ('MIGRADA','ERROR')
    BEGIN RAISERROR(N'idOS y estado (MIGRADA|ERROR) son obligatorios',16,1); RETURN; END
    UPDATE TP_ORDENES_SERVICIO SET
        estado = @estado,
        numeroOSExterno = COALESCE(@numeroOS, numeroOSExterno),
        respuesta = COALESCE(@respuesta, respuesta),
        ultimoError = CASE WHEN @estado='ERROR' THEN @ultimoError ELSE NULL END,
        intentos = intentos + 1,
        fechaMigracion = CASE WHEN @estado='MIGRADA' THEN GETDATE() ELSE fechaMigracion END
    WHERE idOS = @idOS;
    SELECT o.*, (SELECT d.* FROM TP_OS_DETALLE d WHERE d.idOS = o.idOS FOR JSON PATH) AS detalle
    FROM TP_ORDENES_SERVICIO o WHERE o.idOS = @idOS FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO
