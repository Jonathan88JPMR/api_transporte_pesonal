/* ============================================================
   023 — Comunicados de "horas sin servicio"
   - TP_COMUNICADOS: aviso del coordinador de que en un rango de
     horas de un día no habrá servicio (unidades en actividades
     programadas). Bloquea la creación de solicitudes en ese rango.
   - TRANSPORTE_administrarComunicado: LISTAR/GUARDAR/ELIMINAR con
     fan-out de notificación a supervisores/coordinadores/admins.
   - TRANSPORTE_comunicadosActivos: comunicados vigentes y próximos
     (para el banner de la pantalla de solicitudes).
   - TRANSPORTE_guardarSolicitud: rechaza crear dentro del rango;
     esEmergencia=1 salta el bloqueo.
   Ejecutar con: sqlcmd -f 65001 (UTF-8)
   ============================================================ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('TP_COMUNICADOS') IS NULL
CREATE TABLE TP_COMUNICADOS (
    idComunicado   INT IDENTITY(1,1) PRIMARY KEY,
    titulo         NVARCHAR(120) NOT NULL,
    mensaje        NVARCHAR(500) NOT NULL,
    fecha          DATE NOT NULL,                -- día afectado
    horaInicio     VARCHAR(5) NOT NULL,          -- 'HH:mm' — mismo formato que horaProgramada
    horaFin        VARCHAR(5) NOT NULL,
    unidades       NVARCHAR(200) NULL,           -- placas ocupadas (texto libre: 'TP-001, TP-002')
    motivoActividad NVARCHAR(200) NULL,          -- 'capacitación', 'mantenimiento programado', etc.
    activo         BIT NOT NULL DEFAULT 1,
    usuarioCrea    NVARCHAR(50) NULL,
    fechaCreacion  DATETIME NOT NULL DEFAULT GETDATE(),
    idOperacion    NVARCHAR(64) NULL             -- idempotencia offline (Dexie mutar)
);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_TP_COMUNICADOS_idOp')
    CREATE UNIQUE INDEX UX_TP_COMUNICADOS_idOp ON TP_COMUNICADOS(idOperacion) WHERE idOperacion IS NOT NULL;
GO

/* CRUD de comunicados + difusión.
   {accion:'LISTAR'}
   {accion:'GUARDAR', id?, titulo, mensaje, fecha:'yyyy-MM-dd',
     horaInicio:'HH:mm', horaFin:'HH:mm', unidades?, motivoActividad?,
     activo?, idOperacion?, actor|usuario}
   {accion:'ELIMINAR', id} */
CREATE OR ALTER PROCEDURE TRANSPORTE_administrarComunicado
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @accion NVARCHAR(20) = UPPER(JSON_VALUE(@json, '$.accion'));
    DECLARE @id INT = TRY_CAST(JSON_VALUE(@json, '$.id') AS INT);
    DECLARE @actor NVARCHAR(50) = COALESCE(JSON_VALUE(@json, '$.actor'), JSON_VALUE(@json, '$.usuario'));
    DECLARE @idOperacion NVARCHAR(64) = JSON_VALUE(@json, '$.idOperacion');
    IF @accion <> 'LISTAR'
        INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle) VALUES('COMUNICADO',@id,@accion,@actor,@json);

    IF @accion = 'GUARDAR'
    BEGIN
        -- idempotencia: el retry offline devuelve el comunicado ya creado
        IF @id IS NULL AND @idOperacion IS NOT NULL
           AND EXISTS(SELECT 1 FROM TP_COMUNICADOS WHERE idOperacion = @idOperacion)
        BEGIN
            SELECT * FROM TP_COMUNICADOS WHERE idOperacion = @idOperacion FOR JSON PATH; RETURN;
        END
        DECLARE @titulo NVARCHAR(120) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@json,'$.titulo'))),'');
        DECLARE @mensaje NVARCHAR(500) = NULLIF(LTRIM(RTRIM(JSON_VALUE(@json,'$.mensaje'))),'');
        DECLARE @fecha DATE = TRY_CAST(JSON_VALUE(@json,'$.fecha') AS DATE);
        DECLARE @hi VARCHAR(5) = JSON_VALUE(@json,'$.horaInicio');
        DECLARE @hf VARCHAR(5) = JSON_VALUE(@json,'$.horaFin');
        IF @titulo IS NULL OR @mensaje IS NULL
        BEGIN RAISERROR(N'Titulo y mensaje son obligatorios',16,1); RETURN; END
        IF @fecha IS NULL OR TRY_CAST(@hi AS TIME) IS NULL OR TRY_CAST(@hf AS TIME) IS NULL
        BEGIN RAISERROR(N'Fecha y horas validas son obligatorias (HH:mm)',16,1); RETURN; END
        IF @hi >= @hf
        BEGIN RAISERROR(N'La hora de inicio debe ser menor que la hora de fin',16,1); RETURN; END

        IF @id IS NULL
            INSERT INTO TP_COMUNICADOS(titulo,mensaje,fecha,horaInicio,horaFin,unidades,motivoActividad,usuarioCrea,idOperacion)
            VALUES(@titulo,@mensaje,@fecha,@hi,@hf,
                   JSON_VALUE(@json,'$.unidades'),JSON_VALUE(@json,'$.motivoActividad'),
                   @actor,@idOperacion);
        ELSE UPDATE TP_COMUNICADOS SET titulo=@titulo, mensaje=@mensaje, fecha=@fecha,
             horaInicio=@hi, horaFin=@hf,
             unidades=JSON_VALUE(@json,'$.unidades'), motivoActividad=JSON_VALUE(@json,'$.motivoActividad'),
             activo=COALESCE(TRY_CAST(JSON_VALUE(@json,'$.activo') AS BIT),activo)
             WHERE idComunicado=@id;
        SET @id = COALESCE(@id, SCOPE_IDENTITY());

        -- difusión: supervisores (crean solicitudes), coordinadores y admin
        INSERT INTO TP_NOTIFICACIONES(idUsuario,titulo,mensaje,tipo)
        SELECT u.idUsuario,
               CONCAT('Comunicado: ',@titulo),
               CONCAT('Sin servicio el ',CONVERT(VARCHAR(10),@fecha,103),' de ',@hi,' a ',@hf,'. ',@mensaje),
               'COMUNICADO'
        FROM TP_USUARIOS u
        WHERE u.activo = 1 AND u.eliminado = 0 AND u.idrol IN ('SPTRANS','COTRANS','ADTRANS');
    END
    ELSE IF @accion = 'ELIMINAR'
        UPDATE TP_COMUNICADOS SET activo = 0 WHERE idComunicado = @id;

    SELECT *, CASE WHEN activo = 1 AND fecha = CAST(GETDATE() AS DATE)
                    AND CONVERT(VARCHAR(5),GETDATE(),108) >= horaInicio
                    AND CONVERT(VARCHAR(5),GETDATE(),108) <  horaFin
                   THEN 1 ELSE 0 END AS vigente
    FROM TP_COMUNICADOS ORDER BY fecha DESC, horaInicio FOR JSON PATH;
END
GO

/* Comunicados que el usuario debe ver: vigentes ahora + próximos de hoy
   y de fechas futuras. vigente=1 si la hora actual está dentro del rango. */
CREATE OR ALTER PROCEDURE TRANSPORTE_comunicadosActivos
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SELECT *, CASE WHEN fecha = CAST(GETDATE() AS DATE)
                    AND CONVERT(VARCHAR(5),GETDATE(),108) >= horaInicio
                    AND CONVERT(VARCHAR(5),GETDATE(),108) <  horaFin
                   THEN 1 ELSE 0 END AS vigente
    FROM TP_COMUNICADOS
    WHERE activo = 1 AND fecha >= CAST(GETDATE() AS DATE)
    ORDER BY fecha, horaInicio FOR JSON PATH;
END
GO

/* guardarSolicitud + bloqueo por comunicado:
   si la hora del servidor cae dentro de un rango "sin servicio" del día,
   se rechaza la creación con el texto del comunicado.
   esEmergencia=1 (emergencia médica) salta el bloqueo. */
CREATE OR ALTER PROCEDURE TRANSPORTE_guardarSolicitud
    @json NVARCHAR(MAX)
AS
BEGIN
    DECLARE @idSolicitud INT = TRY_CAST(JSON_VALUE(@json, '$.idSolicitud') AS INT);
    DECLARE @usuario NVARCHAR(50) = JSON_VALUE(@json, '$.usuarioRegistra');
    DECLARE @idArea INT = (SELECT idArea FROM TP_USUARIOS WHERE usuario = @usuario);
    DECLARE @areaNombre NVARCHAR(100) = COALESCE(
        (SELECT nombre FROM TP_AREAS WHERE idArea = @idArea),
        JSON_VALUE(@json, '$.area'));
    DECLARE @esEmergencia BIT = COALESCE(TRY_CAST(JSON_VALUE(@json, '$.esEmergencia') AS BIT), 0);
    DECLARE @prioridad NVARCHAR(15) = UPPER(COALESCE(NULLIF(JSON_VALUE(@json, '$.prioridad'), ''), 'NORMAL'));
    IF @prioridad NOT IN ('NORMAL', 'ALTA', 'EMERGENCIA') SET @prioridad = 'NORMAL';
    IF @esEmergencia = 1 SET @prioridad = 'EMERGENCIA';  -- emergencia medica => maxima prioridad

    -- Comunicado "sin servicio": hora actual dentro del rango → no se crean
    -- solicitudes nuevas (edición no se bloquea; emergencia sí pasa)
    IF (@idSolicitud IS NULL OR @idSolicitud = 0) AND @esEmergencia = 0
    BEGIN
        DECLARE @bloqueo NVARCHAR(500) = (
            SELECT TOP 1 CONCAT('Sin servicio de ', c.horaInicio, ' a ', c.horaFin,
                                ' - ', c.titulo, '. ', c.mensaje)
            FROM TP_COMUNICADOS c
            WHERE c.activo = 1 AND c.fecha = CAST(GETDATE() AS DATE)
              AND CONVERT(VARCHAR(5), GETDATE(), 108) >= c.horaInicio
              AND CONVERT(VARCHAR(5), GETDATE(), 108) <  c.horaFin
            ORDER BY c.horaInicio);
        IF @bloqueo IS NOT NULL
        BEGIN RAISERROR('%s', 16, 1, @bloqueo); RETURN; END
    END

    IF @idSolicitud IS NULL OR @idSolicitud = 0
    BEGIN
        INSERT INTO TP_SOLICITUDES (nombre, area, idArea, fechaProgramada, horaProgramada, puntoPartida, puntoLlegada,
                                    cantidad, motivo, observacion, prioridad, esEmergencia, usuarioRegistra)
        SELECT JSON_VALUE(@json, '$.nombre'), @areaNombre, @idArea,
               CAST(GETDATE() AS DATE),                    -- fecha: siempre la del sistema
               CONVERT(VARCHAR(5), GETDATE(), 108),        -- hora: siempre la del sistema (HH:mm)
               JSON_VALUE(@json, '$.puntoPartida'),
               JSON_VALUE(@json, '$.puntoLlegada'), TRY_CAST(JSON_VALUE(@json, '$.cantidad') AS INT),
               JSON_VALUE(@json, '$.motivo'), JSON_VALUE(@json, '$.observacion'),
               @prioridad, @esEmergencia, @usuario;
        SET @idSolicitud = SCOPE_IDENTITY();
    END
    ELSE
    BEGIN
        UPDATE TP_SOLICITUDES
        SET puntoPartida   = JSON_VALUE(@json, '$.puntoPartida'),
            puntoLlegada   = JSON_VALUE(@json, '$.puntoLlegada'),
            cantidad       = TRY_CAST(JSON_VALUE(@json, '$.cantidad') AS INT),
            motivo         = JSON_VALUE(@json, '$.motivo'),
            observacion    = JSON_VALUE(@json, '$.observacion'),
            prioridad      = CASE WHEN @esEmergencia = 1 THEN 'EMERGENCIA'
                                  ELSE COALESCE(NULLIF(JSON_VALUE(@json, '$.prioridad'), ''), prioridad) END,
            esEmergencia   = @esEmergencia
            -- fechaProgramada/horaProgramada: no se tocan, conservan el valor original
        WHERE idSolicitud = @idSolicitud;
    END

    INSERT INTO TP_AUDITORIA(entidad,idEntidad,accion,usuario,detalle)
    VALUES('SOLICITUD',@idSolicitud,CASE WHEN JSON_VALUE(@json,'$.idSolicitud') IS NULL THEN 'CREAR' ELSE 'EDITAR' END,JSON_VALUE(@json,'$.usuarioRegistra'),@json);
    SELECT * FROM TP_SOLICITUDES WHERE idSolicitud = @idSolicitud FOR JSON PATH;
END
GO
