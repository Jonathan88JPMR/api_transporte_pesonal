export interface Usuario {
  idUsuario: number;
  usuario: string;
  nombre: string;
  idrol: string;
  rol: string;
  placa?: string | null;
  area?: string | null;
  idArea?: number | null;
  token?: string;
}

export interface Solicitud {
  idSolicitud: number;
  idTraslado?: number | null;
  idSolicitudUnidad?: number | null;
  nombre: string;
  area?: string | null;
  idArea?: number | null;
  fechaProgramada: string;
  horaProgramada: string;
  puntoPartida: string;
  puntoLlegada: string;
  cantidad: number;
  motivo?: string | null;
  observacion?: string | null;
  prioridad?: string;
  esEmergencia: boolean;
  placa?: string | null;
  realizado: boolean;
  estado: string;
  usuarioRegistra?: string | null;
  fechaRegistro?: string;
  fechaInicio?: string | null;
  fechaFin?: string | null;
  ruta?: string | null;
  paradas?: Parada[] | null;
  // Porciones cuando la solicitud se reparte en varias unidades (MULTIPLE)
  porciones?: PorcionSolicitud[] | null;
}

// Una fracción de una solicitud asignada a una unidad concreta.
// Cada porción tiene su propio traslado (con sus paradas).
export interface PorcionSolicitud {
  idSolicitudUnidad: number;
  placa: string;
  cantidadAsignada: number;
  estado: string;
  idTraslado?: number | null;
}

export interface Traslado {
  idTraslado: number;
  placa: string;
  ruta?: string | null;
  estado: string;
  fechaCreacion?: string;
  solicitudes?: Solicitud[];
  paradas?: Parada[];
  // Última posición GPS reportada por la unidad en ruta
  ultimaLatitud?: number | null;
  ultimaLongitud?: number | null;
  ultimaUbicacionAt?: string | null;
}

export type EstadoParada = 'PENDIENTE' | 'EN_PARADA' | 'REALIZADA' | 'OMITIDA';

// Qué grupo de pasajeros (solicitud) sube o baja en la parada.
// Permite autogenerar la ruta al unir solicitudes y validar conteos.
export interface ParadaDetalle {
  idParadaDetalle?: number;
  idParada?: number;
  idSolicitud: number;
  idSolicitudUnidad?: number | null;
  tipo: 'S' | 'B';               // S = sube, B = baja
  cantidadPlaneada: number;
  cantidadReal?: number | null;
  nombre?: string;               // solicitante, solo para mostrar
}

export interface Parada {
  idParada?: number;
  idPunto?: number | null;
  punto: string;
  orden?: number;
  // Planeado (coordinador)
  cantidadSube: number;
  cantidadBaja: number;
  // Real (conductor)
  subieronReal?: number | null;
  bajaronReal?: number | null;
  estado?: EstadoParada;
  horaLlegada?: string | null;
  horaSalida?: string | null;
  motivoOmision?: string | null;
  detalle?: ParadaDetalle[];
}

// Resumen de avance de un traslado para el polling del coordinador.
export interface ProgresoTraslado {
  idTraslado: number;
  placa: string;
  estadoTraslado: string;
  paradaActual?: number | null;  // orden de la parada en curso (1-based)
  totalParadas: number;
  realizadas: number;
  aBordo: number;
  paradas: Parada[];
  ultimaLatitud?: number | null;
  ultimaLongitud?: number | null;
  ultimaUbicacionAt?: string | null;
}

export interface PosicionGeo {
  latitud: number;
  longitud: number;
  precision?: number;
}

export interface AsignacionUnidad {
  placa: string;
  cantidad: number;
}

export interface IndicadoresReporte {
  totalSolicitudes: number;
  totalPersonas: number;
  totalRealizados: number;
  totalEmergencias: number;
  tiempoPromedioMinutos?: number;
  esperaPromedioMinutos?: number;
  puntualidadPorcentaje?: number;
  unidades: { placa: string; viajes: number; personas: number; ocupacionPorcentaje: number }[];
  areas: { area: string; solicitudes: number; personas: number }[];
  conductores?: { conductor: string; placa: string; servicios: number; personas: number }[];
}

export interface Auditoria {
  idAuditoria: number;
  entidad: string;
  idEntidad?: number;
  accion: string;
  usuario?: string;
  detalle?: string;
  fecha: string;
}

export interface Punto {
  idPunto: number;
  nombre: string;
  latitud?: number | null;
  longitud?: number | null;
}

export interface Unidad {
  idUnidad: number;
  placa: string;
  capacidad: number;
  disponible?: boolean;
  cupoDisponible?: number;
}

export interface Motivo {
  idMotivo: number;
  nombre: string;
}

export interface Area {
  idArea: number;
  nombre: string;
  activo?: boolean;
}
