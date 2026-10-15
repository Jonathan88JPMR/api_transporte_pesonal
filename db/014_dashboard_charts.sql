SET QUOTED_IDENTIFIER ON;
GO
-- ============================================================================
-- 014_dashboard_charts.sql — series faltantes para replicar los 8 gráficos del
-- Excel (DASHBOARD): viajes por estado (pie), por semana (barra) y por mes
-- (línea). El resto (motivo, intervalo, fecha, unidades, areas) ya viene en 013.
-- ============================================================================

CREATE OR ALTER PROCEDURE TRANSPORTE_reporteIndicadores
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @desde DATE = TRY_CAST(JSON_VALUE(@json, '$.desde') AS DATE);
    DECLARE @hasta DATE = TRY_CAST(JSON_VALUE(@json, '$.hasta') AS DATE);
    SELECT
      (SELECT COUNT(*) FROM TP_SOLICITUDES WHERE estado <> 'ANULADO' AND (@desde IS NULL OR fechaProgramada >= @desde) AND (@hasta IS NULL OR fechaProgramada <= @hasta)) totalSolicitudes,
      (SELECT COALESCE(SUM(cantidad),0) FROM TP_SOLICITUDES WHERE estado <> 'ANULADO' AND (@desde IS NULL OR fechaProgramada >= @desde) AND (@hasta IS NULL OR fechaProgramada <= @hasta)) totalPersonas,
      (SELECT COALESCE(SUM(d.cantidadReal),0)
         FROM TP_PARADA_DETALLE d JOIN TP_SOLICITUDES s ON s.idSolicitud = d.idSolicitud
         WHERE d.tipo = 'S' AND s.estado <> 'ANULADO'
           AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)) personasReales,
      (SELECT COUNT(*) FROM TP_SOLICITUDES WHERE estado = 'REALIZADO' AND (@desde IS NULL OR fechaProgramada >= @desde) AND (@hasta IS NULL OR fechaProgramada <= @hasta)) totalRealizados,
      (SELECT COUNT(*) FROM TP_SOLICITUDES WHERE estado = 'ANULADO' AND (@desde IS NULL OR fechaProgramada >= @desde) AND (@hasta IS NULL OR fechaProgramada <= @hasta)) totalAnulados,
      (SELECT COUNT(*) FROM TP_SOLICITUDES WHERE prioridad = 'EMERGENCIA' AND estado <> 'ANULADO' AND (@desde IS NULL OR fechaProgramada >= @desde) AND (@hasta IS NULL OR fechaProgramada <= @hasta)) totalEmergencias,
      (SELECT COALESCE(100.0*SUM(CASE WHEN estado = 'REALIZADO' THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),0) FROM TP_SOLICITUDES WHERE estado <> 'ANULADO' AND (@desde IS NULL OR fechaProgramada>=@desde) AND (@hasta IS NULL OR fechaProgramada<=@hasta)) cumplimientoPorcentaje,
      (SELECT COALESCE(AVG(CAST(DATEDIFF(MINUTE,fechaInicio,fechaFin) AS DECIMAL(10,2))),0) FROM TP_SOLICITUDES WHERE fechaInicio IS NOT NULL AND fechaFin IS NOT NULL AND (@desde IS NULL OR fechaProgramada>=@desde) AND (@hasta IS NULL OR fechaProgramada<=@hasta)) tiempoPromedioMinutos,
      (SELECT COALESCE(AVG(CAST(CASE WHEN DATEDIFF(MINUTE,fechaRegistro,fechaInicio)<0 THEN 0 ELSE DATEDIFF(MINUTE,fechaRegistro,fechaInicio) END AS DECIMAL(10,2))),0) FROM TP_SOLICITUDES WHERE fechaInicio IS NOT NULL AND (@desde IS NULL OR fechaProgramada>=@desde) AND (@hasta IS NULL OR fechaProgramada<=@hasta)) esperaPromedioMinutos,
      (SELECT COALESCE(100.0*SUM(CASE WHEN ABS(DATEDIFF(MINUTE,DATEADD(MINUTE,DATEDIFF(MINUTE,0,TRY_CAST(horaProgramada AS TIME)),CAST(fechaProgramada AS DATETIME)),fechaInicio))<=10 THEN 1 ELSE 0 END)/NULLIF(COUNT(*),0),0) FROM TP_SOLICITUDES WHERE fechaInicio IS NOT NULL AND (@desde IS NULL OR fechaProgramada>=@desde) AND (@hasta IS NULL OR fechaProgramada<=@hasta)) puntualidadPorcentaje,
      -- pie: total de viajes realizados (SI / NO / Cancelado como el Excel)
      JSON_QUERY((SELECT CASE WHEN s.estado = 'REALIZADO' THEN 'SI'
                              WHEN s.estado = 'ANULADO' THEN 'Cancelado' ELSE 'NO' END realizados,
                         COUNT(*) viajes
                  FROM TP_SOLICITUDES s
                  WHERE (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                  GROUP BY CASE WHEN s.estado = 'REALIZADO' THEN 'SI'
                                WHEN s.estado = 'ANULADO' THEN 'Cancelado' ELSE 'NO' END FOR JSON PATH)) porEstado,
      -- KPI por motivo (bloque del Excel: cantidad + % sobre el total de personas)
      JSON_QUERY((SELECT COALESCE(s.motivo,'(sin motivo)') motivo,
                         COUNT(*) viajes,
                         SUM(s.cantidad) personas,
                         COALESCE(SUM(real.subidas),0) personasReales,
                         CAST(100.0*SUM(s.cantidad)/NULLIF(SUM(SUM(s.cantidad)) OVER(),0) AS DECIMAL(5,2)) porcentaje
                  FROM TP_SOLICITUDES s
                  OUTER APPLY (SELECT SUM(d.cantidadReal) subidas FROM TP_PARADA_DETALLE d
                               WHERE d.tipo = 'S' AND d.idSolicitud = s.idSolicitud) real
                  WHERE s.estado <> 'ANULADO' AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                  GROUP BY s.motivo
                  ORDER BY personas DESC FOR JSON PATH)) porMotivo,
      -- viajes por intervalo horario de la hora programada
      JSON_QUERY((SELECT CONCAT(h.hora, ':00 - ', h.hora, ':59') intervalo,
                         h.viajes, h.personas
                  FROM (
                      SELECT DATEPART(HOUR, TRY_CAST(s.horaProgramada AS TIME)) hora,
                             COUNT(*) viajes, SUM(s.cantidad) personas
                      FROM TP_SOLICITUDES s
                      WHERE s.estado <> 'ANULADO' AND TRY_CAST(s.horaProgramada AS TIME) IS NOT NULL
                        AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                      GROUP BY DATEPART(HOUR, TRY_CAST(s.horaProgramada AS TIME))
                  ) h ORDER BY h.hora FOR JSON PATH)) porIntervalo,
      -- tendencia diaria
      JSON_QUERY((SELECT CONVERT(VARCHAR(10), s.fechaProgramada, 23) fecha,
                         COUNT(*) viajes, SUM(s.cantidad) personas
                  FROM TP_SOLICITUDES s
                  WHERE s.estado <> 'ANULADO'
                    AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                  GROUP BY s.fechaProgramada
                  ORDER BY s.fechaProgramada FOR JSON PATH)) porFecha,
      -- por semana ISO (SEM-NN como el Excel)
      JSON_QUERY((SELECT semana, viajes, personas FROM (
                      SELECT CONCAT('SEM-', FORMAT(DATEPART(ISO_WEEK, s.fechaProgramada), '00')) semana,
                             DATEPART(ISO_WEEK, s.fechaProgramada) n,
                             COUNT(*) viajes, SUM(s.cantidad) personas
                      FROM TP_SOLICITUDES s
                      WHERE s.estado <> 'ANULADO'
                        AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                      GROUP BY DATEPART(ISO_WEEK, s.fechaProgramada)
                  ) w ORDER BY w.n FOR JSON PATH)) porSemana,
      -- tendencia mensual (línea del Excel)
      JSON_QUERY((SELECT mes, viajes, personas FROM (
                      SELECT CASE MONTH(s.fechaProgramada)
                               WHEN 1 THEN 'Enero' WHEN 2 THEN 'Febrero' WHEN 3 THEN 'Marzo'
                               WHEN 4 THEN 'Abril' WHEN 5 THEN 'Mayo' WHEN 6 THEN 'Junio'
                               WHEN 7 THEN 'Julio' WHEN 8 THEN 'Agosto' WHEN 9 THEN 'Septiembre'
                               WHEN 10 THEN 'Octubre' WHEN 11 THEN 'Noviembre' ELSE 'Diciembre' END mes,
                             MIN(s.fechaProgramada) orden,
                             COUNT(*) viajes, SUM(s.cantidad) personas
                      FROM TP_SOLICITUDES s
                      WHERE s.estado <> 'ANULADO'
                        AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                      GROUP BY MONTH(s.fechaProgramada), YEAR(s.fechaProgramada)
                  ) m ORDER BY m.orden FOR JSON PATH)) porMes,
      JSON_QUERY((SELECT placa, COUNT(*) viajes, SUM(personas) personas,
                         CAST(100.0 * SUM(personas) / NULLIF(COUNT(*) * MAX(capacidad), 0) AS DECIMAL(6,2)) ocupacionPorcentaje
                  FROM (
                      SELECT s.placa, s.cantidad AS personas, u.capacidad
                      FROM TP_SOLICITUDES s JOIN TP_UNIDADES u ON u.placa = s.placa
                      WHERE s.estado <> 'ANULADO' AND s.placa IS NOT NULL AND s.placa <> 'MULTIPLE'
                        AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                      UNION ALL
                      SELECT u.placa, su.cantidadAsignada, u.capacidad
                      FROM TP_SOLICITUD_UNIDADES su
                      JOIN TP_UNIDADES u ON u.idUnidad = su.idUnidad
                      JOIN TP_SOLICITUDES s ON s.idSolicitud = su.idSolicitud
                      WHERE su.estado <> 'ANULADO' AND s.estado <> 'ANULADO'
                        AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                  ) x GROUP BY placa FOR JSON PATH)) unidades,
      JSON_QUERY((SELECT COALESCE(a.nombre, s.area) AS area, COUNT(*) solicitudes, SUM(s.cantidad) personas
                  FROM TP_SOLICITUDES s LEFT JOIN TP_AREAS a ON a.idArea = s.idArea
                  WHERE s.estado <> 'ANULADO' AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                  GROUP BY COALESCE(a.nombre, s.area) FOR JSON PATH)) areas,
      JSON_QUERY((SELECT u.nombre conductor, u.placa, COUNT(x.idSolicitud) servicios, COALESCE(SUM(x.personas),0) personas
                  FROM TP_USUARIOS u
                  LEFT JOIN (
                      SELECT s.placa, s.idSolicitud, s.cantidad AS personas
                      FROM TP_SOLICITUDES s
                      WHERE s.estado = 'REALIZADO' AND s.placa IS NOT NULL AND s.placa <> 'MULTIPLE'
                        AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                      UNION ALL
                      SELECT u2.placa, s.idSolicitud, su.cantidadAsignada
                      FROM TP_SOLICITUD_UNIDADES su
                      JOIN TP_UNIDADES u2 ON u2.idUnidad = su.idUnidad
                      JOIN TP_SOLICITUDES s ON s.idSolicitud = su.idSolicitud
                      WHERE su.estado = 'REALIZADO'
                        AND (@desde IS NULL OR s.fechaProgramada >= @desde) AND (@hasta IS NULL OR s.fechaProgramada <= @hasta)
                  ) x ON x.placa = u.placa
                  WHERE u.idrol = 'CHTRANS' AND u.activo = 1 AND u.eliminado = 0
                  GROUP BY u.nombre, u.placa FOR JSON PATH)) conductores
    FOR JSON PATH;
END
GO
