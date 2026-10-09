-- ============================================================================
-- TRANSPORTE_PERSONAL — Seguimiento de paradas: esquema
-- Idempotente: se puede ejecutar varias veces sin efectos secundarios.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Columnas de seguimiento en TP_TRASLADO_PARADAS
-- ----------------------------------------------------------------------------
IF COL_LENGTH('TP_TRASLADO_PARADAS', 'estado') IS NULL
    ALTER TABLE TP_TRASLADO_PARADAS ADD estado VARCHAR(12) NOT NULL
        CONSTRAINT DF_TP_TRASLADO_PARADAS_estado DEFAULT 'PENDIENTE';

IF COL_LENGTH('TP_TRASLADO_PARADAS', 'horaLlegada') IS NULL
    ALTER TABLE TP_TRASLADO_PARADAS ADD horaLlegada DATETIME2 NULL;

IF COL_LENGTH('TP_TRASLADO_PARADAS', 'horaSalida') IS NULL
    ALTER TABLE TP_TRASLADO_PARADAS ADD horaSalida DATETIME2 NULL;

IF COL_LENGTH('TP_TRASLADO_PARADAS', 'subieronReal') IS NULL
    ALTER TABLE TP_TRASLADO_PARADAS ADD subieronReal INT NULL;

IF COL_LENGTH('TP_TRASLADO_PARADAS', 'bajaronReal') IS NULL
    ALTER TABLE TP_TRASLADO_PARADAS ADD bajaronReal INT NULL;

IF COL_LENGTH('TP_TRASLADO_PARADAS', 'latitud') IS NULL
    ALTER TABLE TP_TRASLADO_PARADAS ADD latitud DECIMAL(9,6) NULL;

IF COL_LENGTH('TP_TRASLADO_PARADAS', 'longitud') IS NULL
    ALTER TABLE TP_TRASLADO_PARADAS ADD longitud DECIMAL(9,6) NULL;

IF COL_LENGTH('TP_TRASLADO_PARADAS', 'motivoOmision') IS NULL
    ALTER TABLE TP_TRASLADO_PARADAS ADD motivoOmision NVARCHAR(200) NULL;

IF COL_LENGTH('TP_TRASLADO_PARADAS', 'usuarioRegistra') IS NULL
    ALTER TABLE TP_TRASLADO_PARADAS ADD usuarioRegistra NVARCHAR(100) NULL;

IF COL_LENGTH('TP_TRASLADO_PARADAS', 'fechaRegistro') IS NULL
    ALTER TABLE TP_TRASLADO_PARADAS ADD fechaRegistro DATETIME2 NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_TP_TRASLADO_PARADAS_estado')
    ALTER TABLE TP_TRASLADO_PARADAS ADD CONSTRAINT CK_TP_TRASLADO_PARADAS_estado
        CHECK (estado IN ('PENDIENTE','EN_PARADA','REALIZADA','OMITIDA'));

-- ----------------------------------------------------------------------------
-- 2) TP_PARADA_DETALLE — vinculo parada <-> solicitud
--    Quien sube (S) o baja (B) en cada parada y cuantos.
-- ----------------------------------------------------------------------------
IF OBJECT_ID('TP_PARADA_DETALLE', 'U') IS NULL
BEGIN
    CREATE TABLE TP_PARADA_DETALLE (
        idParadaDetalle   INT IDENTITY(1,1) PRIMARY KEY,
        idParada          INT NOT NULL REFERENCES TP_TRASLADO_PARADAS(idParada),
        idSolicitud       INT NOT NULL REFERENCES TP_SOLICITUDES(idSolicitud),
        idSolicitudUnidad INT NULL,
        tipo              CHAR(1) NOT NULL CHECK (tipo IN ('S','B')),
        cantidadPlaneada  INT NOT NULL,
        cantidadReal      INT NULL,
        CONSTRAINT UQ_TP_PARADA_DETALLE UNIQUE (idParada, idSolicitud, tipo)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_TP_PARADA_DETALLE_parada')
    CREATE INDEX IX_TP_PARADA_DETALLE_parada ON TP_PARADA_DETALLE(idParada);
GO
