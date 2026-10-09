SET QUOTED_IDENTIFIER ON;
GO
-- ============================================================================
-- 011_marcar_realizado_paradas.sql — consistencia con el flujo de paradas
-- marcarRealizado marcaba la solicitud REALIZADO sin revisar paradas
-- pendientes ni propagar el estado a los traslados. Ahora aplica la misma
-- regla que cambiarEstado: no se puede finalizar con paradas sin procesar.
-- ============================================================================

CREATE OR ALTER PROCEDURE TRANSPORTE_marcarRealizado
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @id INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @realizado BIT = TRY_CAST(JSON_VALUE(@json, '$.realizado') AS BIT);

    IF @realizado = 1 AND EXISTS (
        SELECT 1 FROM TP_TRASLADO_PARADAS p
        WHERE p.estado IN ('PENDIENTE','EN_PARADA')
          AND p.idTraslado IN (
            SELECT s.idTraslado FROM TP_SOLICITUDES s
            WHERE s.idSolicitud = @id AND s.idTraslado IS NOT NULL
            UNION
            SELECT su.idTraslado FROM TP_SOLICITUD_UNIDADES su
            WHERE su.idSolicitud = @id AND su.idTraslado IS NOT NULL))
    BEGIN RAISERROR('La solicitud aun tiene paradas sin procesar en la ruta', 16, 1); RETURN; END

    UPDATE TP_SOLICITUD_UNIDADES
    SET estado = CASE WHEN @realizado = 1 THEN 'REALIZADO' ELSE 'ASIGNADO' END
    WHERE idSolicitud = @id AND estado <> 'ANULADO';

    UPDATE TP_SOLICITUDES
    SET realizado = @realizado,
        estado = CASE WHEN @realizado = 1 THEN 'REALIZADO' ELSE 'ASIGNADO' END,
        fechaFin = CASE WHEN @realizado = 1 THEN GETDATE() ELSE NULL END
    WHERE idSolicitud = @id;

    -- Propagar a los traslados de la solicitud (directo + porciones):
    -- solo cuando no quedan paradas pendientes ni otras solicitudes activas
    IF @realizado = 1
        UPDATE t SET estado = 'REALIZADO'
        FROM TP_TRASLADOS t
        WHERE t.idTraslado IN (
              SELECT s.idTraslado FROM TP_SOLICITUDES s
              WHERE s.idSolicitud = @id AND s.idTraslado IS NOT NULL
              UNION
              SELECT su.idTraslado FROM TP_SOLICITUD_UNIDADES su
              WHERE su.idSolicitud = @id AND su.idTraslado IS NOT NULL)
          AND t.estado IN ('PENDIENTE','ASIGNADO','EN_RUTA')
          AND NOT EXISTS (SELECT 1 FROM TP_TRASLADO_PARADAS p
                          WHERE p.idTraslado = t.idTraslado AND p.estado IN ('PENDIENTE','EN_PARADA'))
          AND NOT EXISTS (SELECT 1 FROM TP_SOLICITUDES sx
                          WHERE sx.idTraslado = t.idTraslado AND sx.idSolicitud <> @id
                            AND sx.estado NOT IN ('REALIZADO','ANULADO'));

    SELECT * FROM TP_SOLICITUDES WHERE idSolicitud = @id FOR JSON PATH;
END
GO
