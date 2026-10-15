/* 024 — Catálogo de tipos de vehículo
   El select "Tipo de vehículo" del mantenedor de unidades ya no va hardcodeado:
   las opciones viven en TP_TIPOS_VEHICULO y el coordinador las administra
   desde Administración → Tipos vehículo. */
IF OBJECT_ID('TP_TIPOS_VEHICULO') IS NULL
BEGIN
    CREATE TABLE TP_TIPOS_VEHICULO(
        idTipoVehiculo INT IDENTITY(1,1) PRIMARY KEY,
        nombre         NVARCHAR(30) NOT NULL UNIQUE,
        activo         BIT NOT NULL DEFAULT 1
    );
END
GO

-- catálogo inicial: los tipos que antes estaban fijos en el formulario
INSERT INTO TP_TIPOS_VEHICULO(nombre)
SELECT v.nombre FROM (VALUES('Bus'),('Coster'),('Minivan'),('Camioneta'),('Auto'),('Van')) v(nombre)
WHERE NOT EXISTS(SELECT 1 FROM TP_TIPOS_VEHICULO t WHERE t.nombre = v.nombre);
GO
