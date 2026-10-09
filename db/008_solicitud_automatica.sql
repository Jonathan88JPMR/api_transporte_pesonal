SET QUOTED_IDENTIFIER ON;
GO
-- ============================================================================
-- 008_solicitud_automatica.sql — fecha/hora siempre del sistema
-- - INSERT: fechaProgramada y horaProgramada se fuerzan a GETDATE() del
--   servidor; el JSON del cliente se ignora (readonly no basta: se puede
--   manipular la llamada al API).
-- - UPDATE: esas columnas conservan su valor original.
-- - esEmergencia=1 fuerza prioridad='EMERGENCIA' a nivel BD.
-- ============================================================================

CREATE OR ALTER PROCEDURE TRANSPORTE_guardarSolicitud
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @idSolicitud INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @usuario NVARCHAR(50) = JSON_VALUE(@json, '$.usuarioRegistra');
    DECLARE @idArea INT = (SELECT idArea FROM TP_USUARIOS WHERE usuario = @usuario);
    DECLARE @areaNombre NVARCHAR(100) = COALESCE(
        (SELECT nombre FROM TP_AREAS WHERE idArea = @idArea),
        JSON_VALUE(@json, '$.area'));
    DECLARE @esEmergencia BIT = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.esEmergencia') AS BIT), 0);
    DECLARE @prioridad NVARCHAR(15) = UPPER(COALESCE(NULLIF(JSON_VALUE(@json, '$.prioridad'), ''), 'NORMAL'));
    IF @prioridad NOT IN ('NORMAL', 'ALTA', 'EMERGENCIA') SET @prioridad = 'NORMAL';
    IF @esEmergencia = 1 SET @prioridad = 'EMERGENCIA';  -- emergencia medica => maxima prioridad

    IF @idSolicitud IS NULL OR @idSolicitud = 0
    BEGIN
        INSERT INTO TP_SOLICITUDES (nombre, area, idArea, fechaProgramada, horaProgramada, puntoPartida, puntoLlegada,
                                    cantidad, motivo, observacion, prioridad, esEmergencia, usuarioRegistra)
        SELECT JSON_VALUE(@json, '$.nombre'), @areaNombre, @idArea,
               CAST(GETDATE() AS DATE),                    -- fecha: siempre la del sistema
               CONVERT(VARCHAR(5), GETDATE(), 108),        -- hora: siempre la del sistema (HH:mm)
               JSON_VALUE(@json, '$.puntoPartida'),
               JSON_VALUE(@json, '$.puntoLlegada'), TRY_CAST(JSON_VALUE(@json, '$.cantidad') AS INT),
               JSON_VALUE(@json, '$.motivo'), JSON_VALUE(@json, '$.observacion'),
               @prioridad, @esEmergencia, @usuario;
        SET @idSolicitud = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE TP_SOLICITUDES
        SET puntoPartida   = JSON_VALUE(@json, '$.puntoPartida'),
            puntoLlegada   = JSON_VALUE(@json, '$.puntoLlegada'),
            cantidad       = TRY_CAST(JSON_VALUE(@json, '$.cantidad') AS INT),
            motivo         = JSON_VALUE(@json, '$.motivo'),
            observacion    = JSON_VALUE(@json, '$.observacion'),
            prioridad      = CASE WHEN @esEmergencia = 1 THEN 'EMERGENCIA'
                                  ELSE COALESCE(NULLIF(JSON_VALUE(@json, '$.prioridad'), ''), prioridad) END,
            esEmergencia   = @esEmergencia
            -- fechaProgramada/horaProgramada: no se tocan, conservan el valor original
        WHERE idSolicitud = @idSolicitud;
    END

    INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle)
    VALUES('SOLICITUD',@idSolicitud,CASE WHEN JSON_VALUE(@json,'$.idSolicitud') IS NULL THEN 'CREAR' ELSE 'EDITAR' END,JSON_VALUE(@json,'$.usuarioRegistra'),@json);
    SELECT * FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud FOR JSON PATH;
END
GO
