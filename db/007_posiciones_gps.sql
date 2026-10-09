SET QUOTED_IDENTIFIER ON;
GO
-- ============================================================================
-- 007_posiciones_gps.sql — ubicacion GPS en vivo de la unidad
-- - TP_TRASLADO_POSICIONES: historial de pings (trazo del recorrido)
-- - TP_TRASLADOS.ultima*: lectura barata de la ultima posicion conocida
-- - TRANSPORTE_reportarUbicacion: ping del conductor (cada ~30s en ruta)
-- - listarTraslados / trasladoProgreso: exponen la ultima posicion
-- ============================================================================

IF OBJECT_ID('TP_TRASLADO_POSICIONES','U') IS NULL
CREATE TABLE TP_TRASLADO_POSICIONES (
    idPosicion       INT IDENTITY(1,1) PRIMARY KEY,
    idTraslado       INT NOT NULL REFERENCES TP_TRASLADOS(idTraslado),
    placa            NVARCHAR(20) NOT NULL,
    latitud          FLOAT NOT NULL,
    longitud         FLOAT NOT NULL,
    precision        FLOAT NULL,
    fechaHoraCliente DATETIME2 NULL,
    fechaRegistro    DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_TRASLADO_POSICIONES' AND object_id = OBJECT_ID('TP_TRASLADO_POSICIONES'))
    CREATE INDEX IX_TRASLADO_POSICIONES ON TP_TRASLADO_POSICIONES(idTraslado, fechaRegistro);
GO

IF COL_LENGTH('TP_TRASLADOS','ultimaLatitud') IS NULL
    ALTER TABLE TP_TRASLADOS ADD ultimaLatitud FLOAT NULL;
GO
IF COL_LENGTH('TP_TRASLADOS','ultimaLongitud') IS NULL
    ALTER TABLE TP_TRASLADOS ADD ultimaLongitud FLOAT NULL;
GO
IF COL_LENGTH('TP_TRASLADOS','ultimaUbicacionAt') IS NULL
    ALTER TABLE TP_TRASLADOS ADD ultimaUbicacionAt DATETIME2 NULL;
GO

-- ----------------------------------------------------------------------------
-- POST unidades/ubicacion — ping GPS del conductor.
-- Resuelve el traslado por idTraslado, idSolicitudUnidad, idSolicitud o placa
-- (traslado activo mas reciente de la unidad). Solo registra si el traslado
-- esta ASIGNADO o EN_RUTA. Los pings a menos de 15s no duplican el historial.
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_reportarUbicacion
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idTraslado        INT           = TRY_CAST(JSON_VALUE(@json,'$.idTraslado') AS INT),
            @idSolicitud       INT           = TRY_CAST(JSON_VALUE(@json,'$.idSolicitud') AS INT),
            @idSolicitudUnidad INT           = TRY_CAST(JSON_VALUE(@json,'$.idSolicitudUnidad') AS INT),
            @placa             NVARCHAR(20)  = JSON_VALUE(@json,'$.placa'),
            @lat               FLOAT         = TRY_CAST(JSON_VALUE(@json,'$.latitud') AS FLOAT),
            @lng               FLOAT         = TRY_CAST(JSON_VALUE(@json,'$.longitud') AS FLOAT),
            @precision         FLOAT         = TRY_CAST(JSON_VALUE(@json,'$.precision') AS FLOAT),
            @horaCliente       DATETIME2     = TRY_CAST(JSON_VALUE(@json,'$.fechaHoraCliente') AS DATETIME2),
            @usuario           NVARCHAR(100) = JSON_VALUE(@json,'$.usuario');

    IF @lat IS NULL OR @lng IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) ok, 'Coordenadas invalidas' mensaje FOR JSON PATH;
        RETURN;
    END

    IF @idTraslado IS NULL AND @idSolicitudUnidad IS NOT NULL
        SELECT @idTraslado = su.idTraslado
        FROM TP_SOLICITUD_UNIDADES su WHERE su.idSolicitudUnidad = @idSolicitudUnidad;

    IF @idTraslado IS NULL AND @idSolicitud IS NOT NULL
        SELECT @idTraslado = COALESCE(s.idTraslado,
                (SELECT TOP 1 su.idTraslado FROM TP_SOLICITUD_UNIDADES su
                 LEFT JOIN TP_UNIDADES u ON u.idUnidad = su.idUnidad
                 WHERE su.idSolicitud = s.idSolicitud
                   AND (u.placa = @placa OR @placa IS NULL)
                 ORDER BY su.idSolicitudUnidad))
        FROM TP_SOLICITUDES s WHERE s.idSolicitud = @idSolicitud;

    -- Fallback: traslado activo mas reciente de la placa
    IF @idTraslado IS NULL AND @placa IS NOT NULL
        SELECT TOP 1 @idTraslado = t.idTraslado
        FROM TP_TRASLADOS t
        WHERE t.placa = @placa AND t.estado IN ('EN_RUTA','ASIGNADO')
        ORDER BY CASE t.estado WHEN 'EN_RUTA' THEN 0 ELSE 1 END, t.fechaCreacion DESC;

    IF @idTraslado IS NULL
       OR NOT EXISTS (SELECT 1 FROM TP_TRASLADOS WHERE idTraslado = @idTraslado
                       AND estado IN ('EN_RUTA','ASIGNADO'))
    BEGIN
        SELECT CAST(0 AS BIT) ok, 'Sin traslado activo' mensaje FOR JSON PATH;
        RETURN;
    END

    SELECT @placa = t.placa FROM TP_TRASLADOS t WHERE t.idTraslado = @idTraslado;

    -- Dedupe: si el ultimo ping fue hace menos de 15s solo refrescamos la ultima
    IF NOT EXISTS (SELECT 1 FROM TP_TRASLADO_POSICIONES
                   WHERE idTraslado = @idTraslado
                     AND fechaRegistro > DATEADD(SECOND,-15,SYSDATETIME()))
        INSERT INTO TP_TRASLADO_POSICIONES(idTraslado, placa, latitud, longitud, precision, fechaHoraCliente)
        VALUES(@idTraslado, @placa, @lat, @lng, @precision, @horaCliente);

    UPDATE TP_TRASLADOS
    SET ultimaLatitud = @lat, ultimaLongitud = @lng,
        ultimaUbicacionAt = COALESCE(@horaCliente, SYSDATETIME())
    WHERE idTraslado = @idTraslado;

    SELECT CAST(1 AS BIT) ok, @idTraslado idTraslado,
           CONVERT(VARCHAR(33), COALESCE(@horaCliente, SYSDATETIME()), 126) ultimaUbicacionAt
    FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- listarTraslados: incluye la ultima posicion conocida de la unidad
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_listarTraslados
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @fecha DATE = TRY_CAST(JSON_VALUE(@json, '$.fecha') AS DATE);

    SELECT t.idTraslado, t.placa, t.ruta, t.estado, t.fechaCreacion,
           t.ultimaLatitud, t.ultimaLongitud,
           CONVERT(VARCHAR(33), t.ultimaUbicacionAt, 126) AS ultimaUbicacionAt,
           JSON_QUERY((SELECT s.idSolicitud, s.nombre, s.horaProgramada, s.puntoPartida,
                   s.puntoLlegada,
                   COALESCE((SELECT TOP 1 su.cantidadAsignada FROM TP_SOLICITUD_UNIDADES su
                             WHERE su.idSolicitud = s.idSolicitud AND su.idTraslado = t.idTraslado), s.cantidad) cantidad,
                   s.motivo, s.realizado, s.estado, s.esEmergencia
            FROM TP_SOLICITUDES s
            WHERE (s.idTraslado = t.idTraslado
               OR EXISTS (SELECT 1 FROM TP_SOLICITUD_UNIDADES su
                          WHERE su.idSolicitud = s.idSolicitud AND su.idTraslado = t.idTraslado))
              AND s.estado <> 'ANULADO'
            FOR JSON PATH)) AS solicitudes,
           JSON_QUERY((SELECT p.idParada, p.idPunto, p.punto, p.orden,
                   p.cantidadSube, p.cantidadBaja,
                   p.subieronReal, p.bajaronReal, p.estado,
                   CONVERT(VARCHAR(33), p.horaLlegada, 126) AS horaLlegada,
                   CONVERT(VARCHAR(33), p.horaSalida,  126) AS horaSalida,
                   p.motivoOmision,
                   JSON_QUERY((SELECT d.idParadaDetalle, d.idSolicitud, d.idSolicitudUnidad,
                               d.tipo, d.cantidadPlaneada, d.cantidadReal, s2.nombre
                        FROM TP_PARADA_DETALLE d
                        LEFT JOIN TP_SOLICITUDES s2 ON s2.idSolicitud = d.idSolicitud
                        WHERE d.idParada = p.idParada
                        FOR JSON PATH)) AS detalle
            FROM TP_TRASLADO_PARADAS p WHERE p.idTraslado = t.idTraslado ORDER BY p.orden
            FOR JSON PATH)) AS paradas
    FROM TP_TRASLADOS t
    WHERE t.estado <> 'ANULADO'
      AND (@fecha IS NULL OR CAST(t.fechaCreacion AS DATE) = @fecha)
    ORDER BY t.fechaCreacion DESC
    FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- trasladoProgreso: incluye la ultima posicion GPS para el modal de progreso
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_trasladoProgreso
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idTraslado INT = TRY_CAST(JSON_VALUE(@json,'$.idTraslado') AS INT);

    SELECT t.idTraslado, t.placa, t.estado AS estadoTraslado,
           t.ultimaLatitud, t.ultimaLongitud,
           CONVERT(VARCHAR(33), t.ultimaUbicacionAt, 126) AS ultimaUbicacionAt,
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
