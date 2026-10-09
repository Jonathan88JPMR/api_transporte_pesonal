import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '@/environments/environment';
import { lastValueFrom } from 'rxjs';
import { AsignacionUnidad, Auditoria, IndicadoresReporte, Motivo, Parada, ParadaDetalle, PosicionGeo, ProgresoTraslado, Punto, Solicitud, Traslado, Unidad } from '@/app/models/transporte.models';
import { DexieService } from '@/app/shared/dixiedb/dexie-db.service';

@Injectable({
  providedIn: 'root'
})
export class TransporteService {
  private readonly baseUrl: string = `${environment.baseUrl}/api/transporte`;

  constructor(private http: HttpClient, private dexie: DexieService) {
    window.addEventListener('online', () => void this.sincronizarPendientes());
    if (navigator.onLine) void this.sincronizarPendientes();
  }

  // ============ Solicitudes ============

  listarSolicitudes(filtro: { fecha?: string; estado?: string; usuario?: string } = {}): Promise<Solicitud[]> {
    return this.consultar<Solicitud[]>('solicitudes/listar', filtro).then(r => this.unwrap(r));
  }

  async guardarSolicitud(solicitud: Partial<Solicitud>): Promise<Solicitud[]> {
    return this.mutar<Solicitud[]>('solicitudes/guardar', solicitud).then(r => this.unwrap(r));
  }

  eliminarSolicitud(idSolicitud: number): Promise<any> {
    return this.mutar('solicitudes/eliminar', { idSolicitud }).then(r => this.unwrap(r));
  }

  marcarRealizado(idSolicitud: number, realizado: boolean): Promise<Solicitud[]> {
    return this.mutar<Solicitud[]>('solicitudes/realizado', { idSolicitud, realizado }).then(r => this.unwrap(r));
  }

  cambiarEstado(idSolicitud: number, estado: 'PENDIENTE' | 'ASIGNADO' | 'EN_RUTA' | 'REALIZADO', idSolicitudUnidad?: number | null, usuario?: string): Promise<Solicitud[]> {
    return this.mutar<Solicitud[]>('solicitudes/estado', { idSolicitud, estado, idSolicitudUnidad, usuario }).then(r => this.unwrap(r));
  }

  // ============ Traslados ============

  asignarUnidad(idSolicitud: number, placa: string): Promise<Solicitud[]> {
    return this.mutar<Solicitud[]>('solicitudes/asignar', { idSolicitud, placa }).then(r => this.unwrap(r));
  }

  desasignarUnidad(idSolicitud: number): Promise<Solicitud[]> {
    return this.mutar<Solicitud[]>('solicitudes/desasignar', { idSolicitud }).then(r => this.unwrap(r));
  }

  unirSolicitudes(ids: number[], placa: string): Promise<Traslado[]> {
    return this.mutar<Traslado[]>('traslados/unir', { ids, placa }).then(r => this.unwrap(r));
  }

  separarSolicitud(idSolicitud: number): Promise<Solicitud[]> {
    return this.mutar<Solicitud[]>('traslados/separar', { idSolicitud }).then(r => this.unwrap(r));
  }

  listarTraslados(filtro: { fecha?: string } = {}): Promise<Traslado[]> {
    return this.consultar<Traslado[]>('traslados/listar', filtro).then(r => this.unwrap(r));
  }

  guardarParadas(idTraslado: number, paradas: Parada[], usuario?: string): Promise<Parada[]> {
    return this.mutar<Parada[]>('traslados/paradas', { idTraslado, paradas, usuario }).then(r => this.unwrap(r));
  }

  // ============ Seguimiento de paradas ============
  // horaCliente conserva el timestamp real del evento: si el dispositivo está
  // offline, la mutación se encola y se sincroniza después con su hora original.

  llegadaParada(idParada: number, geo?: PosicionGeo): Promise<Parada[]> {
    return this.mutar<Parada[]>('paradas/llegada', {
      idParada, horaCliente: new Date().toISOString(),
      latitud: geo?.latitud, longitud: geo?.longitud
    }).then(r => this.unwrap(r));
  }

  registrarParada(idParada: number, subieronReal: number, bajaronReal: number,
                  detalle?: ParadaDetalle[], geo?: PosicionGeo): Promise<Parada[]> {
    return this.mutar<Parada[]>('paradas/registrar', {
      idParada, subieronReal, bajaronReal, detalle,
      horaCliente: new Date().toISOString(),
      latitud: geo?.latitud, longitud: geo?.longitud
    }).then(r => this.unwrap(r));
  }

  omitirParada(idParada: number, motivo: string): Promise<Parada[]> {
    return this.mutar<Parada[]>('paradas/omitir', {
      idParada, motivo, horaCliente: new Date().toISOString()
    }).then(r => this.unwrap(r));
  }

  // Parada no programada que el conductor inserta en ruta (p. ej. desvío).
  // Se agrega como la siguiente parada pendiente del recorrido.
  agregarParadaImprevista(idTraslado: number | null, idSolicitud: number | null,
                        punto: string, cantidadSube: number, geo?: PosicionGeo): Promise<Parada[]> {
    return this.mutar<Parada[]>('paradas/imprevista', {
      idTraslado, idSolicitud, punto, cantidadSube,
      horaCliente: new Date().toISOString(),
      latitud: geo?.latitud, longitud: geo?.longitud
    }).then(r => this.unwrap(r));
  }

  // Consulta liviana para refrescar el progreso sin recargar todo el traslado
  progresoTraslado(idTraslado: number): Promise<ProgresoTraslado | undefined> {
    return this.consultar<ProgresoTraslado[]>('traslados/progreso', { idTraslado })
      .then(r => this.unwrap(r)[0]);
  }

  // Ping GPS de la unidad en ruta. Va directo (sin cola offline ni
  // idOperacion): una posición vieja encolada no aporta, solo la última sirve.
  reportarUbicacion(idTraslado: number, placa: string, geo: PosicionGeo): void {
    if (!navigator.onLine || geo.latitud == null || geo.longitud == null) return;
    let usuario: string | undefined;
    try { usuario = JSON.parse(localStorage.getItem('usuario') ?? '{}').usuario; } catch { }
    this.post('unidades/ubicacion', {
      idTraslado, placa, usuario,
      latitud: geo.latitud, longitud: geo.longitud, precision: geo.precision,
      fechaHoraCliente: new Date().toISOString()
    }).catch(() => { });
  }

  acoplarSolicitud(idSolicitud: number, idTraslado: number, usuario?: string): Promise<Solicitud[]> {
    return this.mutar<Solicitud[]>('traslados/acoplar', { idSolicitud, idTraslado, usuario }).then(r => this.unwrap(r));
  }

  asignarMultiplesUnidades(idSolicitud: number, unidades: AsignacionUnidad[], usuario?: string): Promise<any[]> {
    return this.mutar<any[]>('solicitudes/asignar-multiples', { idSolicitud, unidades, usuario }).then(r => this.unwrap(r));
  }

  // ============ Conductor ============

  serviciosConductor(placa: string, fecha?: string): Promise<Solicitud[]> {
    return this.consultar<Solicitud[]>('conductor/servicios', { placa, fecha }).then(r => this.unwrap(r));
  }

  // Servicios activos de cada unidad (las asignaciones múltiples llegan como
  // porciones con idSolicitudUnidad). Fuente real de la ocupación por placa.
  serviciosPorPlacas(placas: string[]): Promise<{ placa: string; servicios: Solicitud[] }[]> {
    return Promise.all(placas.map(async placa => {
      try {
        return { placa, servicios: await this.serviciosConductor(placa) };
      } catch {
        return { placa, servicios: [] as Solicitud[] };
      }
    }));
  }

  // idParada: si el extra sube en una parada concreta, queda registrado ahí
  agregarPasajeros(idSolicitud: number, cantidad: number, idSolicitudUnidad?: number | null, idParada?: number | null): Promise<Solicitud[]> {
    return this.mutar<Solicitud[]>('conductor/agregar-pasajeros', { idSolicitud, idSolicitudUnidad, cantidad, idParada }).then(r => this.unwrap(r));
  }

  // ============ Catálogos ============

  listarPuntos(): Promise<Punto[]> {
    return this.consultar<Punto[]>('catalogos/puntos', {}).then(r => this.unwrap(r));
  }

  listarUnidades(): Promise<Unidad[]> {
    return this.consultar<Unidad[]>('catalogos/unidades', {}).then(r => this.unwrap(r));
  }

  listarMotivos(): Promise<Motivo[]> {
    return this.consultar<Motivo[]>('catalogos/motivos', {}).then(r => this.unwrap(r));
  }

  // ============ Reportes ============

  reporteSolicitudes(desde?: string, hasta?: string): Promise<Solicitud[]> {
    return this.post<Solicitud[]>('reportes/solicitudes', { desde, hasta }).then(r => this.unwrap(r));
  }

  reporteIndicadores(desde?: string, hasta?: string): Promise<IndicadoresReporte | undefined> {
    return this.post<IndicadoresReporte[]>('reportes/indicadores', { desde, hasta }).then(r => this.unwrap(r)[0]);
  }

  listarAuditoria(): Promise<Auditoria[]> {
    return this.post<Auditoria[]>('reportes/auditoria', {}).then(r => this.unwrap(r));
  }

  administrarCatalogo(entidad: 'USUARIO' | 'UNIDAD' | 'PUNTO' | 'MOTIVO' | 'AREA', accion: 'LISTAR' | 'GUARDAR' | 'ELIMINAR', datos: any = {}): Promise<any[]> {
    return this.mutar<any[]>('administracion/catalogo', { entidad, accion, ...datos }).then(r => this.unwrap(r));
  }

  cambiarClave(usuario: string, claveActual: string, claveNueva: string): Promise<any> {
    return this.post<any>('auth/cambiar-clave', { usuario, claveActual, claveNueva });
  }

  listarNotificaciones(idUsuario: number): Promise<any[]> {
    return this.post<any[]>('notificaciones/listar', { idUsuario }).then(r => this.unwrap(r));
  }

  marcarNotificacion(idUsuario: number, idNotificacion: number): Promise<any[]> {
    return this.mutar<any[]>('notificaciones/marcar-leida', { idUsuario, idNotificacion }).then(r => this.unwrap(r));
  }

  // ============ Internos ============

  async sincronizarPendientes(): Promise<number> {
    if (!navigator.onLine) return 0;
    let sincronizadas = 0;
    for (const operacion of await this.dexie.operacionesPendientes()) {
      try {
        await this.post(operacion.ruta, operacion.cuerpo);
        if (operacion.id) await this.dexie.eliminarOperacion(operacion.id);
        sincronizadas++;
      } catch {
        // Operación "envenenada" (error de validación, etc.): tras N intentos
        // se descarta para no bloquear el resto de la cola.
        if ((operacion.intentos ?? 0) + 1 >= 5 && operacion.id) {
          await this.dexie.eliminarOperacion(operacion.id);
        } else {
          await this.dexie.incrementarIntento(operacion);
          break;
        }
      }
    }
    return sincronizadas;
  }

  private async mutar<T>(path: string, body: any): Promise<T> {
    let usuario: string | undefined;
    try { usuario = JSON.parse(localStorage.getItem('usuario') ?? '{}').usuario; } catch { }
    const payload = { ...body, usuario: body?.usuario ?? usuario, idOperacion: body?.idOperacion ?? crypto.randomUUID() };
    try {
      return await this.post<T>(path, payload);
    } catch (error: any) {
      if (!navigator.onLine || error?.status === 0) {
        await this.dexie.encolarOperacion(path, payload);
        return [] as T;
      }
      throw error;
    }
  }

  private post<T>(path: string, body: unknown): Promise<T> {
    return lastValueFrom(this.http.post<T>(`${this.baseUrl}/${path}`, body));
  }

  // Lectura con respaldo offline: guarda cada respuesta en caché local y la
  // devuelve cuando no hay conexión, para que la app siga funcionando en campo.
  private async consultar<T>(path: string, body: unknown): Promise<T> {
    const clave = `${path}|${JSON.stringify(body ?? {})}`;
    try {
      const datos = await this.post<T>(path, body);
      await this.dexie.guardarCache(clave, datos);
      return datos;
    } catch (error: any) {
      if (!navigator.onLine || error?.status === 0) {
        const cache = await this.dexie.leerCache(clave);
        if (cache !== undefined) return cache as T;
      }
      throw error;
    }
  }

  // El backend devuelve List<JsonElement>: cuando el SP retorna FOR JSON PATH
  // llega como [ [ {...}, {...} ] ] o [ {...} ]; se aplana a un array plano.
  private unwrap(resp: any): any[] {
    if (!resp) return [];
    if (Array.isArray(resp) && resp.length === 1 && Array.isArray(resp[0])) {
      return resp[0];
    }
    return resp;
  }
}
