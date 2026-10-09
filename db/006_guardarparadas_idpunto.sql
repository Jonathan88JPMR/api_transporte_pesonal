-- ============================================================================
-- 006_guardarparadas_idpunto.sql
-- guardarParadas: si el JSON no trae idPunto, resolverlo por nombre
-- (el editor del coordinador enlaza por nombre de punto)
-- ============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

ALTER PROCEDURE TRANSPORTE_guardarParadas
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idTraslado INT = TRY_CAST(JSON_VALUE(@json, '$.idTraslado') AS INT);
    DECLARE @usuario NVARCHAR(100) = JSON_VALUE(@json, '$.usuario');

    IF NOT EXISTS (SELECT 1 FROM TP_TRASLADOS WHERE idTraslado = @idTraslado)
    BEGIN RAISERROR('Traslado no encontrado',16,1); RETURN; END

    -- La ruta ya esta en ejecucion: no se puede reescribir
    IF EXISTS (SELECT 1 FROM TP_TRASLADO_PARADAS
               WHERE idTraslado = @idTraslado AND estado <> 'PENDIENTE')
    BEGIN RAISERROR('La ruta ya esta en ejecucion; no se puede reescribir',16,1); RETURN; END

    BEGIN TRANSACTION;

    DELETE d FROM TP_PARADA_DETALLE d
    JOIN TP_TRASLADO_PARADAS p ON p.idParada = d.idParada
    WHERE p.idTraslado = @idTraslado;

    DELETE FROM TP_TRASLADO_PARADAS WHERE idTraslado = @idTraslado;

    INSERT INTO TP_TRASLADO_PARADAS (idTraslado, idPunto, punto, orden, cantidadSube, cantidadBaja)
    SELECT @idTraslado,
           COALESCE(TRY_CAST(JSON_VALUE(value, '$.idPunto') AS INT),
                    (SELECT TOP 1 pt.idPunto FROM TP_PUNTOS pt
                     WHERE pt.nombre = JSON_VALUE(value, '$.punto') AND pt.activo = 1)),
           JSON_VALUE(value, '$.punto'),
           TRY_CAST([key] AS INT) + 1,
           COALESCE(TRY_CAST(JSON_VALUE(value, '$.cantidadSube') AS INT), 0),
           COALESCE(TRY_CAST(JSON_VALUE(value, '$.cantidadBaja') AS INT), 0)
    FROM OPENJSON(@json, '$.paradas');

    -- Detalle parada <-> solicitud (quien sube/baja en cada punto)
    INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, idSolicitudUnidad, tipo, cantidadPlaneada)
    SELECT p.idParada,
           TRY_CAST(JSON_VALUE(dd.value,'$.idSolicitud') AS INT),
           TRY_CAST(JSON_VALUE(dd.value,'$.idSolicitudUnidad') AS INT),
           JSON_VALUE(dd.value,'$.tipo'),
           COALESCE(TRY_CAST(JSON_VALUE(dd.value,'$.cantidadPlaneada') AS INT),0)
    FROM OPENJSON(@json, '$.paradas') j
    JOIN TP_TRASLADO_PARADAS p ON p.idTraslado = @idTraslado
                              AND p.orden = TRY_CAST(j.[key] AS INT) + 1
    CROSS APPLY OPENJSON(j.value, '$.detalle') dd
    WHERE ISJSON(j.value) = 1;

    DECLARE @ruta NVARCHAR(2000);
    SELECT @ruta = STUFF((SELECT ' > ' + punto FROM TP_TRASLADO_PARADAS
                          WHERE idTraslado = @idTraslado ORDER BY orden
                          FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 3, '');
    UPDATE TP_TRASLADOS SET ruta = @ruta WHERE idTraslado = @idTraslado;

    INSERT INTO TP_AUDITORIA(entidad, idEntidad, accion, usuario, detalle)
    VALUES ('TRASLADO', @idTraslado, 'ACTUALIZAR_RUTA', @usuario, @json);

    COMMIT;

    SELECT p.*, JSON_QUERY((SELECT d.idParadaDetalle, d.idSolicitud, d.tipo,
                                   d.cantidadPlaneada, d.cantidadReal, s.nombre
                            FROM TP_PARADA_DETALLE d
                            LEFT JOIN TP_SOLICITUDES s ON s.idSolicitud = d.idSolicitud
                            WHERE d.idParada = p.idParada FOR JSON PATH)) AS detalle
    FROM TP_TRASLADO_PARADAS p WHERE p.idTraslado = @idTraslado ORDER BY p.orden
    FOR JSON PATH;
END
GO
