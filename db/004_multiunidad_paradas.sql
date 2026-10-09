-- ============================================================================
-- 004_multiunidad_paradas.sql
-- Cierra el gap de asignaciones multi-unidad: cada porcion
-- (TP_SOLICITUD_UNIDADES) obtiene su propio traslado implicito con paradas,
-- igual que asignarUnidad crea uno por solicitud.
-- ============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ----------------------------------------------------------------------------
-- 1) Enlace porcion -> traslado
-- ----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.columns
               WHERE object_id = OBJECT_ID('TP_SOLICITUD_UNIDADES') AND name = 'idTraslado')
    ALTER TABLE TP_SOLICITUD_UNIDADES ADD idTraslado INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_SolicitudUnidades_Traslado')
    CREATE INDEX IX_SolicitudUnidades_Traslado
    ON TP_SOLICITUD_UNIDADES(idTraslado) WHERE idTraslado IS NOT NULL;
GO

-- ----------------------------------------------------------------------------
-- 2) asignarMultiplesUnidades: un traslado con paradas por porcion.
--    Mismas validaciones de la version anterior + creacion de ruta A > B.
-- ----------------------------------------------------------------------------
ALTER PROCEDURE TRANSPORTE_asignarMultiplesUnidades
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idSolicitud INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @requerido INT = (SELECT cantidad FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud);
    DECLARE @fecha DATE = (SELECT fechaProgramada FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud);
    DECLARE @asignado INT;

    SELECT @asignado = SUM(TRY_CAST(JSON_VALUE(value, '$.cantidad') AS INT)) FROM OPENJSON(@json, '$.unidades');

    IF @requerido IS NULL OR @asignado <> @requerido
    BEGIN RAISERROR(N'La distribucion debe cubrir exactamente la cantidad solicitada', 16, 1); RETURN; END

    IF EXISTS (SELECT 1 FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud AND estado IN ('EN_RUTA', 'REALIZADO', 'ANULADO'))
    BEGIN RAISERROR('La solicitud ya esta en curso, realizada o anulada', 16, 1); RETURN; END

    -- Una placa no puede repetirse en la distribucion
    IF EXISTS (SELECT 1 FROM OPENJSON(@json, '$.unidades') j
               GROUP BY JSON_VALUE(j.value, '$.placa') HAVING COUNT(*) > 1)
    BEGIN RAISERROR('No se puede repetir la misma unidad en la distribucion', 16, 1); RETURN; END

    -- Cada unidad debe existir y tener cupo libre suficiente en esa fecha
    IF EXISTS (
        SELECT 1
        FROM OPENJSON(@json, '$.unidades') j
        LEFT JOIN TP_UNIDADES u ON u.placa = JSON_VALUE(j.value, '$.placa') AND u.activa = 1
        WHERE u.idUnidad IS NULL
           OR TRY_CAST(JSON_VALUE(j.value, '$.cantidad') AS INT) >
              u.capacidad
              - COALESCE((SELECT SUM(s.cantidad) FROM TP_SOLICITUDES s
                          WHERE s.placa = u.placa AND s.fechaProgramada = @fecha
                            AND s.estado IN ('ASIGNADO', 'EN_RUTA') AND s.idSolicitud <> @idSolicitud), 0)
              - COALESCE((SELECT SUM(su2.cantidadAsignada) FROM TP_SOLICITUD_UNIDADES su2
                          JOIN TP_SOLICITUDES s2 ON s2.idSolicitud = su2.idSolicitud
                          WHERE su2.idUnidad = u.idUnidad AND s2.fechaProgramada = @fecha
                            AND su2.estado IN ('ASIGNADO', 'EN_RUTA') AND s2.estado <> 'ANULADO'
                            AND s2.idSolicitud <> @idSolicitud), 0)
    )
    BEGIN RAISERROR('Una unidad no existe o no tiene cupo suficiente para esa fecha', 16, 1); RETURN; END

    -- Reasignacion: disolver los traslados de las porciones anteriores
    DELETE d FROM TP_PARADA_DETALLE d
    JOIN TP_TRASLADO_PARADAS p ON p.idParada = d.idParada
    WHERE p.idTraslado IN (SELECT idTraslado FROM TP_SOLICITUD_UNIDADES
                           WHERE idSolicitud = @idSolicitud AND idTraslado IS NOT NULL);
    DELETE p FROM TP_TRASLADO_PARADAS p
    WHERE p.idTraslado IN (SELECT idTraslado FROM TP_SOLICITUD_UNIDADES
                           WHERE idSolicitud = @idSolicitud AND idTraslado IS NOT NULL);
    UPDATE TP_TRASLADOS SET estado = 'ANULADO'
    WHERE idTraslado IN (SELECT idTraslado FROM TP_SOLICITUD_UNIDADES
                         WHERE idSolicitud = @idSolicitud AND idTraslado IS NOT NULL);

    DELETE FROM TP_SOLICITUD_UNIDADES WHERE idSolicitud = @idSolicitud;

    INSERT INTO TP_SOLICITUD_UNIDADES(idSolicitud, idUnidad, cantidadAsignada)
    SELECT @idSolicitud, u.idUnidad, TRY_CAST(JSON_VALUE(j.value, '$.cantidad') AS INT)
    FROM OPENJSON(@json, '$.unidades') j JOIN TP_UNIDADES u ON u.placa = JSON_VALUE(j.value, '$.placa');

    -- Traslado implicito por porcion: cada unidad recorre origen -> destino
    DECLARE @origen NVARCHAR(300), @destino NVARCHAR(300);
    SELECT @origen = puntoPartida, @destino = puntoLlegada
    FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud;
    DECLARE @ruta NVARCHAR(600) = CONCAT(@origen, ' > ', @destino);
    DECLARE @idPuntoO INT = (SELECT TOP 1 idPunto FROM TP_PUNTOS WHERE nombre = @origen  AND activo = 1);
    DECLARE @idPuntoD INT = (SELECT TOP 1 idPunto FROM TP_PUNTOS WHERE nombre = @destino AND activo = 1);

    DECLARE @su INT, @cant INT, @idTraslado INT, @idParada INT;
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT su.idSolicitudUnidad, su.cantidadAsignada
        FROM TP_SOLICITUD_UNIDADES su WHERE su.idSolicitud = @idSolicitud;
    OPEN cur;
    FETCH NEXT FROM cur INTO @su, @cant;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO TP_TRASLADOS (placa, ruta)
        SELECT u.placa, @ruta
        FROM TP_SOLICITUD_UNIDADES su JOIN TP_UNIDADES u ON u.idUnidad = su.idUnidad
        WHERE su.idSolicitudUnidad = @su;
        SET @idTraslado = SCOPE_IDENTITY();
        UPDATE TP_SOLICITUD_UNIDADES SET idTraslado = @idTraslado WHERE idSolicitudUnidad = @su;

        -- Origen = subida, destino = bajada (mismo patron que asignarUnidad)
        INSERT INTO TP_TRASLADO_PARADAS (idTraslado, idPunto, punto, orden, cantidadSube, cantidadBaja)
        VALUES (@idTraslado, @idPuntoO, @origen, 1, @cant, 0);
        SET @idParada = SCOPE_IDENTITY();
        INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, idSolicitudUnidad, tipo, cantidadPlaneada)
        VALUES (@idParada, @idSolicitud, @su, 'S', @cant);

        IF @origen <> @destino
        BEGIN
            INSERT INTO TP_TRASLADO_PARADAS (idTraslado, idPunto, punto, orden, cantidadSube, cantidadBaja)
            VALUES (@idTraslado, @idPuntoD, @destino, 2, 0, @cant);
            SET @idParada = SCOPE_IDENTITY();
            INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, idSolicitudUnidad, tipo, cantidadPlaneada)
            VALUES (@idParada, @idSolicitud, @su, 'B', @cant);
        END
        ELSE
            INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, idSolicitudUnidad, tipo, cantidadPlaneada)
            VALUES (@idParada, @idSolicitud, @su, 'B', @cant);

        FETCH NEXT FROM cur INTO @su, @cant;
    END
    CLOSE cur; DEALLOCATE cur;

    UPDATE TP_SOLICITUDES
    SET placa = CASE WHEN (SELECT COUNT(*) FROM OPENJSON(@json, '$.unidades')) = 1
                     THEN JSON_VALUE(@json, '$.unidades[0].placa') ELSE 'MULTIPLE' END,
        estado = 'ASIGNADO'
    WHERE idSolicitud = @idSolicitud;

    INSERT INTO TP_NOTIFICACIONES(idUsuario,titulo,mensaje,tipo)
    SELECT usr.idUsuario,'Nuevo servicio asignado',CONCAT('Solicitud #',@idSolicitud,' asignada a ',u.placa),'ASIGNACION'
    FROM TP_SOLICITUD_UNIDADES su JOIN TP_UNIDADES u ON u.idUnidad=su.idUnidad JOIN TP_USUARIOS usr ON usr.placa=u.placa AND usr.activo=1
    WHERE su.idSolicitud=@idSolicitud;

    INSERT INTO TP_NOTIFICACIONES(idUsuario,titulo,mensaje,tipo)
    SELECT usr.idUsuario,'Solicitud asignada',CONCAT('Su solicitud #',@idSolicitud,' fue asignada a ',u.placa),'ASIGNACION'
    FROM TP_SOLICITUDES s JOIN TP_USUARIOS usr ON usr.usuario=s.usuarioRegistra AND usr.activo=1
    JOIN TP_SOLICITUD_UNIDADES su ON su.idSolicitud=s.idSolicitud JOIN TP_UNIDADES u ON u.idUnidad=su.idUnidad
    WHERE s.idSolicitud=@idSolicitud;

    INSERT INTO TP_AUDITORIA(entidad, idEntidad, accion, usuario, detalle)
    VALUES ('SOLICITUD', @idSolicitud, 'ASIGNAR_MULTIPLES_UNIDADES', JSON_VALUE(@json, '$.usuario'), @json);

    SELECT su.idSolicitudUnidad, su.idSolicitud, u.idUnidad, u.placa, su.cantidadAsignada, su.estado, su.idTraslado
    FROM TP_SOLICITUD_UNIDADES su JOIN TP_UNIDADES u ON u.idUnidad = su.idUnidad
    WHERE su.idSolicitud = @idSolicitud FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- 3) listarServiciosConductor: paradas de la porcion (su.idTraslado)
--    o de la solicitud (s.idTraslado), segun corresponda
-- ----------------------------------------------------------------------------
ALTER PROCEDURE TRANSPORTE_listarServiciosConductor
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @placa NVARCHAR(20) = JSON_VALUE(@json, '$.placa');
    DECLARE @fecha DATE = TRY_CAST(JSON_VALUE(@json, '$.fecha') AS DATE);

    SELECT s.idSolicitud, s.idTraslado, su.idSolicitudUnidad, s.nombre, s.area, s.fechaProgramada, s.horaProgramada,
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
-- 4) listarTraslados: las porciones multi-unidad tambien exponen su solicitud
-- ----------------------------------------------------------------------------
ALTER PROCEDURE TRANSPORTE_listarTraslados
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @fecha DATE = TRY_CAST(JSON_VALUE(@json, '$.fecha') AS DATE);

    SELECT t.idTraslado, t.placa, t.ruta, t.estado, t.fechaCreacion,
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
-- 5) cambiarEstado: el bloqueo de REALIZADO por paradas pendientes se evalua
--    por porcion cuando llega idSolicitudUnidad; ademas propaga EN_RUTA y
--    REALIZADO al traslado correspondiente
-- ----------------------------------------------------------------------------
ALTER PROCEDURE TRANSPORTE_cambiarEstado
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @id INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @idSolicitudUnidad INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitudUnidad') AS INT);
    DECLARE @estado NVARCHAR(20) = UPPER(JSON_VALUE(@json, '$.estado'));

    IF @estado NOT IN ('ASIGNADO', 'EN_RUTA', 'REALIZADO')
    BEGIN RAISERROR(N'Estado de solicitud invalido', 16, 1); RETURN; END

    IF NOT EXISTS (SELECT 1 FROM TP_SOLICITUDES WHERE idSolicitud = @id AND estado <> 'ANULADO')
    BEGIN RAISERROR('La solicitud no existe o esta anulada', 16, 1); RETURN; END

    IF @idSolicitudUnidad IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM TP_SOLICITUD_UNIDADES WHERE idSolicitudUnidad = @idSolicitudUnidad AND idSolicitud = @id AND estado <> 'ANULADO')
    BEGIN RAISERROR('La porcion de unidad no existe o esta anulada', 16, 1); RETURN; END

    IF NOT EXISTS (SELECT 1 FROM TP_SOLICITUDES WHERE idSolicitud = @id AND placa IS NOT NULL)
    BEGIN RAISERROR('La solicitud debe tener una unidad asignada', 16, 1); RETURN; END

    -- No se puede finalizar mientras queden paradas sin procesar.
    -- Con porcion: solo las paradas del traslado de ESA porcion bloquean.
    IF @estado = 'REALIZADO' AND EXISTS (
        SELECT 1 FROM TP_PARADA_DETALLE d
        JOIN TP_TRASLADO_PARADAS p ON p.idParada = d.idParada
        WHERE ((@idSolicitudUnidad IS NOT NULL AND d.idSolicitudUnidad = @idSolicitudUnidad)
            OR (@idSolicitudUnidad IS NULL AND d.idSolicitud = @id))
          AND p.estado IN ('PENDIENTE','EN_PARADA'))
    BEGIN RAISERROR('La solicitud aun tiene paradas sin procesar en la ruta', 16, 1); RETURN; END

    IF @idSolicitudUnidad IS NOT NULL
    BEGIN
        UPDATE TP_SOLICITUD_UNIDADES SET estado = @estado WHERE idSolicitudUnidad = @idSolicitudUnidad AND idSolicitud = @id;

        -- Propagar al traslado de la porcion (sin degradar un REALIZADO)
        UPDATE TP_TRASLADOS
        SET estado = CASE WHEN @estado = 'EN_RUTA' THEN 'EN_RUTA'
                          WHEN @estado = 'REALIZADO' THEN 'REALIZADO'
                          ELSE estado END
        WHERE idTraslado = (SELECT idTraslado FROM TP_SOLICITUD_UNIDADES WHERE idSolicitudUnidad = @idSolicitudUnidad)
          AND estado IN ('PENDIENTE','ASIGNADO','EN_RUTA');

        UPDATE TP_SOLICITUDES
        SET estado = CASE WHEN NOT EXISTS (SELECT 1 FROM TP_SOLICITUD_UNIDADES WHERE idSolicitud = @id AND estado <> 'REALIZADO' AND estado <> 'ANULADO') THEN 'REALIZADO'
                          WHEN EXISTS (SELECT 1 FROM TP_SOLICITUD_UNIDADES WHERE idSolicitud = @id AND estado = 'EN_RUTA') THEN 'EN_RUTA' ELSE 'ASIGNADO' END,
            realizado = CASE WHEN NOT EXISTS (SELECT 1 FROM TP_SOLICITUD_UNIDADES WHERE idSolicitud = @id AND estado <> 'REALIZADO' AND estado <> 'ANULADO') THEN 1 ELSE 0 END,
            fechaInicio = CASE WHEN @estado = 'EN_RUTA' AND fechaInicio IS NULL THEN GETDATE() ELSE fechaInicio END,
            fechaFin = CASE WHEN NOT EXISTS (SELECT 1 FROM TP_SOLICITUD_UNIDADES WHERE idSolicitud = @id AND estado <> 'REALIZADO' AND estado <> 'ANULADO') THEN GETDATE() ELSE fechaFin END
        WHERE idSolicitud = @id;
    END
    ELSE
    BEGIN
        UPDATE TP_SOLICITUDES
        SET estado = @estado,
            realizado = CASE WHEN @estado = 'REALIZADO' THEN 1 ELSE 0 END,
            fechaInicio = CASE WHEN @estado = 'EN_RUTA' AND fechaInicio IS NULL THEN GETDATE() ELSE fechaInicio END,
            fechaFin = CASE WHEN @estado = 'REALIZADO' THEN GETDATE() ELSE NULL END
        WHERE idSolicitud = @id;

        -- Propagar al traslado implicito/grupal de la solicitud
        UPDATE TP_TRASLADOS
        SET estado = CASE WHEN @estado = 'EN_RUTA' THEN 'EN_RUTA'
                          WHEN @estado = 'REALIZADO' THEN 'REALIZADO'
                          ELSE estado END
        WHERE idTraslado = (SELECT idTraslado FROM TP_SOLICITUDES WHERE idSolicitud = @id)
          AND estado IN ('PENDIENTE','ASIGNADO','EN_RUTA')
          AND (@estado <> 'REALIZADO'
               OR NOT EXISTS (SELECT 1 FROM TP_SOLICITUDES sx
                              WHERE sx.idTraslado = (SELECT idTraslado FROM TP_SOLICITUDES WHERE idSolicitud = @id)
                                AND sx.idSolicitud <> @id AND sx.estado NOT IN ('REALIZADO','ANULADO')));
    END
    INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle) VALUES('SOLICITUD',@id,CONCAT('ESTADO_',@estado),JSON_VALUE(@json,'$.usuario'),@json);
    INSERT INTO TP_NOTIFICACIONES(idUsuario,titulo,mensaje,tipo)
    SELECT u.idUsuario, 'Estado de movilidad actualizado', CONCAT('La solicitud #',@id,' cambio a ',@estado), 'ESTADO'
    FROM TP_SOLICITUDES s JOIN TP_USUARIOS u ON u.usuario=s.usuarioRegistra WHERE s.idSolicitud=@id AND u.activo=1;
    SELECT * FROM TP_SOLICITUDES WHERE idSolicitud = @id FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- 6) desasignarUnidad: tambien disuelve los traslados de porciones multi-unidad
-- ----------------------------------------------------------------------------
ALTER PROCEDURE TRANSPORTE_desasignarUnidad
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @idTraslado INT = (SELECT idTraslado FROM TP_SOLICITUDES WHERE idSolicitud = @id);

    IF NOT EXISTS (SELECT 1 FROM TP_SOLICITUDES WHERE idSolicitud = @id AND estado = 'ASIGNADO')
    BEGIN RAISERROR('La solicitud no existe o no esta asignada', 16, 1); RETURN; END

    IF @idTraslado IS NOT NULL
       AND EXISTS (SELECT 1 FROM TP_SOLICITUDES
                   WHERE idTraslado = @idTraslado AND idSolicitud <> @id AND estado <> 'ANULADO')
    BEGIN RAISERROR('La solicitud pertenece a un traslado con mas solicitudes; use separar', 16, 1); RETURN; END

    IF EXISTS (SELECT 1 FROM TP_SOLICITUD_UNIDADES WHERE idSolicitud = @id AND estado <> 'ASIGNADO')
    BEGIN RAISERROR('Alguna unidad ya inicio el servicio; no se puede desasignar', 16, 1); RETURN; END

    -- Traslado implicito de una sola solicitud: disolverlo
    IF @idTraslado IS NOT NULL
    BEGIN
        DELETE d FROM TP_PARADA_DETALLE d
        JOIN TP_TRASLADO_PARADAS p ON p.idParada = d.idParada
        WHERE p.idTraslado = @idTraslado;
        DELETE FROM TP_TRASLADO_PARADAS WHERE idTraslado = @idTraslado;
        UPDATE TP_TRASLADOS SET estado = 'ANULADO' WHERE idTraslado = @idTraslado;
    END

    -- Porciones multi-unidad: disolver sus traslados propios
    DELETE d FROM TP_PARADA_DETALLE d
    JOIN TP_TRASLADO_PARADAS p ON p.idParada = d.idParada
    WHERE p.idTraslado IN (SELECT idTraslado FROM TP_SOLICITUD_UNIDADES
                           WHERE idSolicitud = @id AND idTraslado IS NOT NULL);
    DELETE p FROM TP_TRASLADO_PARADAS p
    WHERE p.idTraslado IN (SELECT idTraslado FROM TP_SOLICITUD_UNIDADES
                           WHERE idSolicitud = @id AND idTraslado IS NOT NULL);
    UPDATE TP_TRASLADOS SET estado = 'ANULADO'
    WHERE idTraslado IN (SELECT idTraslado FROM TP_SOLICITUD_UNIDADES
                         WHERE idSolicitud = @id AND idTraslado IS NOT NULL);

    DECLARE @placas TABLE (placa NVARCHAR(20));
    INSERT INTO @placas
        SELECT u.placa FROM TP_SOLICITUD_UNIDADES su
        JOIN TP_UNIDADES u ON u.idUnidad = su.idUnidad WHERE su.idSolicitud = @id;
    INSERT INTO @placas
        SELECT placa FROM TP_SOLICITUDES
        WHERE idSolicitud = @id AND placa IS NOT NULL AND placa <> 'MULTIPLE';

    DELETE FROM TP_SOLICITUD_UNIDADES WHERE idSolicitud = @id;

    UPDATE TP_SOLICITUDES SET placa = NULL, estado = 'PENDIENTE', idTraslado = NULL
    WHERE idSolicitud = @id;

    INSERT INTO TP_NOTIFICACIONES(idUsuario, titulo, mensaje, tipo)
    SELECT usr.idUsuario, 'Servicio desasignado', CONCAT('La solicitud #', @id, ' fue desasignada de su unidad'), 'ESTADO'
    FROM TP_USUARIOS usr JOIN @placas p ON usr.placa = p.placa WHERE usr.activo = 1;

    INSERT INTO TP_NOTIFICACIONES(idUsuario, titulo, mensaje, tipo)
    SELECT u.idUsuario, 'Solicitud desasignada', CONCAT('Su solicitud #', @id, ' fue desasignada y volvio a Pendiente'), 'ESTADO'
    FROM TP_SOLICITUDES s JOIN TP_USUARIOS u ON u.usuario = s.usuarioRegistra
    WHERE s.idSolicitud = @id AND u.activo = 1;

    INSERT INTO TP_AUDITORIA(entidad, idEntidad, accion, usuario, detalle)
    VALUES ('SOLICITUD', @id, 'DESASIGNAR_UNIDAD', JSON_VALUE(@json, '$.usuario'), @json);

    SELECT * FROM TP_SOLICITUDES WHERE idSolicitud = @id FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- 7) eliminarSolicitud: tambien anula los traslados de las porciones
-- ----------------------------------------------------------------------------
ALTER PROCEDURE TRANSPORTE_eliminarSolicitud
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @id INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @idTraslado INT = (SELECT idTraslado FROM TP_SOLICITUDES WHERE idSolicitud = @id);

    UPDATE TP_SOLICITUDES SET estado = 'ANULADO' WHERE idSolicitud = @id;
    UPDATE TP_SOLICITUD_UNIDADES SET estado = 'ANULADO' WHERE idSolicitud = @id;

    -- Descontar su aporte planeado de las paradas pendientes del traslado
    IF @idTraslado IS NOT NULL
    BEGIN
        UPDATE p
        SET cantidadSube = p.cantidadSube - ISNULL((
                SELECT SUM(d.cantidadPlaneada) FROM TP_PARADA_DETALLE d
                WHERE d.idParada = p.idParada AND d.idSolicitud = @id AND d.tipo = 'S'), 0),
            cantidadBaja = p.cantidadBaja - ISNULL((
                SELECT SUM(d.cantidadPlaneada) FROM TP_PARADA_DETALLE d
                WHERE d.idParada = p.idParada AND d.idSolicitud = @id AND d.tipo = 'B'), 0)
        FROM TP_TRASLADO_PARADAS p
        WHERE p.idTraslado = @idTraslado AND p.estado = 'PENDIENTE';

        DELETE d FROM TP_PARADA_DETALLE d
        JOIN TP_TRASLADO_PARADAS p ON p.idParada = d.idParada
        WHERE d.idSolicitud = @id AND p.estado = 'PENDIENTE';
    END

    -- Traslados de porciones multi-unidad: anular los no terminados
    UPDATE TP_TRASLADOS SET estado = 'ANULADO'
    WHERE idTraslado IN (SELECT idTraslado FROM TP_SOLICITUD_UNIDADES
                         WHERE idSolicitud = @id AND idTraslado IS NOT NULL)
      AND estado NOT IN ('REALIZADO');

    INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle) VALUES('SOLICITUD',@id,'ANULAR',JSON_VALUE(@json,'$.usuario'),@json);

    SELECT @id AS idSolicitud, 'ANULADO' AS estado FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- 8) agregarPasajeros: el detalle del extra tambien registra la porcion
-- ----------------------------------------------------------------------------
ALTER PROCEDURE TRANSPORTE_agregarPasajeros
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idSolicitud INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @idSolicitudUnidad INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitudUnidad') AS INT);
    DECLARE @idParada INT = TRY_CAST(JSON_VALUE(@json, '$.idParada') AS INT);
    DECLARE @extra INT = TRY_CAST(JSON_VALUE(@json, '$.cantidad') AS INT);

    IF @extra IS NULL OR @extra < 1 BEGIN RAISERROR(N'Cantidad de pasajeros invalida', 16, 1); RETURN; END

    DECLARE @idUnidad INT = (SELECT idUnidad FROM TP_SOLICITUD_UNIDADES
                             WHERE idSolicitudUnidad = @idSolicitudUnidad AND idSolicitud = @idSolicitud);
    DECLARE @placa NVARCHAR(20) = COALESCE((SELECT placa FROM TP_UNIDADES WHERE idUnidad = @idUnidad),
                                           (SELECT placa FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud));
    DECLARE @estado NVARCHAR(20) = COALESCE((SELECT estado FROM TP_SOLICITUD_UNIDADES WHERE idSolicitudUnidad = @idSolicitudUnidad),
                                            (SELECT estado FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud));
    DECLARE @fecha DATE = (SELECT fechaProgramada FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud);
    DECLARE @capacidad INT = (SELECT capacidad FROM TP_UNIDADES WHERE placa = @placa AND activa = 1);

    IF @placa IS NULL OR @placa = 'MULTIPLE' AND @idUnidad IS NULL
    BEGIN RAISERROR('Servicio sin unidad asignada', 16, 1); RETURN; END
    IF @estado IS NULL OR @estado NOT IN ('ASIGNADO', 'EN_RUTA')
    BEGIN RAISERROR('Solo se pueden agregar pasajeros a servicios asignados o en ruta', 16, 1); RETURN; END
    IF @capacidad IS NULL BEGIN RAISERROR('Unidad inexistente o inactiva', 16, 1); RETURN; END

    DECLARE @ocupacion INT;
    IF @idUnidad IS NOT NULL
        SELECT @ocupacion = COALESCE(SUM(su2.cantidadAsignada), 0)
        FROM TP_SOLICITUD_UNIDADES su2
        JOIN TP_SOLICITUDES s2 ON s2.idSolicitud = su2.idSolicitud
        WHERE su2.idUnidad = @idUnidad AND s2.fechaProgramada = @fecha AND s2.estado <> 'ANULADO';
    ELSE IF (SELECT idTraslado FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud) IS NOT NULL
        SELECT @ocupacion = COALESCE(SUM(s2.cantidad), 0)
        FROM TP_SOLICITUDES s2
        WHERE s2.idTraslado = (SELECT idTraslado FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud)
          AND s2.estado <> 'ANULADO';
    ELSE
        SELECT @ocupacion = COALESCE(SUM(s2.cantidad), 0)
        FROM TP_SOLICITUDES s2
        WHERE s2.placa = @placa AND s2.fechaProgramada = @fecha
          AND s2.estado IN ('ASIGNADO', 'EN_RUTA');

    IF @ocupacion + @extra > @capacidad
    BEGIN RAISERROR('No hay cupo suficiente en la unidad', 16, 1); RETURN; END

    IF @idUnidad IS NOT NULL
        UPDATE TP_SOLICITUD_UNIDADES SET cantidadAsignada = cantidadAsignada + @extra, esEmergencia = 1
        WHERE idSolicitudUnidad = @idSolicitudUnidad;
    ELSE
        UPDATE TP_SOLICITUDES SET esEmergencia = 1, prioridad = 'EMERGENCIA' WHERE idSolicitud = @idSolicitud;
    UPDATE TP_SOLICITUDES SET cantidad = cantidad + @extra WHERE idSolicitud = @idSolicitud;

    -- Si el extra sube en una parada concreta, quedar registrado ahi
    IF @idParada IS NOT NULL
    BEGIN
        UPDATE TP_TRASLADO_PARADAS
        SET cantidadSube  = CASE WHEN estado = 'PENDIENTE' THEN cantidadSube + @extra ELSE cantidadSube END,
            subieronReal  = CASE WHEN estado = 'EN_PARADA' THEN COALESCE(subieronReal, cantidadSube, 0) + @extra ELSE subieronReal END
        WHERE idParada = @idParada AND estado IN ('PENDIENTE','EN_PARADA');

        IF EXISTS (SELECT 1 FROM TP_PARADA_DETALLE
                   WHERE idParada = @idParada AND idSolicitud = @idSolicitud AND tipo = 'S'
                     AND (idSolicitudUnidad = @idSolicitudUnidad OR (@idSolicitudUnidad IS NULL AND idSolicitudUnidad IS NULL)))
            UPDATE TP_PARADA_DETALLE
            SET cantidadPlaneada = cantidadPlaneada + @extra,
                cantidadReal = CASE WHEN cantidadReal IS NOT NULL THEN cantidadReal + @extra ELSE cantidadReal END
            WHERE idParada = @idParada AND idSolicitud = @idSolicitud AND tipo = 'S'
              AND (idSolicitudUnidad = @idSolicitudUnidad OR (@idSolicitudUnidad IS NULL AND idSolicitudUnidad IS NULL));
        ELSE IF EXISTS (SELECT 1 FROM TP_TRASLADO_PARADAS WHERE idParada = @idParada)
            INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, idSolicitudUnidad, tipo, cantidadPlaneada)
            VALUES (@idParada, @idSolicitud, @idSolicitudUnidad, 'S', @extra);
    END

    INSERT INTO TP_AUDITORIA(entidad, idEntidad, accion, usuario, detalle)
    VALUES ('SOLICITUD', @idSolicitud, 'AGREGAR_PASAJEROS', JSON_VALUE(@json, '$.usuario'), @json);
    INSERT INTO TP_NOTIFICACIONES(idUsuario, titulo, mensaje, tipo)
    SELECT u.idUsuario, 'Pasajeros agregados', CONCAT(N'El conductor agrego ', @extra, ' pasajero(s) a la solicitud #', @idSolicitud), 'PASAJEROS'
    FROM TP_SOLICITUDES s JOIN TP_USUARIOS u ON u.usuario = s.usuarioRegistra
    WHERE s.idSolicitud = @idSolicitud AND u.activo = 1;

    SELECT * FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud FOR JSON PATH;
END
GO
