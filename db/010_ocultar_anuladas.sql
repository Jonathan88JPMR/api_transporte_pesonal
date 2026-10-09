SET QUOTED_IDENTIFIER ON;
GO
-- listarSolicitudes: las anuladas no aparecen en la vista operativa;
-- solo se ven si se filtra explicitamente con estado='ANULADO'
CREATE OR ALTER PROCEDURE TRANSPORTE_listarSolicitudes
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @fecha  DATE = TRY_CAST(JSON_VALUE(@json, '$.fecha') AS DATE);
    DECLARE @estado NVARCHAR(20) = JSON_VALUE(@json, '$.estado');
    DECLARE @usuario NVARCHAR(50) = JSON_VALUE(@json, '$.usuario');
    DECLARE @idAreaFiltro INT = (SELECT idArea FROM TP_USUARIOS WHERE usuario = @usuario AND idrol = 'SPTRANS');
    DECLARE @esSupervisor BIT = CASE WHEN EXISTS (SELECT 1 FROM TP_USUARIOS WHERE usuario = @usuario AND idrol = 'SPTRANS') THEN 1 ELSE 0 END;

    SELECT s.idSolicitud, s.idTraslado, s.idArea, s.nombre, COALESCE(a.nombre, s.area) AS area,
           s.fechaProgramada, s.horaProgramada, s.puntoPartida, s.puntoLlegada, s.cantidad,
           s.motivo, s.observacion, s.prioridad, s.esEmergencia, s.placa,
           s.realizado, s.estado, s.usuarioRegistra, s.fechaRegistro, s.fechaInicio, s.fechaFin,
           JSON_QUERY((SELECT su.idSolicitudUnidad, u.placa, su.cantidadAsignada, su.estado, su.idTraslado
                       FROM TP_SOLICITUD_UNIDADES su
                       JOIN TP_UNIDADES u ON u.idUnidad = su.idUnidad
                       WHERE su.idSolicitud = s.idSolicitud AND su.estado <> 'ANULADO'
                       FOR JSON PATH)) AS porciones
    FROM TP_SOLICITUDES s
    LEFT JOIN TP_AREAS a ON a.idArea = s.idArea
    WHERE (@fecha  IS NULL OR s.fechaProgramada = @fecha)
      AND (@estado IS NOT NULL OR s.estado <> 'ANULADO')
      AND (@estado IS NULL OR s.estado = @estado)
      AND (@usuario IS NULL OR @esSupervisor = 0
           OR s.idArea = @idAreaFiltro
           OR (@idAreaFiltro IS NULL AND s.usuarioRegistra = @usuario))
    ORDER BY CASE s.prioridad WHEN 'EMERGENCIA' THEN 0 WHEN 'ALTA' THEN 1 ELSE 2 END,
             s.fechaRegistro, s.idSolicitud
    FOR JSON PATH;
END
GO

-- Limpieza: fila de prueba del test de fecha automatica
DELETE FROM TP_PARADA_DETALLE WHERE idSolicitud = 14;
DELETE FROM TP_AUDITORIA WHERE entidad='SOLICITUD' AND idEntidad = 14;
DELETE FROM TP_SOLICITUDES WHERE idSolicitud = 14;
GO
