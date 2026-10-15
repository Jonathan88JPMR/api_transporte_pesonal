SET QUOTED_IDENTIFIER ON;
GO
-- IMPORTANTE: ejecutar con "sqlcmd -f 65001" para que las tildes se lean bien
-- (el archivo es UTF-8; sin el flag sqlcmd lo interpreta en la página local).
-- ============================================================================
-- 015_catalogos_excel.sql — registra las áreas y motivos que usa el Excel
-- "DASHBOARD ACTIVIDADES DE TRANSPORTE" para que los catálogos del sistema
-- reflejen la operación real. Idempotente (WHERE NOT EXISTS).
-- ============================================================================

INSERT INTO TP_AREAS(nombre)
SELECT v.n FROM (VALUES
    (N'BPA'), (N'Mant. Riego'), (N'Riego'), (N'Inv. Desarrollo'),
    (N'Post. Cosecha'), (N'Palto'), (N'Labores'), (N'BPM'),
    (N'Des. Organizacional'), (N'Cosecha Arandano'), (N'Aseg. Calidad'),
    (N'Tópico'), (N'RR.HH'), (N'Materiales de cosecha'), (N'M. Ambiente'),
    (N'Almacen Empaque'), (N'Electrificación'), (N'Operador maquina'),
    (N'Taller Macánica'), (N'Instalación'), (N'Construcción'),
    (N'Control Interno'), (N'Sanidad'), (N'SST'), (N'Lav. Jarras'),
    (N'Apicultura'), (N'Control de Aves'), (N'Vigilancia')
) v(n)
WHERE NOT EXISTS (SELECT 1 FROM TP_AREAS WHERE nombre = v.n);
GO

INSERT INTO TP_MOTIVOS(nombre)
SELECT v.n FROM (VALUES
    (N'Permiso'), (N'Reunión'), (N'P. nuevo')
) v(n)
WHERE NOT EXISTS (SELECT 1 FROM TP_MOTIVOS WHERE nombre = v.n);
GO

SELECT 'AREAS' lista, idArea id, nombre, activo FROM TP_AREAS ORDER BY nombre;
SELECT 'MOTIVOS' lista, idMotivo id, nombre, activo FROM TP_MOTIVOS ORDER BY idMotivo;
GO
