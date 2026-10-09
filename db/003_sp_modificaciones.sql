-- ============================================================================
-- TRANSPORTE_PERSONAL — Modificaciones a SPs existentes (versiones completas)
-- Integran el seguimiento de paradas en todo el flujo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- guardarParadas: reconstruye la ruta solo si el recorrido no inicio;
-- sincroniza TP_PARADA_DETALLE por posicion (key del array = orden).
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_guardarParadas
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
    SELECT @idTraslado, TRY_CAST(JSON_VALUE(value, '$.idPunto') AS INT), JSON_VALUE(value, '$.punto'),
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

-- ----------------------------------------------------------------------------
-- unirSolicitudes: autogenera paradas fusionando puntos repetidos
-- (cada punto una vez, orden de primera aparicion por orden de seleccion)
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_unirSolicitudes
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @placa NVARCHAR(20) = JSON_VALUE(@json, '$.placa');
    DECLARE @idTraslado INT;
    DECLARE @ruta NVARCHAR(1000);
    DECLARE @idUnidad INT = (SELECT idUnidad FROM TP_UNIDADES WHERE placa = @placa AND activa = 1);
    DECLARE @capacidad INT = (SELECT capacidad FROM TP_UNIDADES WHERE placa = @placa AND activa = 1);

    DECLARE @Ids TABLE (idSolicitud INT, orden INT);
    INSERT INTO @Ids
    SELECT TRY_CAST(j.value AS INT), MIN(TRY_CAST(j.[key] AS INT))
    FROM OPENJSON(@json, '$.ids') j
    GROUP BY TRY_CAST(j.value AS INT);

    DECLARE @totalPersonas INT = (
        SELECT COALESCE(SUM(s.cantidad), 0) FROM TP_SOLICITUDES s JOIN @Ids i ON s.idSolicitud = i.idSolicitud);

    IF @capacidad IS NULL BEGIN RAISERROR('Unidad inexistente o inactiva', 16, 1); RETURN; END

    IF EXISTS (SELECT 1 FROM TP_SOLICITUDES s JOIN @Ids i ON s.idSolicitud = i.idSolicitud
               WHERE s.estado <> 'PENDIENTE' OR s.idTraslado IS NOT NULL)
    BEGIN RAISERROR('Solo se pueden unir solicitudes pendientes sin traslado', 16, 1); RETURN; END

    IF (SELECT COUNT(DISTINCT s.fechaProgramada)
        FROM TP_SOLICITUDES s JOIN @Ids i ON s.idSolicitud = i.idSolicitud) > 1
    BEGIN RAISERROR('Solo se pueden unir solicitudes de la misma fecha', 16, 1); RETURN; END

    DECLARE @fecha DATE = (
        SELECT TOP 1 s.fechaProgramada FROM TP_SOLICITUDES s JOIN @Ids i ON s.idSolicitud = i.idSolicitud);

    DECLARE @ocupado INT =
        COALESCE((SELECT SUM(s.cantidad) FROM TP_SOLICITUDES s
                  WHERE s.placa = @placa AND s.fechaProgramada = @fecha
                    AND s.estado IN ('ASIGNADO', 'EN_RUTA')), 0)
      + COALESCE((SELECT SUM(su.cantidadAsignada) FROM TP_SOLICITUD_UNIDADES su
                  JOIN TP_SOLICITUDES s2 ON s2.idSolicitud = su.idSolicitud
                  WHERE su.idUnidad = @idUnidad AND s2.fechaProgramada = @fecha
                    AND su.estado IN ('ASIGNADO', 'EN_RUTA') AND s2.estado <> 'ANULADO'), 0);

    IF @totalPersonas + @ocupado > @capacidad
    BEGIN RAISERROR('Las solicitudes superan el cupo disponible de la unidad', 16, 1); RETURN; END

    -- Eventos S/B por solicitud: partida antes que llegada (evOrd 0/1)
    DECLARE @Eventos TABLE (solOrd INT, evOrd INT, idSolicitud INT,
                            punto NVARCHAR(300), tipo CHAR(1), cantidad INT);
    INSERT INTO @Eventos
    SELECT i.orden, 0, s.idSolicitud, s.puntoPartida, 'S', s.cantidad
    FROM TP_SOLICITUDES s JOIN @Ids i ON s.idSolicitud = i.idSolicitud;
    INSERT INTO @Eventos
    SELECT i.orden, 1, s.idSolicitud, s.puntoLlegada, 'B', s.cantidad
    FROM TP_SOLICITUDES s JOIN @Ids i ON s.idSolicitud = i.idSolicitud;

    -- Ruta: puntos unicos en orden de primera aparicion
    SELECT @ruta = STUFF((
        SELECT ' > ' + punto FROM (
            SELECT punto, MIN(solOrd * 2 + evOrd) AS posMin
            FROM @Eventos GROUP BY punto) p
        ORDER BY posMin
        FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 3, '');

    INSERT INTO TP_TRASLADOS (placa, ruta) VALUES (@placa, @ruta);
    SET @idTraslado = SCOPE_IDENTITY();

    -- Paradas fusionadas por punto
    INSERT INTO TP_TRASLADO_PARADAS (idTraslado, idPunto, punto, orden, cantidadSube, cantidadBaja)
    SELECT @idTraslado, pt.idPunto, pl.punto,
           ROW_NUMBER() OVER (ORDER BY pl.posMin),
           pl.sube, pl.baja
    FROM (SELECT punto, MIN(solOrd * 2 + evOrd) AS posMin,
                 ISNULL(SUM(CASE WHEN tipo = 'S' THEN cantidad END), 0) AS sube,
                 ISNULL(SUM(CASE WHEN tipo = 'B' THEN cantidad END), 0) AS baja
          FROM @Eventos GROUP BY punto) pl
    LEFT JOIN TP_PUNTOS pt ON pt.nombre = pl.punto AND pt.activo = 1;

    -- Detalle parada <-> solicitud
    INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, tipo, cantidadPlaneada)
    SELECT p.idParada, e.idSolicitud, e.tipo, e.cantidad
    FROM @Eventos e
    JOIN TP_TRASLADO_PARADAS p ON p.idTraslado = @idTraslado AND p.punto = e.punto;

    UPDATE s
    SET s.idTraslado = @idTraslado, s.placa = @placa, s.estado = 'ASIGNADO'
    FROM TP_SOLICITUDES s JOIN @Ids i ON s.idSolicitud = i.idSolicitud;

    INSERT INTO TP_NOTIFICACIONES(idUsuario, titulo, mensaje, tipo)
    SELECT idUsuario, 'Nuevo servicio asignado', CONCAT('Traslado T-', @idTraslado, ' asignado a la unidad ', @placa), 'ASIGNACION'
    FROM TP_USUARIOS WHERE placa = @placa AND activo = 1;

    INSERT INTO TP_NOTIFICACIONES(idUsuario, titulo, mensaje, tipo)
    SELECT u.idUsuario, 'Solicitud asignada', CONCAT('Su solicitud #', s.idSolicitud, ' se unio al traslado T-', @idTraslado, ' (', @placa, ')'), 'ASIGNACION'
    FROM TP_SOLICITUDES s JOIN TP_USUARIOS u ON u.usuario = s.usuarioRegistra
    WHERE s.idTraslado = @idTraslado AND u.activo = 1;

    INSERT INTO TP_AUDITORIA(entidad, idEntidad, accion, usuario, detalle)
    VALUES ('TRASLADO', @idTraslado, 'UNIR_SOLICITUDES', JSON_VALUE(@json, '$.usuario'), @json);

    SELECT t.idTraslado, t.placa, t.ruta, t.estado
    FROM TP_TRASLADOS t WHERE t.idTraslado = @idTraslado
    FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- asignarUnidad: crea un traslado implicito con sus 2 paradas base
-- para que la asignacion simple A->B tambien tenga seguimiento.
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_asignarUnidad
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @id INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @placa NVARCHAR(20) = JSON_VALUE(@json, '$.placa');
    DECLARE @idUnidad INT = (SELECT idUnidad FROM TP_UNIDADES WHERE placa = @placa AND activa = 1);
    DECLARE @capacidad INT = (SELECT capacidad FROM TP_UNIDADES WHERE placa = @placa AND activa = 1);
    DECLARE @cantidad INT = (SELECT cantidad FROM TP_SOLICITUDES WHERE idSolicitud = @id);
    DECLARE @fecha DATE = (SELECT fechaProgramada FROM TP_SOLICITUDES WHERE idSolicitud = @id);

    IF @capacidad IS NULL BEGIN RAISERROR('Unidad inexistente o inactiva', 16, 1); RETURN; END
    IF @cantidad IS NULL BEGIN RAISERROR('Solicitud inexistente', 16, 1); RETURN; END
    IF NOT EXISTS (SELECT 1 FROM TP_SOLICITUDES WHERE idSolicitud = @id AND estado = 'PENDIENTE')
    BEGIN RAISERROR('La solicitud no esta pendiente de asignacion', 16, 1); RETURN; END

    DECLARE @ocupado INT =
        COALESCE((SELECT SUM(s.cantidad) FROM TP_SOLICITUDES s
                  WHERE s.placa = @placa AND s.fechaProgramada = @fecha
                    AND s.estado IN ('ASIGNADO', 'EN_RUTA') AND s.idSolicitud <> @id), 0)
      + COALESCE((SELECT SUM(su.cantidadAsignada) FROM TP_SOLICITUD_UNIDADES su
                  JOIN TP_SOLICITUDES s2 ON s2.idSolicitud = su.idSolicitud
                  WHERE su.idUnidad = @idUnidad AND s2.fechaProgramada = @fecha
                    AND su.estado IN ('ASIGNADO', 'EN_RUTA') AND s2.estado <> 'ANULADO'
                    AND s2.idSolicitud <> @id), 0);

    IF @cantidad > @capacidad - @ocupado
    BEGIN RAISERROR('La unidad no tiene cupo suficiente para esa fecha', 16, 1); RETURN; END

    DECLARE @pp NVARCHAR(300), @pl NVARCHAR(300);
    SELECT @pp = puntoPartida, @pl = puntoLlegada FROM TP_SOLICITUDES WHERE idSolicitud = @id;

    -- Traslado implicito (una sola solicitud)
    INSERT INTO TP_TRASLADOS (placa, ruta) VALUES (@placa, CONCAT(@pp, ' > ', @pl));
    DECLARE @idTraslado INT = SCOPE_IDENTITY();

    UPDATE TP_SOLICITUDES
    SET placa = @placa, estado = 'ASIGNADO', idTraslado = @idTraslado
    WHERE idSolicitud = @id;

    -- Paradas base A -> B (si partida = llegada, una sola parada con ambos)
    INSERT INTO TP_TRASLADO_PARADAS (idTraslado, idPunto, punto, orden, cantidadSube, cantidadBaja)
    SELECT @idTraslado, pt.idPunto, v.punto, v.orden, v.sube, v.baja
    FROM (VALUES (@pp, 1, @cantidad, CASE WHEN @pp = @pl THEN @cantidad ELSE 0 END),
                 (@pl, 2, 0, @cantidad)) v(punto, orden, sube, baja)
    LEFT JOIN TP_PUNTOS pt ON pt.nombre = v.punto AND pt.activo = 1
    WHERE NOT (@pp = @pl AND v.orden = 2);

    INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, tipo, cantidadPlaneada)
    SELECT p.idParada, @id,
           CASE WHEN p.orden = 1 THEN 'S' ELSE 'B' END, @cantidad
    FROM TP_TRASLADO_PARADAS p WHERE p.idTraslado = @idTraslado;
    -- Caso partida = llegada: un solo punto recibe ambos detalles
    IF @pp = @pl
        INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, tipo, cantidadPlaneada)
        SELECT TOP 1 p.idParada, @id, 'B', @cantidad
        FROM TP_TRASLADO_PARADAS p WHERE p.idTraslado = @idTraslado ORDER BY p.orden;

    INSERT INTO TP_NOTIFICACIONES(idUsuario, titulo, mensaje, tipo)
    SELECT idUsuario, 'Nuevo servicio asignado', CONCAT('Solicitud #', @id, ' asignada a la unidad ', @placa), 'ASIGNACION'
    FROM TP_USUARIOS WHERE placa = @placa AND activo = 1;

    INSERT INTO TP_NOTIFICACIONES(idUsuario, titulo, mensaje, tipo)
    SELECT u.idUsuario, 'Solicitud asignada', CONCAT('Su solicitud #', @id, ' fue asignada a la unidad ', @placa), 'ASIGNACION'
    FROM TP_SOLICITUDES s JOIN TP_USUARIOS u ON u.usuario = s.usuarioRegistra
    WHERE s.idSolicitud = @id AND u.activo = 1;

    INSERT INTO TP_AUDITORIA(entidad, idEntidad, accion, usuario, detalle)
    VALUES ('SOLICITUD', @id, 'ASIGNAR_UNIDAD', JSON_VALUE(@json, '$.usuario'), @json);

    SELECT * FROM TP_SOLICITUDES WHERE idSolicitud = @id FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- desasignarUnidad: si la solicitud esta en un traslado de una sola solicitud
-- (traslado implicito) lo disuelve; si el traslado tiene mas, usar separar.
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_desasignarUnidad
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
-- separarSolicitud: quita el aporte de la solicitud de las paradas pendientes
-- y su detalle parada <-> solicitud.
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_separarSolicitud
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @id INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @idTraslado INT = (SELECT idTraslado FROM TP_SOLICITUDES WHERE idSolicitud = @id);

    IF NOT EXISTS (SELECT 1 FROM TP_SOLICITUDES WHERE idSolicitud = @id AND idTraslado IS NOT NULL AND estado = 'ASIGNADO')
    BEGIN RAISERROR('Solo se pueden separar solicitudes asignadas a un traslado que aun no inician', 16, 1); RETURN; END

    UPDATE TP_SOLICITUDES
    SET idTraslado = NULL, placa = NULL, estado = 'PENDIENTE'
    WHERE idSolicitud = @id;

    -- Descontar su aporte planeado de las paradas pendientes
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

    IF @idTraslado IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TP_SOLICITUDES WHERE idTraslado = @idTraslado)
        UPDATE TP_TRASLADOS SET estado = 'ANULADO' WHERE idTraslado = @idTraslado;

    -- Recalcular la ruta textual con las paradas restantes
    IF @idTraslado IS NOT NULL
    BEGIN
        DECLARE @ruta NVARCHAR(2000);
        SELECT @ruta = STUFF((SELECT ' > ' + punto FROM TP_TRASLADO_PARADAS
                              WHERE idTraslado = @idTraslado ORDER BY orden
                              FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,3,'');
        UPDATE TP_TRASLADOS SET ruta = @ruta WHERE idTraslado = @idTraslado;
    END

    INSERT INTO TP_NOTIFICACIONES(idUsuario, titulo, mensaje, tipo)
    SELECT u.idUsuario, 'Solicitud separada', CONCAT('Su solicitud #', @id, ' fue separada del traslado y volvio a Pendiente'), 'ESTADO'
    FROM TP_SOLICITUDES s JOIN TP_USUARIOS u ON u.usuario = s.usuarioRegistra
    WHERE s.idSolicitud = @id AND u.activo = 1;
    INSERT INTO TP_AUDITORIA(entidad, idEntidad, accion, usuario, detalle)
    VALUES ('SOLICITUD', @id, 'SEPARAR', JSON_VALUE(@json, '$.usuario'), @json);

    SELECT * FROM TP_SOLICITUDES WHERE idSolicitud = @id FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- eliminarSolicitud (anular): descuenta su aporte de las paradas pendientes.
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_eliminarSolicitud
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

    INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle) VALUES('SOLICITUD',@id,'ANULAR',JSON_VALUE(@json,'$.usuario'),@json);

    SELECT @id AS idSolicitud, 'ANULADO' AS estado FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- acoplarSolicitud: fusiona los puntos de la solicitud con las paradas
-- pendientes del traslado (suma al punto existente o agrega al final).
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_acoplarSolicitud
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @idSolicitud INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @idTraslado INT = TRY_CAST(JSON_VALUE(@json, '$.idTraslado') AS INT);
    DECLARE @usuario NVARCHAR(50) = JSON_VALUE(@json, '$.usuario');
    DECLARE @placa NVARCHAR(20) = (SELECT placa FROM TP_TRASLADOS WHERE idTraslado = @idTraslado AND estado <> 'ANULADO');
    DECLARE @capacidad INT = (SELECT capacidad FROM TP_UNIDADES WHERE placa = @placa AND activa = 1);
    DECLARE @ocupacion INT = (SELECT COALESCE(SUM(cantidad), 0) FROM TP_SOLICITUDES WHERE idTraslado = @idTraslado AND estado <> 'ANULADO');
    DECLARE @cantidad INT = (SELECT cantidad FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud AND estado = 'PENDIENTE');
    IF @placa IS NULL OR @cantidad IS NULL BEGIN RAISERROR('Solicitud o traslado no disponible', 16, 1); RETURN; END

    IF EXISTS (SELECT 1 FROM TP_USUARIOS WHERE usuario = @usuario AND idrol = 'SPTRANS')
       AND NOT EXISTS (SELECT 1 FROM TP_SOLICITUDES s
                       JOIN TP_USUARIOS u ON u.usuario = @usuario AND u.idArea = s.idArea
                       WHERE s.idSolicitud = @idSolicitud)
    BEGIN RAISERROR('Solo puede acoplar solicitudes de su propia area', 16, 1); RETURN; END

    IF @ocupacion + @cantidad > @capacidad BEGIN RAISERROR('No existe cupo suficiente en el traslado', 16, 1); RETURN; END

    -- La ruta no debe estar en ejecucion para modificar sus paradas
    IF EXISTS (SELECT 1 FROM TP_TRASLADO_PARADAS
               WHERE idTraslado = @idTraslado AND estado <> 'PENDIENTE')
    BEGIN RAISERROR('El traslado ya inicio su recorrido', 16, 1); RETURN; END

    -- Compatibilidad geografica: origen y destino a <= 10 km de la ruta
    DECLARE @maxKm FLOAT = 10;
    DECLARE @latP DECIMAL(9,6), @lonP DECIMAL(9,6), @latL DECIMAL(9,6), @lonL DECIMAL(9,6);
    SELECT @latP = p.latitud, @lonP = p.longitud
    FROM TP_SOLICITUDES s JOIN TP_PUNTOS p ON p.nombre = s.puntoPartida AND p.activo = 1
    WHERE s.idSolicitud = @idSolicitud;
    SELECT @latL = p.latitud, @lonL = p.longitud
    FROM TP_SOLICITUDES s JOIN TP_PUNTOS p ON p.nombre = s.puntoLlegada AND p.activo = 1
    WHERE s.idSolicitud = @idSolicitud;

    IF OBJECT_ID('tempdb..#RUTA') IS NOT NULL DROP TABLE #RUTA;
    CREATE TABLE #RUTA (latitud DECIMAL(9,6), longitud DECIMAL(9,6));
    INSERT INTO #RUTA
        SELECT DISTINCT pt.latitud, pt.longitud
        FROM TP_TRASLADO_PARADAS pa JOIN TP_PUNTOS pt ON pt.nombre = pa.punto AND pt.activo = 1
        WHERE pa.idTraslado = @idTraslado AND pt.latitud IS NOT NULL AND pt.longitud IS NOT NULL;
    IF NOT EXISTS (SELECT 1 FROM #RUTA)
        INSERT INTO #RUTA
            SELECT DISTINCT pt.latitud, pt.longitud
            FROM TP_SOLICITUDES s JOIN TP_PUNTOS pt ON pt.activo = 1
                AND (pt.nombre = s.puntoPartida OR pt.nombre = s.puntoLlegada)
            WHERE s.idTraslado = @idTraslado AND pt.latitud IS NOT NULL AND pt.longitud IS NOT NULL;

    IF EXISTS (SELECT 1 FROM #RUTA) AND (@latP IS NOT NULL OR @latL IS NOT NULL)
    BEGIN
        IF @latP IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM #RUTA r
            WHERE 6371 * 2 * ASIN(SQRT(
                POWER(SIN(RADIANS(r.latitud - @latP) / 2.0), 2) +
                COS(RADIANS(@latP)) * COS(RADIANS(r.latitud)) *
                POWER(SIN(RADIANS(r.longitud - @lonP) / 2.0), 2))) <= @maxKm)
        BEGIN RAISERROR(N'El punto de partida esta a mas de 10 km de la ruta del traslado', 16, 1); RETURN; END

        IF @latL IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM #RUTA r
            WHERE 6371 * 2 * ASIN(SQRT(
                POWER(SIN(RADIANS(r.latitud - @latL) / 2.0), 2) +
                COS(RADIANS(@latL)) * COS(RADIANS(r.latitud)) *
                POWER(SIN(RADIANS(r.longitud - @lonL) / 2.0), 2))) <= @maxKm)
        BEGIN RAISERROR(N'El punto de llegada esta a mas de 10 km de la ruta del traslado', 16, 1); RETURN; END
    END
    DROP TABLE #RUTA;

    UPDATE TP_SOLICITUDES SET idTraslado = @idTraslado, placa = @placa, estado = 'ASIGNADO' WHERE idSolicitud = @idSolicitud;

    -- Fusionar puntos de la solicitud con las paradas pendientes
    DECLARE @pp NVARCHAR(300), @pl2 NVARCHAR(300), @maxOrden INT, @idParadaP INT;
    SELECT @pp = puntoPartida, @pl2 = puntoLlegada FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud;
    SELECT @maxOrden = ISNULL(MAX(orden), 0) FROM TP_TRASLADO_PARADAS WHERE idTraslado = @idTraslado;

    -- Punto de partida (suben)
    SELECT @idParadaP = MIN(idParada) FROM TP_TRASLADO_PARADAS
    WHERE idTraslado = @idTraslado AND punto = @pp AND estado = 'PENDIENTE';
    IF @idParadaP IS NULL
    BEGIN
        SET @maxOrden = @maxOrden + 1;
        INSERT INTO TP_TRASLADO_PARADAS (idTraslado, idPunto, punto, orden, cantidadSube, cantidadBaja)
        SELECT @idTraslado, pt.idPunto, @pp, @maxOrden, @cantidad, 0
        FROM TP_PUNTOS pt WHERE pt.nombre = @pp AND pt.activo = 1;
        IF @@ROWCOUNT = 0
            INSERT INTO TP_TRASLADO_PARADAS (idTraslado, punto, orden, cantidadSube, cantidadBaja)
            VALUES (@idTraslado, @pp, @maxOrden, @cantidad, 0);
        SET @idParadaP = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE TP_TRASLADO_PARADAS SET cantidadSube = cantidadSube + @cantidad WHERE idParada = @idParadaP;

    INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, tipo, cantidadPlaneada)
    VALUES (@idParadaP, @idSolicitud, 'S', @cantidad);

    -- Punto de llegada (bajan)
    SET @idParadaP = NULL;
    SELECT @idParadaP = MIN(idParada) FROM TP_TRASLADO_PARADAS
    WHERE idTraslado = @idTraslado AND punto = @pl2 AND estado = 'PENDIENTE';
    IF @idParadaP IS NULL
    BEGIN
        SET @maxOrden = @maxOrden + 1;
        INSERT INTO TP_TRASLADO_PARADAS (idTraslado, idPunto, punto, orden, cantidadSube, cantidadBaja)
        SELECT @idTraslado, pt.idPunto, @pl2, @maxOrden, 0, @cantidad
        FROM TP_PUNTOS pt WHERE pt.nombre = @pl2 AND pt.activo = 1;
        IF @@ROWCOUNT = 0
            INSERT INTO TP_TRASLADO_PARADAS (idTraslado, punto, orden, cantidadSube, cantidadBaja)
            VALUES (@idTraslado, @pl2, @maxOrden, 0, @cantidad);
        SET @idParadaP = SCOPE_IDENTITY();
    END
    ELSE
        UPDATE TP_TRASLADO_PARADAS SET cantidadBaja = cantidadBaja + @cantidad WHERE idParada = @idParadaP;

    INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, tipo, cantidadPlaneada)
    VALUES (@idParadaP, @idSolicitud, 'B', @cantidad);

    -- Recalcular la ruta textual
    DECLARE @ruta NVARCHAR(2000);
    SELECT @ruta = STUFF((SELECT ' > ' + punto FROM TP_TRASLADO_PARADAS
                          WHERE idTraslado = @idTraslado ORDER BY orden
                          FOR XML PATH(''),TYPE).value('.','NVARCHAR(MAX)'),1,3,'');
    UPDATE TP_TRASLADOS SET ruta = @ruta WHERE idTraslado = @idTraslado;

    INSERT INTO TP_NOTIFICACIONES(idUsuario, titulo, mensaje, tipo)
    SELECT idUsuario, 'Nuevo servicio asignado', CONCAT('Solicitud #', @idSolicitud, ' se acoplo al traslado T-', @idTraslado, ' (', @placa, ')'), 'ASIGNACION'
    FROM TP_USUARIOS WHERE placa = @placa AND activo = 1;
    INSERT INTO TP_AUDITORIA(entidad, idEntidad, accion, usuario, detalle)
    VALUES ('SOLICITUD', @idSolicitud, 'ACOPLAR', JSON_VALUE(@json, '$.usuario'), @json);
    SELECT * FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- cambiarEstado: no permite REALIZADO si la solicitud aun tiene paradas
-- de la ruta sin procesar (sus pasajeros no terminaron el recorrido).
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_cambiarEstado
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

    -- No se puede finalizar si sus pasajeros aun tienen paradas sin procesar
    IF @estado = 'REALIZADO' AND EXISTS (
        SELECT 1 FROM TP_PARADA_DETALLE d
        JOIN TP_TRASLADO_PARADAS p ON p.idParada = d.idParada
        WHERE d.idSolicitud = @id AND p.estado IN ('PENDIENTE','EN_PARADA'))
    BEGIN RAISERROR('La solicitud aun tiene paradas sin procesar en la ruta', 16, 1); RETURN; END

    IF @idSolicitudUnidad IS NOT NULL
    BEGIN
        UPDATE TP_SOLICITUD_UNIDADES SET estado = @estado WHERE idSolicitudUnidad = @idSolicitudUnidad AND idSolicitud = @id;
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
    END
    INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle) VALUES('SOLICITUD',@id,CONCAT('ESTADO_',@estado),JSON_VALUE(@json,'$.usuario'),@json);
    INSERT INTO TP_NOTIFICACIONES(idUsuario,titulo,mensaje,tipo)
    SELECT u.idUsuario, 'Estado de movilidad actualizado', CONCAT('La solicitud #',@id,' cambio a ',@estado), 'ESTADO'
    FROM TP_SOLICITUDES s JOIN TP_USUARIOS u ON u.usuario=s.usuarioRegistra WHERE s.idSolicitud=@id AND u.activo=1;
    SELECT * FROM TP_SOLICITUDES WHERE idSolicitud = @id FOR JSON PATH;
END
GO

-- ----------------------------------------------------------------------------
-- agregarPasajeros: si llega idParada, el extra se amarra a esa parada
-- (sube lo planeado si aun no se ejecuta, o lo real si esta en curso).
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_agregarPasajeros
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
                   WHERE idParada = @idParada AND idSolicitud = @idSolicitud AND tipo = 'S')
            UPDATE TP_PARADA_DETALLE
            SET cantidadPlaneada = cantidadPlaneada + @extra,
                cantidadReal = CASE WHEN cantidadReal IS NOT NULL THEN cantidadReal + @extra ELSE cantidadReal END
            WHERE idParada = @idParada AND idSolicitud = @idSolicitud AND tipo = 'S';
        ELSE IF EXISTS (SELECT 1 FROM TP_TRASLADO_PARADAS WHERE idParada = @idParada)
            INSERT INTO TP_PARADA_DETALLE (idParada, idSolicitud, tipo, cantidadPlaneada)
            VALUES (@idParada, @idSolicitud, 'S', @extra);
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

-- ----------------------------------------------------------------------------
-- listarTraslados: paradas con estado, conteos reales y detalle por solicitud
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_listarTraslados
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @fecha DATE = TRY_CAST(JSON_VALUE(@json, '$.fecha') AS DATE);

    SELECT t.idTraslado, t.placa, t.ruta, t.estado, t.fechaCreacion,
           JSON_QUERY((SELECT s.idSolicitud, s.nombre, s.horaProgramada, s.puntoPartida,
                   s.puntoLlegada, s.cantidad, s.motivo, s.realizado, s.estado, s.esEmergencia
            FROM TP_SOLICITUDES s WHERE s.idTraslado = t.idTraslado AND s.estado <> 'ANULADO'
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
-- listarServiciosConductor: paradas con idParada, estado y detalle
-- (el conductor necesita idParada para marcar llegada/registrar)
-- ----------------------------------------------------------------------------
CREATE OR ALTER PROCEDURE TRANSPORTE_listarServiciosConductor
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
                       FROM TP_TRASLADO_PARADAS p WHERE p.idTraslado = s.idTraslado
                       ORDER BY p.orden FOR JSON PATH)) AS paradas
    FROM TP_SOLICITUDES s
    LEFT JOIN TP_SOLICITUD_UNIDADES su ON su.idSolicitud=s.idSolicitud
    LEFT JOIN TP_UNIDADES u ON u.idUnidad=su.idUnidad
    LEFT JOIN TP_TRASLADOS t ON t.idTraslado = s.idTraslado
    WHERE (s.placa = @placa OR u.placa = @placa)
      AND s.estado <> 'ANULADO'
      AND (@fecha IS NULL OR s.fechaProgramada = @fecha)
    ORDER BY CASE WHEN COALESCE(su.esEmergencia,0)=1 OR s.prioridad='EMERGENCIA' THEN 0
                  WHEN s.prioridad='ALTA' THEN 1 ELSE 2 END,
             s.horaProgramada, s.idSolicitud
    FOR JSON PATH;
END
GO
