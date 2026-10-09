-- ============================================================================
-- 005_porciones_traslado.sql
-- Expone el idTraslado de cada porcion multi-unidad para que el coordinador
-- pueda ver T-x por porcion en la tabla de solicitudes.
-- ============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ----------------------------------------------------------------------------
-- listarServiciosConductor: el idTraslado expuesto es el de la porcion cuando
-- existe (esa fila ES el servicio de esa unidad)
-- ----------------------------------------------------------------------------
ALTER PROCEDURE TRANSPORTE_listarServiciosConductor
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @placa NVARCHAR(20) = JSON_VALUE(@json, '$.placa');
    DECLARE @fecha DATE = TRY_CAST(JSON_VALUE(@json, '$.fecha') AS DATE);

    SELECT s.idSolicitud, COALESCE(su.idTraslado, s.idTraslado) AS idTraslado,
           su.idSolicitudUnidad, s.nombre, s.area, s.fechaProgramada, s.horaProgramada,
           s.puntoPartida, s.puntoLlegada, COALESCE(su.cantidadAsignada,s.cantidad) cantidad, s.motivo, s.observacion,
           CASE WHEN COALESCE(su.esEmergencia, 0) = 1 THEN 'EMERGENCIA' ELSE s.prioridad END AS prioridad,
           CASE WHEN COALESCE(su.esEmergencia, 0) = 1 OR s.esEmergencia = 1 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS esEmergencia,
           @placa placa,
           CASE WHEN su.idSolicitudUnidad IS NULL THEN s.realizado ELSE CASE WHEN su.estado='REALIZADO' THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END END realizado,
           COALESCE(su.estado,s.estado) estado, s.fechaInicio, s.fechaFin,
           t.ruta,
           JSON_QUERY((SELECT p.idParada, p.idPunto, p.punto, p.orden,
                       p.cantidadSube, p.cantidadBaja,
                       p.subieronReal, p.bajaronReal, p.estado,
                       CONVERT(VARCHAR(33), p.horaLlegada, 126) AS horaLlegada,
                       CONVERT(VARCHAR(33), p.horaSalida,  126) AS horaSalida,
                       p.motivoOmision,
                       JSON_QUERY((SELECT d.idParadaDetalle, d.idSolicitud, d.idSolicitudUnidad,
                                   d.tipo, d.cantidadPlaneada, d.cantidadReal, s3.nombre
                            FROM TP_PARADA_DETALLE d
                            LEFT JOIN TP_SOLICITUDES s3 ON s3.idSolicitud = d.idSolicitud
                            WHERE d.idParada = p.idParada
                            FOR JSON PATH)) AS detalle
                       FROM TP_TRASLADO_PARADAS p
                       WHERE p.idTraslado = COALESCE(su.idTraslado, s.idTraslado)
                       ORDER BY p.orden FOR JSON PATH)) AS paradas
    FROM TP_SOLICITUDES s
    LEFT JOIN TP_SOLICITUD_UNIDADES su ON su.idSolicitud=s.idSolicitud
    LEFT JOIN TP_UNIDADES u ON u.idUnidad=su.idUnidad
    LEFT JOIN TP_TRASLADOS t ON t.idTraslado = COALESCE(su.idTraslado, s.idTraslado)
    WHERE (s.placa = @placa OR u.placa = @placa)
      AND s.estado <> 'ANULADO'
      AND (@fecha IS NULL OR s.fechaProgramada = @fecha)
    ORDER BY CASE WHEN COALESCE(su.esEmergencia,0)=1 OR s.prioridad='EMERGENCIA' THEN 0
                  WHEN s.prioridad='ALTA' THEN 1 ELSE 2 END,
             s.horaProgramada, s.idSolicitud
    FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- listarSolicitudes: incluye las porciones multi-unidad con su traslado
-- ----------------------------------------------------------------------------
ALTER PROCEDURE TRANSPORTE_listarSolicitudes
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @fecha  DATE = TRY_CAST(JSON_VALUE(@json, '$.fecha') AS DATE);
    DECLARE @estado NVARCHAR(20) = JSON_VALUE(@json, '$.estado');
    DECLARE @usuario NVARCHAR(50) = JSON_VALUE(@json, '$.usuario');
    -- Si quien consulta es supervisor, solo ve solicitudes de su area
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
      AND (@estado IS NULL OR s.estado = @estado)
      AND (@usuario IS NULL OR @esSupervisor = 0
           OR s.idArea = @idAreaFiltro
           OR (@idAreaFiltro IS NULL AND s.usuarioRegistra = @usuario))
    -- RN-004: prioridad primero (emergencias al tope), luego orden de registro
    ORDER BY CASE s.prioridad WHEN 'EMERGENCIA' THEN 0 WHEN 'ALTA' THEN 1 ELSE 2 END,
             s.fechaRegistro, s.idSolicitud
    FOR JSON PATH;
END
GO
