export interface Usuario {
  idUsuario: number;
  usuario: string;
  nombre: string;
  idrol: string;
  rol: string;
  placa?: string | null;
  area?: string | null;
  token?: string;
}

export interface Solicitud {
  idSolicitud: number;
  idTraslado?: number | null;
  idSolicitudUnidad?: number | null;
  nombre: string;
  area?: string | null;
  fechaProgramada: string;
  horaProgramada: string;
  puntoPartida: string;
  puntoLlegada: string;
  cantidad: number;
  motivo?: string | null;
  observacion?: string | null;
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
}

export interface Traslado {
  idTraslado: number;
  placa: string;
  ruta?: string | null;
  estado: string;
  fechaCreacion?: string;
  solicitudes?: Solicitud[];
  paradas?: Parada[];
}

export interface Parada {
  idParada?: number;
  idPunto?: number | null;
  punto: string;
  orden?: number;
  cantidadSube: number;
  cantidadBaja: number;
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
