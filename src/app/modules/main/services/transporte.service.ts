import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { environment } from '@/environments/environment';
import { lastValueFrom } from 'rxjs';
import { AsignacionUnidad, Auditoria, IndicadoresReporte, Motivo, Parada, Punto, Solicitud, Traslado, Unidad } from '@/app/models/transporte.models';
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

  listarSolicitudes(filtro: { fecha?: string; estado?: string } = {}): Promise<Solicitud[]> {
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

  agregarPasajeros(idSolicitud: number, cantidad: number, idSolicitudUnidad?: number | null): Promise<Solicitud[]> {
    return this.mutar<Solicitud[]>('conductor/agregar-pasajeros', { idSolicitud, idSolicitudUnidad, cantidad }).then(r => this.unwrap(r));
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

  administrarCatalogo(entidad: 'USUARIO' | 'UNIDAD' | 'PUNTO' | 'MOTIVO', accion: 'LISTAR' | 'GUARDAR' | 'ELIMINAR', datos: any = {}): Promise<any[]> {
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
        await this.dexie.incrementarIntento(operacion);
        break;
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
