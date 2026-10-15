/* ============================================================
   020 — Distribución del costo por tareo filtrado por supervisor
   - TRANSPORTE_horasCecoSupervisor: misma consulta que
     BDERP_Agro_Hass.dbo.TareoHorasCeco pero filtrada por los DNIs
     de los supervisores que registraron las solicitudes, e
     incluye "supervisor" en cada fila.
   - TRANSPORTE_generarOS: modo TAREO ahora usa el tareo de los
     supervisores vinculados a las solicitudes de cada OS.
     Fallback a modo AREA si el supervisor no tiene tareo/DNI.
   Ejecutar con: sqlcmd -f 65001 (UTF-8)
   ============================================================ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

/* input:  [{"ruc":"20481121966","fechaInicio":"yyyymmdd","fechaFin":"yyyymmdd",
             "supervisores":["dni1","dni2"]}]
   output: id = JSON [{supervisor,idcultivo,idproyecto,ceco,cuenta,TotalHoras,idlabor,codfundo}] */
CREATE OR ALTER PROCEDURE TRANSPORTE_horasCecoSupervisor
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ruc NVARCHAR(20) = JSON_VALUE(@json,'$[0].ruc');
    DECLARE @fini NVARCHAR(20) = JSON_VALUE(@json,'$[0].fechaInicio');
    DECLARE @ffin NVARCHAR(20) = JSON_VALUE(@json,'$[0].fechaFin');

    DECLARE @sups TABLE(dni NVARCHAR(20));
    INSERT INTO @sups SELECT v.value FROM OPENJSON(JSON_QUERY(@json,'$[0].supervisores')) v;

    SELECT ISNULL((
        SELECT a.nrodocumentosupervisor AS supervisor,
               c.idcultivo, c.idproyecto, m.ceco_distribucion AS ceco,
               '9' + CAST(ac.div AS VARCHAR(1)) + '311207' AS cuenta,
               SUM(c.horas) AS TotalHoras, '4502' AS idlabor, a.codfundo
        FROM BDERP_Agro_Hass.dbo.tareo_asistencia a
        INNER JOIN BDERP_Agro_Hass.dbo.tareo_dasistencia d
            ON a.idtareo_asistencia = d.idtareo_asistencia
        INNER JOIN BDERP_Agro_Hass.dbo.tareo_dasistenciacecolabor c
            ON a.idtareo_asistencia = c.idtareo_asistencia
           AND d.nrodocumento = c.nrodocumento
        INNER JOIN BDERP_Agro_Hass.dbo.MAESTRO_CecoDistriTR m
            ON c.ceco = m.ceco
        INNER JOIN [HASS-DB1].HP_SPRING_PRD.dbo.AC_CostCenterMST ac
            ON m.ceco_distribucion = ac.CostCenter
        WHERE a.ruc = @ruc
          AND a.fecha_tareo >= @fini AND a.fecha_tareo <= @ffin
          AND (NOT EXISTS (SELECT 1 FROM @sups)
               OR a.nrodocumentosupervisor IN (SELECT dni FROM @sups))
          AND NULLIF(LTRIM(RTRIM(c.idcultivo)), '') IS NOT NULL
          AND NULLIF(LTRIM(RTRIM(a.codfundo)), '') IS NOT NULL
          AND NULLIF(LTRIM(RTRIM(c.idproyecto)), '') IS NOT NULL
          AND NULLIF(LTRIM(RTRIM(m.ceco_distribucion)), '') IS NOT NULL
        GROUP BY a.nrodocumentosupervisor, c.idcultivo, c.idproyecto,
                 m.ceco_distribucion, ac.div, a.codfundo
        FOR JSON PATH), '[]') AS id;
END
GO

/* TRANSPORTE_generarOS — corazón del flujo de la Orden de Servicio.
   Genera (o simula con previa:1) las OS del período: una por transportista.

   Etapas internas:
     1. #OVR   cecos elegidos a mano en la previa (solo modo AREA)
     2. #PAX   pasajeros reales por solicitud (subidas en paradas o planificado)
     3. #TR    traslados elegibles: REALIZADO, en el rango, no facturados aún
     4. tarifa match por ruta (exacta > parcial > default del transportista)
     5. #G     grupos por transportista = las OS a crear (viajes/pax/tarifa)
     6. #SUP   supervisores que hicieron esas solicitudes (DNI + peso en pax)
     7. #FIRM  firmante de cada OS = supervisor con más pasajeros del grupo
     8. #TAREO horas del ERP (TRANSPORTE_horasCecoSupervisor) para esos DNIs
     9. #OSDET distribución del costo por OS:
         - TAREO: costo_fila = totalTarifa * TotalHoras_fila / Σ horas del grupo
         - AREA (fallback): costo_fila = totalTarifa * pax_area / pax_grupo
    10. Validaciones duras: ceco+cuenta+proyecto en toda fila, toda OS con
        detalle y toda OS con firmante (DNI supervisor o del que genera)
    11. Inserta OS + detalle + traslados + payloadEnvio listo para logística

   Distribución del costo:
     - TAREO (default): horas del tareo de los supervisores que registraron
       las solicitudes de esa OS; costo ∝ TotalHoras por ceco.
     - AREA  (fallback por grupo): costo ∝ pasajeros por área, ceco elegido
       en detalle: [{"idTransportista":N,"idArea":N,"idCeco":N}] */
CREATE OR ALTER PROCEDURE TRANSPORTE_generarOS
    @json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @desde DATE = TRY_CAST(JSON_VALUE(@json,'$.desde') AS DATE);
    DECLARE @hasta DATE = TRY_CAST(JSON_VALUE(@json,'$.hasta') AS DATE);
    DECLARE @usuario NVARCHAR(50) = JSON_VALUE(@json,'$.usuario');
    DECLARE @dni NVARCHAR(15) = JSON_VALUE(@json,'$.usuarioGenera');
    DECLARE @idOperacion NVARCHAR(64) = JSON_VALUE(@json,'$.idOperacion');
    DECLARE @previa BIT = COALESCE(TRY_CAST(JSON_VALUE(@json,'$.previa') AS BIT), 0);
    DECLARE @usarTareo BIT = COALESCE(TRY_CAST(JSON_VALUE(@json,'$.usarTareo') AS BIT), 1);
    -- Si no llega el DNI, se resuelve desde la cuenta del usuario que genera
    IF @dni IS NULL SET @dni = (SELECT dni FROM TP_USUARIOS WHERE usuario = @usuario);

    IF @desde IS NULL OR @hasta IS NULL
    BEGIN RAISERROR(N'Las fechas desde y hasta son obligatorias',16,1); RETURN; END

    -- Idempotencia: misma operación devuelve las OS ya creadas (no aplica a previa)
    IF @previa = 0 AND @idOperacion IS NOT NULL AND EXISTS(SELECT 1 FROM TP_ORDENES_SERVICIO WHERE idOperacion = @idOperacion)
    BEGIN
        SELECT (SELECT o.*, (SELECT d.* FROM TP_OS_DETALLE d WHERE d.idOS = o.idOS FOR JSON PATH) AS detalle
                FROM TP_ORDENES_SERVICIO o WHERE o.idOperacion = @idOperacion
                ORDER BY o.idOS FOR JSON PATH) AS ordenes,
               JSON_QUERY('[]') AS excluidos
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    DECLARE @rucEmpresa NVARCHAR(11) = (SELECT valor FROM TP_PARAMETROS WHERE clave='RUC_EMPRESA');
    DECLARE @idEmpresa NVARCHAR(20)  = (SELECT valor FROM TP_PARAMETROS WHERE clave='ID_EMPRESA');

    -- (1) Overrides de ceco elegidos por el coordinador en la previa (modo AREA)
    SELECT idTransportista, idArea, idCeco INTO #OVR
    FROM OPENJSON(ISNULL(JSON_QUERY(@json,'$.detalle'),'[]'))
    WITH (idTransportista INT '$.idTransportista', idArea INT '$.idArea', idCeco INT '$.idCeco');

    -- (2) Pasajeros reales por solicitud (subidas registradas en paradas; si no hay, lo planificado)
    SELECT s.idSolicitud, s.idTraslado, s.idArea, s.area,
           ISNULL((SELECT SUM(d.cantidadReal) FROM TP_PARADA_DETALLE d
                   JOIN TP_TRASLADO_PARADAS p ON p.idParada = d.idParada
                   WHERE p.idTraslado = s.idTraslado AND d.idSolicitud = s.idSolicitud AND d.tipo = 'B'),
                  s.cantidad) AS pasajeros
    INTO #PAX
    FROM TP_SOLICITUDES s
    WHERE s.estado = 'REALIZADO';

    -- (3) Traslados elegibles: realizados en el período y aún no incluidos en una OS
    SELECT t.idTraslado, t.placa, u.idTransportista, tr.ruc, tr.razonSocial,
           LTRIM(RTRIM(LEFT(t.ruta, CASE WHEN CHARINDEX('>',t.ruta) > 0 THEN CHARINDEX('>',t.ruta)-1 ELSE LEN(t.ruta) END))) AS origen,
           LTRIM(RTRIM(REVERSE(LEFT(REVERSE(t.ruta), CASE WHEN CHARINDEX('>',REVERSE(t.ruta)) > 0 THEN CHARINDEX('>',REVERSE(t.ruta))-1 ELSE LEN(t.ruta) END)))) AS destino,
           ISNULL(px.pasajeros,0) AS pasajeros,
           CAST(NULL AS DECIMAL(12,2)) AS tarifa,
           CAST(NULL AS DECIMAL(18,6)) AS costo
    INTO #TR
    FROM TP_TRASLADOS t
    JOIN TP_UNIDADES u ON u.placa = t.placa
    LEFT JOIN TP_TRANSPORTISTAS tr ON tr.idTransportista = u.idTransportista
    OUTER APPLY (SELECT SUM(x.pasajeros) AS pasajeros FROM #PAX x WHERE x.idTraslado = t.idTraslado) px
    WHERE t.estado = 'REALIZADO'
      AND NOT EXISTS (SELECT 1 FROM TP_OS_TRASLADOS ot WHERE ot.idTraslado = t.idTraslado)
      AND (SELECT MAX(COALESCE(s.fechaFin, s.fechaProgramada)) FROM TP_SOLICITUDES s
           WHERE s.idTraslado = t.idTraslado AND s.estado = 'REALIZADO') BETWEEN @desde AND DATEADD(day,1,@hasta);

    -- (4) Tarifa por traslado: match exacto ruta, luego parcial, luego default (origen/destino NULL)
    UPDATE x SET tarifa = tf.monto,
        costo = CASE WHEN tf.porPasajero = 1 THEN tf.monto * x.pasajeros ELSE tf.monto END
    FROM #TR x
    OUTER APPLY (
        SELECT TOP 1 monto, porPasajero FROM TP_TARIFAS tf
        WHERE tf.idTransportista = x.idTransportista AND tf.activo = 1
          AND (tf.puntoOrigen  IS NULL OR tf.puntoOrigen  = x.origen)
          AND (tf.puntoDestino IS NULL OR tf.puntoDestino = x.destino)
        ORDER BY (CASE WHEN tf.puntoOrigen  IS NOT NULL THEN 1 ELSE 0 END
                + CASE WHEN tf.puntoDestino IS NOT NULL THEN 1 ELSE 0 END) DESC
    ) tf;

    -- Resumen de lo no facturable para devolverlo como advertencia
    SELECT placa, origen, destino,
           CASE WHEN idTransportista IS NULL THEN 'SIN_TRANSPORTISTA' ELSE 'SIN_TARIFA' END AS motivo
    INTO #EXCLUIDOS FROM #TR WHERE idTransportista IS NULL OR tarifa IS NULL;

    -- (5) Grupos por transportista: cada grupo terminará siendo una OS
    SELECT idTransportista, MIN(ruc) AS ruc, MIN(razonSocial) AS razonSocial,
           COUNT(*) AS viajes, ISNULL(SUM(pasajeros),0) AS pax, ISNULL(SUM(costo),0) AS totalTarifa
    INTO #G FROM #TR WHERE idTransportista IS NOT NULL AND tarifa IS NOT NULL
    GROUP BY idTransportista;

    -- (6) Supervisores que registraron las solicitudes de cada grupo (usuario + DNI + peso en pax)
    SELECT t.idTransportista, s.usuarioRegistra, u.dni, SUM(px.pasajeros) AS paxSup
    INTO #SUP
    FROM #TR t
    JOIN TP_SOLICITUDES s ON s.idTraslado = t.idTraslado AND s.estado = 'REALIZADO'
    JOIN TP_USUARIOS u ON u.usuario = s.usuarioRegistra
    JOIN #PAX px ON px.idSolicitud = s.idSolicitud
    WHERE NULLIF(LTRIM(RTRIM(u.dni)),'') IS NOT NULL
    GROUP BY t.idTransportista, s.usuarioRegistra, u.dni;

    -- (7) Firmante de cada OS: el supervisor con más pasajeros del grupo
    SELECT idTransportista, dni INTO #FIRM
    FROM (SELECT s.idTransportista, s.dni,
                 ROW_NUMBER() OVER (PARTITION BY s.idTransportista ORDER BY s.paxSup DESC) AS rn
          FROM #SUP s) x
    WHERE rn = 1;

    -- (8) Tareo del ERP filtrado por esos supervisores (una sola llamada, fila incluye supervisor)
    CREATE TABLE #TJSON(id NVARCHAR(MAX));
    CREATE TABLE #TAREO(
        supervisor NVARCHAR(20) NULL, idcultivo NVARCHAR(10) NULL,
        idproyecto NVARCHAR(20) NULL, ceco NVARCHAR(20) NULL, cuenta NVARCHAR(30) NULL,
        TotalHoras DECIMAL(18,6) NULL, idlabor NVARCHAR(10) NULL, codfundo NVARCHAR(20) NULL);
    IF @usarTareo = 1 AND @rucEmpresa IS NOT NULL AND EXISTS (SELECT 1 FROM #SUP)
    BEGIN
        DECLARE @supJson NVARCHAR(MAX) = N'[' + ISNULL(STUFF((
            SELECT ',"' + dni + '"' FROM (SELECT DISTINCT dni FROM #SUP) s FOR XML PATH(''),TYPE
            ).value('.','NVARCHAR(MAX)'), 1, 1, ''),'') + N']';
        DECLARE @jTareo NVARCHAR(MAX) = N'[{"ruc":"' + @rucEmpresa + N'","fechaInicio":"'
            + CONVERT(NVARCHAR(8),@desde,112) + N'","fechaFin":"' + CONVERT(NVARCHAR(8),@hasta,112)
            + N'","supervisores":' + @supJson + N'}]';
        BEGIN TRY
            INSERT INTO #TJSON EXEC TRANSPORTE_horasCecoSupervisor @jTareo;
            INSERT INTO #TAREO
            SELECT JSON_VALUE(v.value,'$.supervisor'), JSON_VALUE(v.value,'$.idcultivo'),
                   JSON_VALUE(v.value,'$.idproyecto'), JSON_VALUE(v.value,'$.ceco'),
                   JSON_VALUE(v.value,'$.cuenta'),
                   TRY_CAST(JSON_VALUE(v.value,'$.TotalHoras') AS DECIMAL(18,6)),
                   JSON_VALUE(v.value,'$.idlabor'), JSON_VALUE(v.value,'$.codfundo')
            FROM #TJSON CROSS APPLY OPENJSON(id) v;
            -- Cultivo genérico por proyecto (FUNDO HP/BH/CAO)
            UPDATE t SET idcultivo = pc.idcultivo
            FROM #TAREO t JOIN TP_PROYECTO_CULTIVO pc ON pc.idproyecto = t.idproyecto;
        END TRY
        BEGIN CATCH
            DELETE FROM #TJSON; -- sin tareo: se distribuirá por área
        END CATCH
    END

    CREATE TABLE #OSDET(
        idTransportista INT, idArea INT NULL, area NVARCHAR(100) NULL,
        idCeco INT NULL, ceco NVARCHAR(20) NULL, cuenta NVARCHAR(30) NULL,
        idproyecto NVARCHAR(20) NULL, codfundo NVARCHAR(20) NULL,
        idcultivo NVARCHAR(10) NULL, idlabor NVARCHAR(10) NULL,
        cantidad DECIMAL(18,6), costo DECIMAL(18,6), origen NVARCHAR(10));

    -- (9a) MODO TAREO por grupo: solo grupos cuyos supervisores tienen tareo en el período
    INSERT INTO #OSDET(idTransportista, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, cantidad, costo, origen)
    SELECT g.idTransportista, t.ceco, t.cuenta, t.idproyecto, t.codfundo, t.idcultivo, t.idlabor,
           t.TotalHoras, ROUND(g.totalTarifa * t.TotalHoras / s.sumHoras, 6), 'TAREO'
    FROM #G g
    JOIN #TAREO t ON t.supervisor IN (SELECT dni FROM #SUP s WHERE s.idTransportista = g.idTransportista)
    CROSS APPLY (SELECT SUM(t2.TotalHoras) AS sumHoras FROM #TAREO t2
                 WHERE t2.supervisor IN (SELECT dni FROM #SUP s WHERE s.idTransportista = g.idTransportista)) s
    WHERE s.sumHoras > 0;

    -- (9b) MODO AREA: grupos sin tareo de sus supervisores (o sin DNI) → costo ∝ pasajeros
    INSERT INTO #OSDET(idTransportista, idArea, area, idCeco, ceco, cuenta, idproyecto,
                       codfundo, idcultivo, idlabor, cantidad, costo, origen)
    SELECT t.idTransportista, px.idArea, px.area,
           COALESCE(cc.idCeco, def.idCeco),
           COALESCE(cc.ceco, a.ceco), COALESCE(cc.cuenta, a.cuenta),
           COALESCE(cc.idproyecto, a.idproyecto), COALESCE(cc.codfundo, a.codfundo),
           COALESCE(cc.idcultivo, a.idcultivo), COALESCE(cc.idlabor, a.idlabor),
           SUM(px.pasajeros),
           ROUND(g.totalTarifa * SUM(px.pasajeros) / NULLIF(g.pax,0), 6), 'AREA'
    FROM #PAX px
    JOIN #TR t ON t.idTraslado = px.idTraslado AND t.tarifa IS NOT NULL
    JOIN #G g ON g.idTransportista = t.idTransportista
    LEFT JOIN TP_AREAS a ON a.idArea = px.idArea
    LEFT JOIN #OVR o ON o.idTransportista = t.idTransportista AND (o.idArea = px.idArea OR (o.idArea IS NULL AND px.idArea IS NULL))
    LEFT JOIN TP_CECOS cc ON cc.idCeco = o.idCeco
    LEFT JOIN TP_CECOS def ON def.ceco = a.ceco AND def.activo = 1
    WHERE g.pax > 0
      AND NOT EXISTS (SELECT 1 FROM #OSDET d WHERE d.idTransportista = g.idTransportista AND d.origen = 'TAREO')
    GROUP BY t.idTransportista, px.idArea, px.area, cc.idCeco, def.idCeco, cc.ceco, a.ceco,
             cc.cuenta, a.cuenta, cc.idproyecto, a.idproyecto, cc.codfundo, a.codfundo,
             cc.idcultivo, a.idcultivo, cc.idlabor, a.idlabor, g.totalTarifa, g.pax;

    -- Previa: devuelve lo que se generaría sin grabar nada (paso 1 del flujo UI)
    IF @previa = 1
    BEGIN
        SELECT (SELECT g.idTransportista, g.razonSocial AS nombreTransportista, g.ruc AS rucTransportista,
                       g.viajes AS totalViajes, g.pax AS totalPasajeros, g.totalTarifa,
                       ROUND(g.totalTarifa*0.18,2) AS igvTotalTarifa,
                       CASE WHEN EXISTS (SELECT 1 FROM #OSDET d WHERE d.idTransportista = g.idTransportista AND d.origen='TAREO')
                            THEN 'TAREO' ELSE 'AREA' END AS modoCeco,
                       COALESCE((SELECT dni FROM #FIRM WHERE idTransportista = g.idTransportista), @dni) AS dniFirmante,
                       (SELECT d.* FROM #OSDET d WHERE d.idTransportista = g.idTransportista FOR JSON PATH) AS detalle
                FROM #G g ORDER BY g.idTransportista FOR JSON PATH) AS ordenes,
               (SELECT * FROM #EXCLUIDOS FOR JSON PATH) AS excluidos
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
        RETURN;
    END

    -- (10) Validaciones duras antes de grabar — regla: toda OS nace completa.
    -- Toda fila del detalle debe tener ceco, cuenta y proyecto antes de generar
    IF EXISTS (SELECT 1 FROM #OSDET WHERE ceco IS NULL OR cuenta IS NULL OR idproyecto IS NULL)
    BEGIN
        DECLARE @faltantes NVARCHAR(MAX) = STUFF((SELECT DISTINCT ', ' + ISNULL(area, ceco) FROM #OSDET
            WHERE ceco IS NULL OR cuenta IS NULL OR idproyecto IS NULL
            FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)'), 1, 2, '');
        RAISERROR(N'Falta centro de costo, cuenta o proyecto para: %s. Elija el ceco en la previa.', 16, 1, @faltantes);
        RETURN;
    END
    -- y toda OS debe llevar detalle (sin distribución = sin ceco)
    IF EXISTS (SELECT 1 FROM #G g WHERE NOT EXISTS (SELECT 1 FROM #OSDET d WHERE d.idTransportista = g.idTransportista))
    BEGIN
        DECLARE @sinDet NVARCHAR(MAX) = STUFF((SELECT ', ' + razonSocial FROM #G g
            WHERE NOT EXISTS (SELECT 1 FROM #OSDET d WHERE d.idTransportista = g.idTransportista)
            FOR XML PATH(''), TYPE).value('.','NVARCHAR(MAX)'), 1, 2, '');
        RAISERROR(N'No se pudo distribuir el costo por área para: %s', 16, 1, @sinDet);
        RETURN;
    END
    -- y toda OS debe tener firmante: DNI del supervisor (o del que genera como fallback)
    IF NULLIF(LTRIM(RTRIM(@dni)),'') IS NULL
       AND EXISTS (SELECT 1 FROM #G g WHERE NOT EXISTS (SELECT 1 FROM #FIRM f WHERE f.idTransportista = g.idTransportista))
    BEGIN RAISERROR(N'Ni los supervisores de las solicitudes ni el usuario que genera tienen DNI registrado.', 16, 1); RETURN; END

    -- (11) Persistencia: una OS por transportista + su detalle + traslados + payload
    BEGIN TRAN;
    DECLARE @idT INT, @idOS INT, @viajes INT, @pax INT, @tarifa DECIMAL(14,2), @rucT NVARCHAR(11), @razT NVARCHAR(150), @dniOS NVARCHAR(15);
    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT idTransportista, ruc, razonSocial, viajes, pax, totalTarifa FROM #G;
    OPEN cur;
    FETCH NEXT FROM cur INTO @idT, @rucT, @razT, @viajes, @pax, @tarifa;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- El que firma ante logística es el supervisor que hizo la solicitud;
        -- si ningún supervisor del grupo tiene DNI, firma el que genera
        SET @dniOS = COALESCE((SELECT dni FROM #FIRM WHERE idTransportista = @idT), @dni);

        INSERT INTO TP_ORDENES_SERVICIO(fechaDesde, fechaHasta, fechaProceso, idTransportista,
            rucTransportista, nombreTransportista, totalViajes, totalPasajeros, totalTarifa, igvTotalTarifa,
            usuarioGenera, usuario, idOperacion)
        VALUES(@desde, @hasta, @hasta, @idT, @rucT, @razT, @viajes, @pax, @tarifa,
            ROUND(@tarifa * 0.18, 2), @dniOS, @usuario, @idOperacion);
        SET @idOS = SCOPE_IDENTITY();

        -- Detalle: filas del tareo de los supervisores (o por área en fallback)
        INSERT INTO TP_OS_DETALLE(idOS, idArea, area, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, cantidad, costo, origen)
        SELECT @idOS, idArea, area, ceco, cuenta, idproyecto, codfundo, idcultivo, idlabor, cantidad, costo, origen
        FROM #OSDET WHERE idTransportista = @idT;

        INSERT INTO TP_OS_TRASLADOS(idOS, idTraslado)
            SELECT @idOS, idTraslado FROM #TR WHERE idTransportista = @idT AND tarifa IS NOT NULL;

        -- Payload listo para logistica (contrato orden-servicio/ingresar-transporte)
        UPDATE o SET payloadEnvio = (
            SELECT @idEmpresa AS idempresa, @rucEmpresa AS ruc_empresa, @rucT AS ruc_transportista,
                   @viajes AS total_viajes, @tarifa AS total_tarifa, ROUND(@tarifa*0.18,2) AS igv_total_tarifa,
                   CONVERT(NVARCHAR(10),@hasta,120) AS fechaProceso, @dniOS AS usuario,
                   CONVERT(NVARCHAR(10),@desde,120) AS fechaInicioServicio,
                   CONVERT(NVARCHAR(10),@hasta,120) AS fechaFinServicio,
                   (SELECT @rucT AS ruc_transportista, d.idcultivo, d.idproyecto, d.ceco,
                           d.cantidad AS TotalHoras, d.idlabor, d.cuenta, d.codfundo, d.costo
                    FROM TP_OS_DETALLE d WHERE d.idOS = @idOS FOR JSON PATH) AS detalle
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
        FROM TP_ORDENES_SERVICIO o WHERE o.idOS = @idOS;

        FETCH NEXT FROM cur INTO @idT, @rucT, @razT, @viajes, @pax, @tarifa;
    END
    CLOSE cur; DEALLOCATE cur;
    COMMIT;

    SELECT (SELECT o.*, (SELECT d.* FROM TP_OS_DETALLE d WHERE d.idOS = o.idOS FOR JSON PATH) AS detalle
            FROM TP_ORDENES_SERVICIO o
            WHERE o.idOperacion = @idOperacion OR (o.idOperacion IS NULL AND o.fechaGeneracion >= DATEADD(minute,-1,GETDATE()) AND o.fechaDesde=@desde AND o.fechaHasta=@hasta)
            ORDER BY o.idOS FOR JSON PATH) AS ordenes,
           (SELECT * FROM #EXCLUIDOS FOR JSON PATH) AS excluidos
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER;
END
GO
