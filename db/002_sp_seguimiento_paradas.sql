-- ============================================================================
-- TRANSPORTE_PERSONAL — SPs nuevos de seguimiento de paradas
-- Patron del API: un parametro @json con el body completo; salida FOR JSON PATH.
-- La idempotencia offline (idOperacion) ya la resuelve BaseRepository contra
-- TP_OPERACIONES_CLIENTE antes de llamar al SP.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- POST paradas/llegada — PENDIENTE → EN_PARADA (solo la parada actual)
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_paradaLlegada
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idParada    INT          = TRY_CAST(JSON_VALUE(@json,'$.idParada') AS INT);
    DECLARE @horaCliente DATETIME2    = TRY_CAST(JSON_VALUE(@json,'$.horaCliente') AS DATETIME2);
    DECLARE @lat         DECIMAL(9,6) = TRY_CAST(JSON_VALUE(@json,'$.latitud') AS DECIMAL(9,6));
    DECLARE @lon         DECIMAL(9,6) = TRY_CAST(JSON_VALUE(@json,'$.longitud') AS DECIMAL(9,6));
    DECLARE @usuario     NVARCHAR(100)= JSON_VALUE(@json,'$.usuario');

    DECLARE @idTraslado INT, @estado VARCHAR(12), @orden INT;
    SELECT @idTraslado = idTraslado, @estado = estado, @orden = orden
    FROM TP_TRASLADO_PARADAS WHERE idParada = @idParada;

    IF @idTraslado IS NULL BEGIN RAISERROR('Parada no encontrada',16,1); RETURN; END
    IF @estado = 'EN_PARADA' GOTO fin;  -- reintento: ya quedo marcada
    IF @estado <> 'PENDIENTE' BEGIN RAISERROR('La parada ya fue procesada',16,1); RETURN; END

    -- Solo la primera parada pendiente del recorrido puede activarse
    IF EXISTS (SELECT 1 FROM TP_TRASLADO_PARADAS
               WHERE idTraslado = @idTraslado AND orden < @orden AND estado = 'PENDIENTE')
    BEGIN RAISERROR('Hay paradas anteriores sin procesar',16,1); RETURN; END

    UPDATE TP_TRASLADO_PARADAS
    SET estado = 'EN_PARADA',
        horaLlegada = COALESCE(@horaCliente, GETDATE()),
        latitud = @lat, longitud = @lon,
        usuarioRegistra = @usuario, fechaRegistro = GETDATE()
    WHERE idParada = @idParada;

    UPDATE TP_TRASLADOS SET estado = 'EN_RUTA'
    WHERE idTraslado = @idTraslado AND estado IN ('PENDIENTE','ASIGNADO');

    INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle)
    VALUES('PARADA',@idParada,'LLEGADA',@usuario,@json);

    fin:
    SELECT idParada, idTraslado, punto, orden, estado, horaLlegada, horaSalida,
           subieronReal, bajaronReal
    FROM TP_TRASLADO_PARADAS WHERE idParada = @idParada
    FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- POST paradas/registrar — EN_PARADA → REALIZADA con conteos reales
-- (si llega en PENDIENTE graba llegada y salida en un solo paso)
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_paradaRegistrar
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idParada     INT           = TRY_CAST(JSON_VALUE(@json,'$.idParada') AS INT);
    DECLARE @subieronReal INT           = TRY_CAST(JSON_VALUE(@json,'$.subieronReal') AS INT);
    DECLARE @bajaronReal  INT           = TRY_CAST(JSON_VALUE(@json,'$.bajaronReal') AS INT);
    DECLARE @horaCliente  DATETIME2     = TRY_CAST(JSON_VALUE(@json,'$.horaCliente') AS DATETIME2);
    DECLARE @lat          DECIMAL(9,6)  = TRY_CAST(JSON_VALUE(@json,'$.latitud') AS DECIMAL(9,6));
    DECLARE @lon          DECIMAL(9,6)  = TRY_CAST(JSON_VALUE(@json,'$.longitud') AS DECIMAL(9,6));
    DECLARE @usuario      NVARCHAR(100) = JSON_VALUE(@json,'$.usuario');
    DECLARE @detalle      NVARCHAR(MAX) = JSON_QUERY(@json,'$.detalle');

    DECLARE @idTraslado INT, @estado VARCHAR(12), @orden INT;
    SELECT @idTraslado = idTraslado, @estado = estado, @orden = orden
    FROM TP_TRASLADO_PARADAS WHERE idParada = @idParada;

    IF @idTraslado IS NULL BEGIN RAISERROR('Parada no encontrada',16,1); RETURN; END
    IF @estado = 'REALIZADA' GOTO fin;  -- reintento: ya quedo registrada
    IF @estado = 'OMITIDA'   BEGIN RAISERROR('La parada fue omitida',16,1); RETURN; END
    IF @subieronReal IS NULL OR @bajaronReal IS NULL OR @subieronReal < 0 OR @bajaronReal < 0
    BEGIN RAISERROR('Conteos invalidos',16,1); RETURN; END

    -- Capacidad: el a bordo resultante no puede exceder la unidad
    DECLARE @aBordo INT, @capacidad INT;
    SELECT @capacidad = u.capacidad
    FROM TP_TRASLADOS t JOIN TP_UNIDADES u ON u.placa = t.placa
    WHERE t.idTraslado = @idTraslado;

    SELECT @aBordo = SUM(COALESCE(subieronReal, cantidadSube, 0)
                       - COALESCE(bajaronReal,  cantidadBaja, 0))
    FROM TP_TRASLADO_PARADAS
    WHERE idTraslado = @idTraslado AND orden < @orden AND estado = 'REALIZADA';

    SET @aBordo = COALESCE(@aBordo, 0) + @subieronReal - @bajaronReal;

    IF @capacidad IS NOT NULL AND @aBordo > @capacidad
    BEGIN RAISERROR('Los pasajeros a bordo exceden la capacidad de la unidad',16,1); RETURN; END

    BEGIN TRANSACTION;

    UPDATE TP_TRASLADO_PARADAS
    SET estado = 'REALIZADA',
        subieronReal = @subieronReal,
        bajaronReal  = @bajaronReal,
        horaLlegada  = COALESCE(horaLlegada, @horaCliente, GETDATE()),
        horaSalida   = COALESCE(@horaCliente, GETDATE()),
        latitud  = COALESCE(@lat, latitud),
        longitud = COALESCE(@lon, longitud),
        usuarioRegistra = @usuario, fechaRegistro = GETDATE()
    WHERE idParada = @idParada;

    -- Conteo real por solicitud, si el conductor lo detallo
    IF @detalle IS NOT NULL
        UPDATE d SET d.cantidadReal = TRY_CAST(JSON_VALUE(j.value,'$.cantidadReal') AS INT)
        FROM TP_PARADA_DETALLE d
        JOIN OPENJSON(@detalle) j
          ON d.idParadaDetalle = TRY_CAST(JSON_VALUE(j.value,'$.idParadaDetalle') AS INT)
        WHERE d.idParada = @idParada
          AND JSON_VALUE(j.value,'$.cantidadReal') IS NOT NULL;

    -- Sin paradas pendientes el traslado queda ejecutado
    IF NOT EXISTS (SELECT 1 FROM TP_TRASLADO_PARADAS
                   WHERE idTraslado = @idTraslado AND estado IN ('PENDIENTE','EN_PARADA'))
        UPDATE TP_TRASLADOS SET estado = 'REALIZADO' WHERE idTraslado = @idTraslado;

    INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle)
    VALUES('PARADA',@idParada,'REGISTRAR',@usuario,@json);

    COMMIT;

    fin:
    SELECT idParada, idTraslado, punto, orden, estado, horaLlegada, horaSalida,
           subieronReal, bajaronReal
    FROM TP_TRASLADO_PARADAS WHERE idParada = @idParada
    FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- POST paradas/omitir — PENDIENTE/EN_PARADA → OMITIDA
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_paradaOmitir
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idParada    INT           = TRY_CAST(JSON_VALUE(@json,'$.idParada') AS INT);
    DECLARE @motivo      NVARCHAR(200) = JSON_VALUE(@json,'$.motivo');
    DECLARE @horaCliente DATETIME2     = TRY_CAST(JSON_VALUE(@json,'$.horaCliente') AS DATETIME2);
    DECLARE @usuario     NVARCHAR(100) = JSON_VALUE(@json,'$.usuario');

    DECLARE @estado VARCHAR(12), @previsto INT, @idTraslado INT;
    SELECT @estado = estado, @idTraslado = idTraslado,
           @previsto = COALESCE(cantidadSube,0) + COALESCE(cantidadBaja,0)
    FROM TP_TRASLADO_PARADAS WHERE idParada = @idParada;

    IF @estado IS NULL BEGIN RAISERROR('Parada no encontrada',16,1); RETURN; END
    IF @estado IN ('REALIZADA','OMITIDA') BEGIN RAISERROR('La parada ya fue procesada',16,1); RETURN; END
    IF @previsto > 0 AND NULLIF(LTRIM(RTRIM(@motivo)),'') IS NULL
    BEGIN RAISERROR('La parada tenia movimiento previsto; indique el motivo',16,1); RETURN; END

    UPDATE TP_TRASLADO_PARADAS
    SET estado = 'OMITIDA', motivoOmision = @motivo,
        horaSalida = COALESCE(@horaCliente, GETDATE()),
        usuarioRegistra = @usuario, fechaRegistro = GETDATE()
    WHERE idParada = @idParada;

    -- Sin paradas pendientes el traslado queda ejecutado
    IF NOT EXISTS (SELECT 1 FROM TP_TRASLADO_PARADAS
                   WHERE idTraslado = @idTraslado AND estado IN ('PENDIENTE','EN_PARADA'))
        UPDATE TP_TRASLADOS SET estado = 'REALIZADO' WHERE idTraslado = @idTraslado;

    INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle)
    VALUES('PARADA',@idParada,'OMITIR',@usuario,@json);

    SELECT idParada, idTraslado, punto, orden, estado, motivoOmision
    FROM TP_TRASLADO_PARADAS WHERE idParada = @idParada
    FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- POST paradas/imprevista — el conductor inserta una parada no programada.
-- Se ubica como la SIGUIENTE parada (antes de las demas pendientes).
-- Si se invoca con idSolicitud y la solicitud no tiene traslado (asignacion
-- simple antigua), se crea el traslado implicito con sus dos paradas base.
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_paradaImprevista
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idTraslado   INT           = TRY_CAST(JSON_VALUE(@json,'$.idTraslado') AS INT);
    DECLARE @idSolicitud  INT           = TRY_CAST(JSON_VALUE(@json,'$.idSolicitud') AS INT);
    DECLARE @punto        NVARCHAR(300) = JSON_VALUE(@json,'$.punto');
    DECLARE @cantidadSube INT           = COALESCE(TRY_CAST(JSON_VALUE(@json,'$.cantidadSube') AS INT),0);
    DECLARE @horaCliente  DATETIME2     = TRY_CAST(JSON_VALUE(@json,'$.horaCliente') AS DATETIME2);
    DECLARE @usuario      NVARCHAR(100) = JSON_VALUE(@json,'$.usuario');
    DECLARE @idPunto      INT           = (SELECT idPunto FROM TP_PUNTOS WHERE nombre = @punto AND activo = 1);

    IF @idTraslado IS NULL AND @idSolicitud IS NULL
    BEGIN RAISERROR('Indique idTraslado o idSolicitud',16,1); RETURN; END
    IF NULLIF(LTRIM(RTRIM(@punto)),'') IS NULL
    BEGIN RAISERROR('Indique el punto de la parada',16,1); RETURN; END

    -- Asignacion simple antigua: crear traslado implicito con paradas base
    IF @idTraslado IS NULL AND @idSolicitud IS NOT NULL
    BEGIN
        DECLARE @placa NVARCHAR(40), @pp NVARCHAR(300), @pl NVARCHAR(300), @cant INT;
        SELECT @placa = placa, @pp = puntoPartida, @pl = puntoLlegada, @cant = cantidad
        FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud AND estado IN ('ASIGNADO','EN_RUTA');

        IF @placa IS NULL OR @placa = 'MULTIPLE'
        BEGIN RAISERROR('La solicitud no tiene una unidad asignable a traslado',16,1); RETURN; END

        INSERT INTO TP_TRASLADOS(placa, ruta, estado)
        VALUES (@placa, CONCAT(@pp,' > ',@pl), 'EN_RUTA');
        SET @idTraslado = SCOPE_IDENTITY();

        UPDATE TP_SOLICITUDES SET idTraslado = @idTraslado WHERE idSolicitud = @idSolicitud;

        INSERT INTO TP_TRASLADO_PARADAS(idTraslado, punto, orden, cantidadSube, cantidadBaja)
        VALUES (@idTraslado,@pp,1,@cant,0), (@idTraslado,@pl,2,0,@cant);

        INSERT INTO TP_PARADA_DETALLE(idParada,idSolicitud,tipo,cantidadPlaneada)
        SELECT p.idParada, @idSolicitud, CASE p.orden WHEN 1 THEN 'S' ELSE 'B' END, @cant
        FROM TP_TRASLADO_PARADAS p WHERE p.idTraslado = @idTraslado;
    END

    IF NOT EXISTS (SELECT 1 FROM TP_TRASLADOS WHERE idTraslado = @idTraslado)
    BEGIN RAISERROR('Traslado no encontrado',16,1); RETURN; END

    BEGIN TRANSACTION;

    -- Posicion: antes de la primera PENDIENTE; si no hay, al final
    DECLARE @orden INT;
    SELECT @orden = MIN(orden) FROM TP_TRASLADO_PARADAS
    WHERE idTraslado = @idTraslado AND estado = 'PENDIENTE';

    IF @orden IS NULL
        SELECT @orden = ISNULL(MAX(orden),0) + 1 FROM TP_TRASLADO_PARADAS
        WHERE idTraslado = @idTraslado;
    ELSE
        UPDATE TP_TRASLADO_PARADAS SET orden = orden + 1
        WHERE idTraslado = @idTraslado AND estado = 'PENDIENTE' AND orden >= @orden;

    INSERT INTO TP_TRASLADO_PARADAS(idTraslado, idPunto, punto, orden,
                                    cantidadSube, cantidadBaja, usuarioRegistra, fechaRegistro)
    VALUES (@idTraslado, @idPunto, @punto, @orden, @cantidadSube, 0, @usuario, GETDATE());

    DECLARE @idParada INT = SCOPE_IDENTITY();

    -- Recalcular la ruta textual del traslado
    DECLARE @ruta NVARCHAR(2000);
    SELECT @ruta = STUFF((SELECT ' > ' + punto FROM TP_TRASLADO_PARADAS
                          WHERE idTraslado = @idTraslado ORDER BY orden
                          FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,3,'');
    UPDATE TP_TRASLADOS SET ruta = @ruta WHERE idTraslado = @idTraslado;

    INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle)
    VALUES('PARADA',@idParada,'IMPREVISTA',@usuario,@json);

    COMMIT;

    SELECT idParada, idTraslado, punto, orden, estado, cantidadSube, cantidadBaja
    FROM TP_TRASLADO_PARADAS WHERE idParada = @idParada
    FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- POST traslados/progreso — resumen liviano para el polling del coordinador
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_trasladoProgreso
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idTraslado INT = TRY_CAST(JSON_VALUE(@json,'$.idTraslado') AS INT);

    SELECT t.idTraslado, t.placa, t.estado AS estadoTraslado,
           (SELECT COUNT(*) FROM TP_TRASLADO_PARADAS p WHERE p.idTraslado = t.idTraslado) AS totalParadas,
           (SELECT COUNT(*) FROM TP_TRASLADO_PARADAS p WHERE p.idTraslado = t.idTraslado
             AND p.estado IN ('REALIZADA','OMITIDA')) AS realizadas,
           (SELECT MIN(p.orden) FROM TP_TRASLADO_PARADAS p WHERE p.idTraslado = t.idTraslado
             AND p.estado IN ('PENDIENTE','EN_PARADA')) AS paradaActual,
           COALESCE((SELECT SUM(COALESCE(p.subieronReal,p.cantidadSube,0)
                              - COALESCE(p.bajaronReal, p.cantidadBaja,0))
                     FROM TP_TRASLADO_PARADAS p
                     WHERE p.idTraslado = t.idTraslado
                       AND p.estado IN ('REALIZADA','EN_PARADA')),0) AS aBordo,
           JSON_QUERY((SELECT p.idParada, p.idPunto, p.punto, p.orden,
                   p.cantidadSube, p.cantidadBaja,
                   p.subieronReal, p.bajaronReal, p.estado,
                   CONVERT(VARCHAR(33), p.horaLlegada, 126) AS horaLlegada,
                   CONVERT(VARCHAR(33), p.horaSalida,  126) AS horaSalida,
                   p.motivoOmision,
                   JSON_QUERY((SELECT d.idParadaDetalle, d.idSolicitud, d.idSolicitudUnidad,
                               d.tipo, d.cantidadPlaneada, d.cantidadReal, s.nombre
                        FROM TP_PARADA_DETALLE d
                        LEFT JOIN TP_SOLICITUDES s ON s.idSolicitud = d.idSolicitud
                        WHERE d.idParada = p.idParada
                        FOR JSON PATH)) AS detalle
            FROM TP_TRASLADO_PARADAS p
            WHERE p.idTraslado = t.idTraslado
            ORDER BY p.orden
            FOR JSON PATH)) AS paradas
    FROM TP_TRASLADOS t
    WHERE t.idTraslado = @idTraslado
    FOR JSON PATH;
END
GO
