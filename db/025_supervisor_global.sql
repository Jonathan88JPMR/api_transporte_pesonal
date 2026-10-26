SET QUOTED_IDENTIFIER ON;
GO
-- ============================================================================
-- 025_supervisor_global.sql
-- Los supervisores (SPTRANS) ya no ven solo su área: ven TODAS las solicitudes
-- de todos los supervisores, para conocer los servicios y las unidades
-- disponibles antes de solicitar movilidad.
-- La gestión sigue siendo por área: TRANSPORTE_acoplarSolicitud conserva su
-- guarda ("solo puede acoplar solicitudes de su propia area") y la UI oculta
-- Editar/Anular/Acoplar en solicitudes ajenas.
-- ============================================================================
CREATE OR ALTER PROCEDURE TRANSPORTE_listarSolicitudes
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @fecha  DATE = TRY_CAST(JSON_VALUE(@json, '$.fecha') AS DATE);
    DECLARE @estado NVARCHAR(20) = JSON_VALUE(@json, '$.estado');

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
    -- RN-004: prioridad primero (emergencias al tope), luego orden de registro
    ORDER BY CASE s.prioridad WHEN 'EMERGENCIA' THEN 0 WHEN 'ALTA' THEN 1 ELSE 2 END,
             s.fechaRegistro, s.idSolicitud
    FOR JSON PATH;
END
GO
