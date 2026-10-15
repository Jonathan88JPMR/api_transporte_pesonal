
CREATE   PROCEDURE TRANSPORTE_administrarCatalogo
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
            IF @id IS NULL INSERT INTO TP_AREAS(nombre) VALUES(JSON_VALUE(@json, '$.nombre'));
            ELSE UPDATE TP_AREAS SET nombre = JSON_VALUE(@json, '$.nombre'), activo = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activo) WHERE idArea = @id;
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_AREAS SET activo = 0 WHERE idArea = @id;
        SELECT idArea, nombre, activo FROM TP_AREAS ORDER BY nombre FOR JSON PATH; RETURN;
    END
    IF @entidad = 'UNIDAD'
    BEGIN
        IF @accion = 'GUARDAR'
            IF @id IS NULL INSERT INTO TP_UNIDADES(placa, capacidad) VALUES(JSON_VALUE(@json, '$.placa'), TRY_CAST(JSON_VALUE(@json, '$.capacidad') AS INT));
            ELSE UPDATE TP_UNIDADES SET placa = JSON_VALUE(@json, '$.placa'), capacidad = TRY_CAST(JSON_VALUE(@json, '$.capacidad') AS INT), activa = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.activo') AS BIT), activa) WHERE idUnidad = @id;
        ELSE IF @accion = 'ELIMINAR' UPDATE TP_UNIDADES SET activa = 0 WHERE idUnidad = @id;
        SELECT idUnidad, placa, capacidad, activa AS activo FROM TP_UNIDADES ORDER BY placa FOR JSON PATH; RETURN;
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
            IF @id IS NULL INSERT INTO TP_USUARIOS(usuario, claveHash, nombre, idrol, placa, area, idArea)
                VALUES(@usuarioNuevo, JSON_VALUE(@json, '$.claveHash'),
                       JSON_VALUE(@json, '$.nombre'), @idrolNuevo, JSON_VALUE(@json, '$.placa'), @areaNombre, @idAreaU);
            ELSE UPDATE TP_USUARIOS SET nombre = JSON_VALUE(@json, '$.nombre'), idrol = @idrolNuevo,
                 placa = JSON_VALUE(@json, '$.placa'), area = @areaNombre, idArea = @idAreaU,
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
        SELECT idUsuario, usuario, nombre, idrol, placa, area, idArea, activo, eliminado, fechaEliminado, usuarioElimina
        FROM TP_USUARIOS
        WHERE (@rolSol <> 'COTRANS' OR @rolSol IS NULL OR idrol IN ('CHTRANS','SPTRANS'))
        ORDER BY nombre FOR JSON PATH; RETURN;
    END
    RAISERROR(N'Entidad administrativa invalida', 16, 1);
END


(1 rows affected)
