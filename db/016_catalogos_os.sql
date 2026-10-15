/* ============================================================
   016 — Catálogos para Órdenes de Servicio (OS)
   - TP_TRANSPORTISTAS: empresas terceras dueñas de las unidades
   - TP_TARIFAS: tarifa por transportista y ruta (por viaje o por pasajero)
   - TP_UNIDADES.idTransportista: a qué transportista pertenece la unidad
   - TP_AREAS: ceco/cuenta/proyecto/fundo/cultivo/labor para distribución del costo
   - TP_USUARIOS.dni: documento que firma la OS (usuarioGenera en logística)
   - TP_PARAMETROS: ruc_empresa / idempresa para la cabecera de la OS
   - TRANSPORTE_administrarCatalogo: entidades TRANSPORTISTA y TARIFA
   Ejecutar con: sqlcmd -f 65001 (UTF-8)
   ============================================================ */
SET NOCOUNT ON;

IF OBJECT_ID('TP_TRANSPORTISTAS') IS NULL
CREATE TABLE TP_TRANSPORTISTAS (
    idTransportista INT IDENTITY(1,1) PRIMARY KEY,
    ruc             NVARCHAR(11)  NOT NULL,
    razonSocial     NVARCHAR(150) NOT NULL,
    telefono        NVARCHAR(20)  NULL,
    email           NVARCHAR(100) NULL,
    activo          BIT NOT NULL DEFAULT 1,
    fechaCreacion   DATETIME NOT NULL DEFAULT GETDATE()
);

IF OBJECT_ID('TP_TARIFAS') IS NULL
CREATE TABLE TP_TARIFAS (
    idTarifa        INT IDENTITY(1,1) PRIMARY KEY,
    idTransportista INT NOT NULL REFERENCES TP_TRANSPORTISTAS(idTransportista),
    puntoOrigen     NVARCHAR(120) NULL,   -- NULL = tarifa por defecto del transportista
    puntoDestino    NVARCHAR(120) NULL,
    monto           DECIMAL(12,2) NOT NULL,
    porPasajero     BIT NOT NULL DEFAULT 0, -- 0 = por viaje, 1 = por pasajero
    activo          BIT NOT NULL DEFAULT 1,
    fechaCreacion   DATETIME NOT NULL DEFAULT GETDATE()
);

IF COL_LENGTH('TP_UNIDADES','idTransportista') IS NULL
    ALTER TABLE TP_UNIDADES ADD idTransportista INT NULL REFERENCES TP_TRANSPORTISTAS(idTransportista);

IF COL_LENGTH('TP_USUARIOS','dni') IS NULL
    ALTER TABLE TP_USUARIOS ADD dni NVARCHAR(15) NULL;

-- Imputación del costo por área (contrato detalle OS de logística)
IF COL_LENGTH('TP_AREAS','ceco')       IS NULL ALTER TABLE TP_AREAS ADD ceco       NVARCHAR(20) NULL;
IF COL_LENGTH('TP_AREAS','cuenta')     IS NULL ALTER TABLE TP_AREAS ADD cuenta     NVARCHAR(30) NULL;
IF COL_LENGTH('TP_AREAS','idproyecto') IS NULL ALTER TABLE TP_AREAS ADD idproyecto NVARCHAR(20) NULL;
IF COL_LENGTH('TP_AREAS','codfundo')   IS NULL ALTER TABLE TP_AREAS ADD codfundo   NVARCHAR(20) NULL;
IF COL_LENGTH('TP_AREAS','idcultivo')  IS NULL ALTER TABLE TP_AREAS ADD idcultivo  NVARCHAR(10) NULL;
IF COL_LENGTH('TP_AREAS','idlabor')    IS NULL ALTER TABLE TP_AREAS ADD idlabor    NVARCHAR(10) NULL;

IF OBJECT_ID('TP_PARAMETROS') IS NULL
CREATE TABLE TP_PARAMETROS (
    clave NVARCHAR(50) PRIMARY KEY,
    valor NVARCHAR(200) NULL
);
IF NOT EXISTS (SELECT 1 FROM TP_PARAMETROS WHERE clave = 'RUC_EMPRESA') INSERT INTO TP_PARAMETROS VALUES('RUC_EMPRESA','');
IF NOT EXISTS (SELECT 1 FROM TP_PARAMETROS WHERE clave = 'ID_EMPRESA')  INSERT INTO TP_PARAMETROS VALUES('ID_EMPRESA','');
GO

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
    IF @entidad = 'UNIDAD'
    BEGIN
        IF @accion = 'GUARDAR'
            IF @id IS NULL INSERT INTO TP_UNIDADES(placa, capacidad, idTransportista)
                VALUES(JSON_VALUE(@json, '$.placa'), TRY_CAST(JSON_VALUE(@json, '$.capacidad') AS INT),
                       TRY_CAST(JSON_VALUE(@json, '$.idTransportista') AS INT));
            ELSE UPDATE TP_UNIDADES SET placa = JSON_VALUE(@json, '$.placa'),
                 capacidad = TRY_CAST(JSON_VALUE(@json, '$.capacidad') AS INT),
                 idTransportista = TRY_CAST(JSON_VALUE(@json, '$.idTransportista') AS INT),
                 activa = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activa) WHERE idUnidad = @id;
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_UNIDADES SET activa = 0 WHERE idUnidad = @id;
        SELECT u.idUnidad, u.placa, u.capacidad, u.idTransportista, t.razonSocial AS transportista, u.activa AS activo
        FROM TP_UNIDADES u LEFT JOIN TP_TRANSPORTISTAS t ON t.idTransportista = u.idTransportista
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
