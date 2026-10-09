SET QUOTED_IDENTIFIER ON;
GO
-- Punto "Topico": destino por defecto de las emergencias medicas.
-- Sin coordenadas por ahora — se asignan desde el catalogo de puntos
-- cuando se conozcan (mapa/GPS las usaran automaticamente).
IF NOT EXISTS (SELECT 1 FROM TP_PUNTOS WHERE nombre = 'Topico')
    INSERT INTO TP_PUNTOS (nombre, activo) VALUES ('Topico', 1);
GO
