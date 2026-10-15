/* ============================================================
   021 — Consulta de estado de la OS en logística/SPRING
   - TP_ORDENES_SERVICIO + numeroOSSpring, estadoLogistica:
     se actualizan consultando a logística la OS migrada.
   - TRANSPORTE_marcarOS: además de MIGRADA/ERROR ahora acepta
     actualizar solo numeroOSSpring/estadoLogistica.
   Ejecutar con: sqlcmd -f 65001 (UTF-8)
   ============================================================ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

IF COL_LENGTH('TP_ORDENES_SERVICIO','numeroOSSpring') IS NULL
    ALTER TABLE TP_ORDENES_SERVICIO ADD numeroOSSpring NVARCHAR(30) NULL;
GO
IF COL_LENGTH('TP_ORDENES_SERVICIO','estadoLogistica') IS NULL
    ALTER TABLE TP_ORDENES_SERVICIO ADD estadoLogistica NVARCHAR(30) NULL;
GO

/* Marca resultado de migración o actualiza el estado en logística/SPRING.
   {idOS, estado:'MIGRADA'|'ERROR', numeroOS, respuesta, ultimoError}
   {idOS, numeroOSSpring, estadoLogistica}  → solo refresco de estado */
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
    DECLARE @numeroSpring NVARCHAR(30) = JSON_VALUE(@json,'$.numeroOSSpring');
    DECLARE @estadoLog NVARCHAR(30) = JSON_VALUE(@json,'$.estadoLogistica');
    IF @idOS IS NULL
    BEGIN RAISERROR(N'idOS es obligatorio',16,1); RETURN; END

    -- Refresco de estado: solo actualiza los datos de logística/SPRING
    IF @estado IS NULL
    BEGIN
        IF @numeroSpring IS NULL AND @estadoLog IS NULL
        BEGIN RAISERROR(N'Nada que actualizar: falta estado o datos de logística',16,1); RETURN; END
        UPDATE TP_ORDENES_SERVICIO SET
            numeroOSSpring = COALESCE(@numeroSpring, numeroOSSpring),
            estadoLogistica = COALESCE(@estadoLog, estadoLogistica)
        WHERE idOS = @idOS;
    END
    ELSE
    BEGIN
        IF @estado NOT IN ('MIGRADA','ERROR')
        BEGIN RAISERROR(N'estado debe ser MIGRADA o ERROR',16,1); RETURN; END
        UPDATE TP_ORDENES_SERVICIO SET
            estado = @estado,
            numeroOSExterno = COALESCE(@numeroOS, numeroOSExterno),
            respuesta = COALESCE(@respuesta, respuesta),
            ultimoError = CASE WHEN @estado='ERROR' THEN @ultimoError ELSE NULL END,
            intentos = intentos + 1,
            fechaMigracion = CASE WHEN @estado='MIGRADA' THEN GETDATE() ELSE fechaMigracion END
        WHERE idOS = @idOS;
    END

    SELECT o.*, (SELECT d.* FROM TP_OS_DETALLE d WHERE d.idOS = o.idOS FOR JSON PATH) AS detalle
    FROM TP_ORDENES_SERVICIO o WHERE o.idOS = @idOS FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO
