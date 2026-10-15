/* ============================================================
   022 — Unidades propias (flota mixta PROPIA/TERCERO)
   - TP_UNIDADES: tipoPropiedad (PROPIA/TERCERO), tipoVehiculo,
     marca, modelo, anio, estadoOperativo (OPERATIVA/MANTENIMIENTO/
     FUERA_SERVICIO), idConductor (usuario CHTRANS asignado).
   - administrarCatalogo UNIDAD: formulario enriquecido; TERCERO
     exige transportista, PROPIA lo deja vacio; no se desactiva
     una unidad con traslados activos.
   - asignarUnidad / asignarMultiplesUnidades: solo asignables
     unidades activas Y en estadoOperativo = 'OPERATIVA'.
   Ejecutar con: sqlcmd -f 65001 (UTF-8)
   ============================================================ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('TP_UNIDADES','tipoPropiedad') IS NULL
    ALTER TABLE TP_UNIDADES ADD tipoPropiedad NVARCHAR(10) NOT NULL DEFAULT 'PROPIA';
GO
IF COL_LENGTH('TP_UNIDADES','tipoVehiculo') IS NULL
    ALTER TABLE TP_UNIDADES ADD tipoVehiculo NVARCHAR(30) NULL;
GO
IF COL_LENGTH('TP_UNIDADES','marca') IS NULL
    ALTER TABLE TP_UNIDADES ADD marca NVARCHAR(40) NULL;
GO
IF COL_LENGTH('TP_UNIDADES','modelo') IS NULL
    ALTER TABLE TP_UNIDADES ADD modelo NVARCHAR(40) NULL;
GO
IF COL_LENGTH('TP_UNIDADES','anio') IS NULL
    ALTER TABLE TP_UNIDADES ADD anio INT NULL;
GO
IF COL_LENGTH('TP_UNIDADES','estadoOperativo') IS NULL
    ALTER TABLE TP_UNIDADES ADD estadoOperativo NVARCHAR(20) NOT NULL DEFAULT 'OPERATIVA';
GO
IF COL_LENGTH('TP_UNIDADES','idConductor') IS NULL
    ALTER TABLE TP_UNIDADES ADD idConductor INT NULL REFERENCES TP_USUARIOS(idUsuario);
GO

/* Catálogo administrable — versión completa con UNIDAD enriquecida.
   El resto de entidades queda igual que la versión vigente. */
CREATE OR ALTER PROCEDURE TRANSPORTE_administrarCatalogo
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @entidad NVARCHAR(20) = UPPER(JSON_VALUE(@json, '$.entidad'));
    DECLARE @accion NVARCHAR(20) = UPPER(JSON_VALUE(@json, '$.accion'));
    DECLARE @id INT = TRY_CAST(JSON_VALUE(@json, '$.id') AS INT);
    DECLARE @actor NVARCHAR(50) = COALESCE(JSON_VALUE(@json, '$.actor'), JSON_VALUE(@json, '$.usuario'));
    IF @accion <> 'LISTAR' INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle) VALUES(@entidad,@id,@accion,@actor,@json);
    IF @entidad = 'PUNTO'
    BEGIN
        IF @accion = 'GUARDAR'
            IF @id IS NULL INSERT INTO TP_PUNTOS(nombre, latitud, longitud) VALUES(JSON_VALUE(@json, '$.nombre'), TRY_CAST(JSON_VALUE(@json, '$.latitud') AS DECIMAL(9,6)), TRY_CAST(JSON_VALUE(@json, '$.longitud') AS DECIMAL(9,6)));
            ELSE UPDATE TP_PUNTOS SET nombre = JSON_VALUE(@json, '$.nombre'), latitud = TRY_CAST(JSON_VALUE(@json, '$.latitud') AS DECIMAL(9,6)), longitud = TRY_CAST(JSON_VALUE(@json, '$.longitud') AS DECIMAL(9,6)), activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo) WHERE idPunto = @id;
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_PUNTOS SET activo = 0 WHERE idPunto = @id;
        SELECT idPunto, nombre, latitud, longitud, activo FROM TP_PUNTOS ORDER BY nombre FOR JSON PATH; RETURN;
    END
    IF @entidad = 'MOTIVO'
    BEGIN
        IF @accion = 'GUARDAR'
            IF @id IS NULL INSERT INTO TP_MOTIVOS(nombre) VALUES(JSON_VALUE(@json, '$.nombre'));
            ELSE UPDATE TP_MOTIVOS SET nombre = JSON_VALUE(@json, '$.nombre'), activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo) WHERE idMotivo = @id;
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_MOTIVOS SET activo = 0 WHERE idMotivo = @id;
        SELECT idMotivo, nombre, activo FROM TP_MOTIVOS ORDER BY nombre FOR JSON PATH; RETURN;
    END
    -- Catálogo de tipos de vehículo (select del mantenedor de unidades)
    IF @entidad = 'TIPO_VEHICULO'
    BEGIN
        IF @accion = 'GUARDAR'
        BEGIN
            IF JSON_VALUE(@json, '$.nombre') IS NULL
            BEGIN RAISERROR(N'El nombre del tipo es obligatorio',16,1); RETURN; END
            IF @id IS NULL AND EXISTS(SELECT 1 FROM TP_TIPOS_VEHICULO WHERE nombre = JSON_VALUE(@json, '$.nombre'))
            BEGIN RAISERROR(N'Ya existe un tipo de vehículo con ese nombre',16,1); RETURN; END
            IF @id IS NULL INSERT INTO TP_TIPOS_VEHICULO(nombre) VALUES(JSON_VALUE(@json, '$.nombre'));
            ELSE UPDATE TP_TIPOS_VEHICULO SET nombre = JSON_VALUE(@json, '$.nombre'),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo) WHERE idTipoVehiculo = @id;
        END
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_TIPOS_VEHICULO SET activo = 0 WHERE idTipoVehiculo = @id;
        SELECT idTipoVehiculo, nombre, activo FROM TP_TIPOS_VEHICULO ORDER BY nombre FOR JSON PATH; RETURN;
    END
    IF @entidad = 'AREA'
    BEGIN
        IF @accion = 'GUARDAR'
            IF @id IS NULL INSERT INTO TP_AREAS(nombre, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor)
                VALUES(JSON_VALUE(@json, '$.nombre'), JSON_VALUE(@json, '$.ceco'), JSON_VALUE(@json, '$.cuenta'),
                       JSON_VALUE(@json, '$.idproyecto'), JSON_VALUE(@json, '$.codfundo'),
                       JSON_VALUE(@json, '$.idcultivo'), JSON_VALUE(@json, '$.idlabor'));
            ELSE UPDATE TP_AREAS SET nombre = JSON_VALUE(@json, '$.nombre'),
                 ceco = JSON_VALUE(@json, '$.ceco'), cuenta = JSON_VALUE(@json, '$.cuenta'),
                 idproyecto = JSON_VALUE(@json, '$.idproyecto'), codfundo = JSON_VALUE(@json, '$.codfundo'),
                 idcultivo = JSON_VALUE(@json, '$.idcultivo'), idlabor = JSON_VALUE(@json, '$.idlabor'),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo) WHERE idArea = @id;
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_AREAS SET activo = 0 WHERE idArea = @id;
        SELECT idArea, nombre, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, activo
        FROM TP_AREAS ORDER BY nombre FOR JSON PATH; RETURN;
    END
    IF @entidad = 'CECO'
    BEGIN
        IF @accion = 'GUARDAR'
        BEGIN
            IF JSON_VALUE(@json, '$.ceco') IS NULL
            BEGIN RAISERROR(N'El centro de costo es obligatorio',16,1); RETURN; END
            IF @id IS NULL AND EXISTS(SELECT 1 FROM TP_CECOS WHERE ceco = JSON_VALUE(@json, '$.ceco'))
            BEGIN RAISERROR(N'Ya existe un centro de costo con ese codigo',16,1); RETURN; END
            IF @id IS NULL INSERT INTO TP_CECOS(ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, descripcion)
                VALUES(JSON_VALUE(@json, '$.ceco'), JSON_VALUE(@json, '$.cuenta'), JSON_VALUE(@json, '$.idproyecto'),
                       JSON_VALUE(@json, '$.codfundo'), JSON_VALUE(@json, '$.idcultivo'), JSON_VALUE(@json, '$.idlabor'),
                       JSON_VALUE(@json, '$.descripcion'));
            ELSE UPDATE TP_CECOS SET ceco = JSON_VALUE(@json, '$.ceco'), cuenta = JSON_VALUE(@json, '$.cuenta'),
                 idproyecto = JSON_VALUE(@json, '$.idproyecto'), codfundo = JSON_VALUE(@json, '$.codfundo'),
                 idcultivo = JSON_VALUE(@json, '$.idcultivo'), idlabor = JSON_VALUE(@json, '$.idlabor'),
                 descripcion = JSON_VALUE(@json, '$.descripcion'),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo)
                 WHERE idCeco = @id;
        END
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_CECOS SET activo = 0 WHERE idCeco = @id;
        SELECT idCeco, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, descripcion, activo
        FROM TP_CECOS ORDER BY ceco FOR JSON PATH; RETURN;
    END
    IF @entidad = 'UNIDAD'
    BEGIN
        IF @accion = 'GUARDAR'
        BEGIN
            DECLARE @placaU NVARCHAR(20) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@json, '$.placa'))), '');
            DECLARE @tipoProp NVARCHAR(10) = UPPER(COALESCE(NULLIF(JSON_VALUE(@json, '$.tipoPropiedad'), ''), 'PROPIA'));
            DECLARE @estadoOp NVARCHAR(20) = UPPER(COALESCE(NULLIF(JSON_VALUE(@json, '$.estadoOperativo'), ''), 'OPERATIVA'));
            DECLARE @idTransp INT = TRY_CAST(JSON_VALUE(@json, '$.idTransportista') AS INT);
            DECLARE @idCond INT = TRY_CAST(JSON_VALUE(@json, '$.idConductor') AS INT);
            IF @placaU IS NULL
            BEGIN RAISERROR(N'La placa es obligatoria',16,1); RETURN; END
            IF @tipoProp NOT IN ('PROPIA','TERCERO')
            BEGIN RAISERROR(N'tipoPropiedad debe ser PROPIA o TERCERO',16,1); RETURN; END
            IF @estadoOp NOT IN ('OPERATIVA','MANTENIMIENTO','FUERA_SERVICIO')
            BEGIN RAISERROR(N'estadoOperativo debe ser OPERATIVA, MANTENIMIENTO o FUERA_SERVICIO',16,1); RETURN; END
            -- flota mixta: la unidad de tercero exige su transportista; la propia no lleva
            IF @tipoProp = 'TERCERO' AND @idTransp IS NULL
            BEGIN RAISERROR(N'Una unidad de tercero requiere su transportista',16,1); RETURN; END
            IF @tipoProp = 'PROPIA' SET @idTransp = NULL;
            IF @idCond IS NOT NULL AND NOT EXISTS(
                SELECT 1 FROM TP_USUARIOS WHERE idUsuario = @idCond AND idrol = 'CHTRANS' AND activo = 1 AND eliminado = 0)
            BEGIN RAISERROR(N'El conductor asignado no es valido',16,1); RETURN; END
            -- el tipo de vehículo debe existir en el catálogo TP_TIPOS_VEHICULO
            DECLARE @tipoVeh NVARCHAR(30) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@json, '$.tipoVehiculo'))), '');
            IF @tipoVeh IS NOT NULL AND NOT EXISTS(
                SELECT 1 FROM TP_TIPOS_VEHICULO WHERE nombre = @tipoVeh AND activo = 1)
            BEGIN RAISERROR(N'El tipo de vehículo no existe en el catálogo',16,1); RETURN; END
            IF @id IS NULL AND EXISTS(SELECT 1 FROM TP_UNIDADES WHERE placa = @placaU)
            BEGIN RAISERROR(N'Ya existe una unidad con esa placa',16,1); RETURN; END
            IF @id IS NULL INSERT INTO TP_UNIDADES(placa, capacidad, tipoPropiedad, tipoVehiculo,
                    marca, modelo, anio, estadoOperativo, idConductor, idTransportista)
                VALUES(@placaU, TRY_CAST(JSON_VALUE(@json, '$.capacidad') AS INT), @tipoProp,
                       @tipoVeh, JSON_VALUE(@json, '$.marca'),
                       JSON_VALUE(@json, '$.modelo'), TRY_CAST(JSON_VALUE(@json, '$.anio') AS INT),
                       @estadoOp, @idCond, @idTransp);
            ELSE UPDATE TP_UNIDADES SET placa = @placaU,
                 capacidad = TRY_CAST(JSON_VALUE(@json, '$.capacidad') AS INT),
                 tipoPropiedad = @tipoProp, tipoVehiculo = @tipoVeh,
                 marca = JSON_VALUE(@json, '$.marca'), modelo = JSON_VALUE(@json, '$.modelo'),
                 anio = TRY_CAST(JSON_VALUE(@json, '$.anio') AS INT),
                 estadoOperativo = @estadoOp, idConductor = @idCond, idTransportista = @idTransp,
                 activa = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activa)
                 WHERE idUnidad = @id;
        END
        ELSE IF @accion = 'ELIMINAR'
        BEGIN
            -- no se puede desactivar una unidad con traslados activos
            IF EXISTS(SELECT 1 FROM TP_UNIDADES u JOIN TP_TRASLADOS t ON t.placa = u.placa
                      WHERE u.idUnidad = @id AND t.estado IN ('PENDIENTE','ASIGNADO','EN_RUTA'))
            BEGIN RAISERROR(N'La unidad tiene traslados activos; no se puede desactivar',16,1); RETURN; END
            UPDATE TP_UNIDADES SET activa = 0 WHERE idUnidad = @id;
        END
        SELECT u.idUnidad, u.placa, u.capacidad, u.tipoPropiedad, u.tipoVehiculo, u.marca,
               u.modelo, u.anio, u.estadoOperativo, u.idConductor, c.nombre AS conductor,
               u.idTransportista, t.razonSocial AS transportista, u.activa AS activo
        FROM TP_UNIDADES u
        LEFT JOIN TP_TRANSPORTISTAS t ON t.idTransportista = u.idTransportista
        LEFT JOIN TP_USUARIOS c ON c.idUsuario = u.idConductor
        ORDER BY u.placa FOR JSON PATH; RETURN;
    END
    IF @entidad = 'TRANSPORTISTA'
    BEGIN
        IF @accion = 'GUARDAR'
        BEGIN
            IF @id IS NULL AND EXISTS(SELECT 1 FROM TP_TRANSPORTISTAS WHERE ruc = JSON_VALUE(@json, '$.ruc'))
            BEGIN RAISERROR(N'Ya existe un transportista con ese RUC',16,1); RETURN; END
            IF @id IS NULL INSERT INTO TP_TRANSPORTISTAS(ruc, razonSocial, telefono, email)
                VALUES(JSON_VALUE(@json, '$.ruc'), JSON_VALUE(@json, '$.razonSocial'),
                       JSON_VALUE(@json, '$.telefono'), JSON_VALUE(@json, '$.email'));
            ELSE UPDATE TP_TRANSPORTISTAS SET ruc = JSON_VALUE(@json, '$.ruc'),
                 razonSocial = JSON_VALUE(@json, '$.razonSocial'), telefono = JSON_VALUE(@json, '$.telefono'),
                 email = JSON_VALUE(@json, '$.email'),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo)
                 WHERE idTransportista = @id;
        END
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_TRANSPORTISTAS SET activo = 0 WHERE idTransportista = @id;
        SELECT idTransportista, ruc, razonSocial, telefono, email, activo
        FROM TP_TRANSPORTISTAS ORDER BY razonSocial FOR JSON PATH; RETURN;
    END
    IF @entidad = 'TARIFA'
    BEGIN
        IF @accion = 'GUARDAR'
        BEGIN
            IF JSON_VALUE(@json, '$.idTransportista') IS NULL OR TRY_CAST(JSON_VALUE(@json, '$.monto') AS DECIMAL(12,2)) IS NULL
            BEGIN RAISERROR(N'Transportista y monto son obligatorios',16,1); RETURN; END
            IF @id IS NULL INSERT INTO TP_TARIFAS(idTransportista, puntoOrigen, puntoDestino, monto, porPasajero)
                VALUES(TRY_CAST(JSON_VALUE(@json, '$.idTransportista') AS INT),
                       NULLIF(JSON_VALUE(@json, '$.puntoOrigen'), ''), NULLIF(JSON_VALUE(@json, '$.puntoDestino'), ''),
                       TRY_CAST(JSON_VALUE(@json, '$.monto') AS DECIMAL(12,2)),
                       COALESCE(TRY_CAST(JSON_VALUE(@json, '$.porPasajero') AS BIT), 0));
            ELSE UPDATE TP_TARIFAS SET idTransportista = TRY_CAST(JSON_VALUE(@json, '$.idTransportista') AS INT),
                 puntoOrigen = NULLIF(JSON_VALUE(@json, '$.puntoOrigen'), ''),
                 puntoDestino = NULLIF(JSON_VALUE(@json, '$.puntoDestino'), ''),
                 monto = TRY_CAST(JSON_VALUE(@json, '$.monto') AS DECIMAL(12,2)),
                 porPasajero = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.porPasajero') AS BIT), porPasajero),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo)
                 WHERE idTarifa = @id;
        END
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_TARIFAS SET activo = 0 WHERE idTarifa = @id;
        SELECT tf.idTarifa, tf.idTransportista, t.razonSocial AS transportista,
               tf.puntoOrigen, tf.puntoDestino, tf.monto, tf.porPasajero, tf.activo
        FROM TP_TARIFAS tf JOIN TP_TRANSPORTISTAS t ON t.idTransportista = tf.idTransportista
        ORDER BY t.razonSocial, tf.puntoOrigen FOR JSON PATH; RETURN;
    END
    IF @entidad = 'USUARIO'
    BEGIN
        DECLARE @idAreaU INT = TRY_CAST(JSON_VALUE(@json, '$.idArea') AS INT);
        DECLARE @areaNombre NVARCHAR(100) = COALESCE(
            (SELECT nombre FROM TP_AREAS WHERE idArea = @idAreaU),
            JSON_VALUE(@json, '$.area'));
        DECLARE @rolSol NVARCHAR(10) = JSON_VALUE(@json, '$.rolSolicitante');
        DECLARE @idrolNuevo NVARCHAR(10) = JSON_VALUE(@json, '$.idrol');
        DECLARE @usuarioNuevo NVARCHAR(50) = JSON_VALUE(@json, '$.usuario');
        DECLARE @rolObj NVARCHAR(10), @usuarioObj NVARCHAR(50), @eliminadoObj BIT, @placaObj NVARCHAR(20);
        IF @id IS NOT NULL
            SELECT @rolObj = idrol, @usuarioObj = usuario, @eliminadoObj = eliminado, @placaObj = placa
            FROM TP_USUARIOS WHERE idUsuario = @id;
        IF @accion = 'GUARDAR'
        BEGIN
            -- un coordinador solo gestiona conductores y supervisores
            IF @rolSol = 'COTRANS' AND (@idrolNuevo IS NULL OR @idrolNuevo NOT IN ('CHTRANS','SPTRANS')
                OR (@id IS NOT NULL AND @rolObj NOT IN ('CHTRANS','SPTRANS')))
            BEGIN RAISERROR(N'El coordinador solo puede gestionar conductores y supervisores',16,1); RETURN; END
            IF @id IS NOT NULL AND @eliminadoObj = 1
            BEGIN RAISERROR(N'El usuario esta eliminado; no se puede editar',16,1); RETURN; END
            IF @id IS NULL AND EXISTS(SELECT 1 FROM TP_USUARIOS WHERE usuario = @usuarioNuevo)
            BEGIN RAISERROR(N'Ya existe un usuario con ese nombre de acceso',16,1); RETURN; END
            IF @id IS NULL INSERT INTO TP_USUARIOS(usuario, claveHash, nombre, idrol, placa, area, idArea, dni)
                VALUES(@usuarioNuevo, JSON_VALUE(@json, '$.claveHash'),
                       JSON_VALUE(@json, '$.nombre'), @idrolNuevo, JSON_VALUE(@json, '$.placa'), @areaNombre, @idAreaU,
                       JSON_VALUE(@json, '$.dni'));
            ELSE UPDATE TP_USUARIOS SET nombre = JSON_VALUE(@json, '$.nombre'), idrol = @idrolNuevo,
                 placa = JSON_VALUE(@json, '$.placa'), area = @areaNombre, idArea = @idAreaU,
                 dni = JSON_VALUE(@json, '$.dni'),
                 activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo),
                 claveHash = COALESCE(NULLIF(JSON_VALUE(@json, '$.claveHash'), ''), claveHash)
                 WHERE idUsuario = @id;
        END
        ELSE IF @accion = 'ELIMINAR'
        BEGIN
            IF @id IS NULL OR @rolObj IS NULL
            BEGIN RAISERROR(N'Usuario no encontrado',16,1); RETURN; END
            IF @eliminadoObj = 1
            BEGIN RAISERROR(N'El usuario ya esta eliminado',16,1); RETURN; END
            IF @usuarioObj = @actor
            BEGIN RAISERROR(N'No puede eliminar su propio usuario',16,1); RETURN; END
            IF @rolSol = 'COTRANS' AND @rolObj NOT IN ('CHTRANS','SPTRANS')
            BEGIN RAISERROR(N'El coordinador solo puede eliminar conductores y supervisores',16,1); RETURN; END
            -- conductor con traslados activos no se puede eliminar
            IF @rolObj = 'CHTRANS' AND @placaObj IS NOT NULL AND EXISTS(
                SELECT 1 FROM TP_TRASLADOS t WHERE t.placa = @placaObj AND t.estado IN ('PENDIENTE','ASIGNADO','EN_RUTA'))
            BEGIN RAISERROR(N'El conductor tiene traslados activos; no se puede eliminar',16,1); RETURN; END
            -- supervisor con solicitudes activas no se puede eliminar
            IF @rolObj = 'SPTRANS' AND EXISTS(
                SELECT 1 FROM TP_SOLICITUDES s WHERE s.usuarioRegistra = @usuarioObj AND s.estado IN ('PENDIENTE','ASIGNADO','EN_RUTA'))
            BEGIN RAISERROR(N'El supervisor tiene solicitudes activas; no se puede eliminar',16,1); RETURN; END
            UPDATE TP_USUARIOS SET eliminado = 1, activo = 0,
                fechaEliminado = GETDATE(), usuarioElimina = @actor
                WHERE idUsuario = @id;
        END
        -- LISTAR: el coordinador solo ve conductores y supervisores
        SELECT idUsuario, usuario, nombre, idrol, placa, area, idArea, dni, activo, eliminado, fechaEliminado, usuarioElimina
        FROM TP_USUARIOS
        WHERE (@rolSol <> 'COTRANS' OR @rolSol IS NULL OR idrol IN ('CHTRANS','SPTRANS'))
        ORDER BY nombre FOR JSON PATH; RETURN;
    END
    RAISERROR(N'Entidad administrativa invalida', 16, 1);
END
GO

/* asignarUnidad: además de activa=1 exige estadoOperativo='OPERATIVA'
   (una unidad en mantenimiento o fuera de servicio no puede asignarse). */
CREATE OR ALTER PROCEDURE TRANSPORTE_asignarUnidad
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @id INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @placa NVARCHAR(20) = JSON_VALUE(@json, '$.placa');
    DECLARE @idUnidad INT = (SELECT idUnidad FROM TP_UNIDADES WHERE placa = @placa AND activa = 1 AND estadoOperativo = 'OPERATIVA');
    DECLARE @capacidad INT = (SELECT capacidad FROM TP_UNIDADES WHERE placa = @placa AND activa = 1 AND estadoOperativo = 'OPERATIVA');
    DECLARE @cantidad INT = (SELECT cantidad FROM TP_SOLICITUDES WHERE idSolicitud = @id);
    DECLARE @fecha DATE = (SELECT fechaProgramada FROM TP_SOLICITUDES WHERE idSolicitud = @id);

    IF @capacidad IS NULL BEGIN RAISERROR('Unidad inexistente, inactiva o no operativa', 16, 1); RETURN; END
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

/* asignarMultiplesUnidades: mismo control, cada unidad de la distribución
   debe existir, estar activa y en estadoOperativo='OPERATIVA'. */
CREATE OR ALTER PROCEDURE TRANSPORTE_asignarMultiplesUnidades
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

    -- Cada unidad debe existir, estar activa/operativa y tener cupo libre suficiente
    IF EXISTS (
        SELECT 1
        FROM OPENJSON(@json, '$.unidades') j
        LEFT JOIN TP_UNIDADES u ON u.placa = JSON_VALUE(j.value, '$.placa') AND u.activa = 1 AND u.estadoOperativo = 'OPERATIVA'
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
    BEGIN RAISERROR('Una unidad no existe, no esta operativa o no tiene cupo suficiente para esa fecha', 16, 1); RETURN; END

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
