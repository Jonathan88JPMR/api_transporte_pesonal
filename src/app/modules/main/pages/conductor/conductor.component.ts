import { Component, OnDestroy, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TableModule } from 'primeng/table';
import { TagModule } from 'primeng/tag';
import { ButtonModule } from 'primeng/button';
import { TooltipModule } from 'primeng/tooltip';
import { SelectModule } from 'primeng/select';
import { TransporteService } from '../../services/transporte.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';
import { AuthService } from '@/app/modules/auth/services/auth.service';
import { EstadoParada, Parada, PosicionGeo, Punto, Solicitud, Unidad, Usuario } from '@/app/models/transporte.models';
import { MapaComponent, PuntoMapa } from '@/app/shared/mapa/mapa.component';

@Component({
  selector: 'app-conductor',
  standalone: true,
  imports: [CommonModule, FormsModule, TableModule, TagModule, ButtonModule, TooltipModule, SelectModule, MapaComponent],
  templateUrl: './conductor.component.html',
  styleUrl: './conductor.component.scss'
})
export class ConductorComponent implements OnInit, OnDestroy {

  servicios: Solicitud[] = [];
  usuario?: Usuario;
  puntos: Punto[] = [];
  unidades: Unidad[] = [];
  ubicacionActual?: { latitud: number; longitud: number };
  servicioMapa?: Solicitud;
  puntosMapaSel: PuntoMapa[] = [];
  origenMapa?: PuntoMapa;
  servicioPasajeros?: Solicitud;
  pasajerosExtra = 1;
  cargando = false;
  fechaFiltro = this.fechaLocal();
  // Registro en la parada actual: qué parada se está cargando y los conteos reales
  paradaRegistrando?: { servicio: Solicitud; parada: Parada };
  subenReal = 0;
  bajanReal = 0;
  marcando = false;
  // Parada imprevista: el conductor puede insertar una parada no programada en ruta
  agregandoParada = false;
  paradaNuevaPunto?: string;
  paradaNuevaCantidad = 1;
  // Ping GPS cada 30 s mientras la unidad tenga servicios EN_RUTA
  private timerGps?: ReturnType<typeof setInterval>;

  constructor(
    private transporteService: TransporteService,
    private alertService: AlertService,
    private authService: AuthService
  ) { }

  async ngOnInit() {
    this.usuario = await this.authService.getUser();
    try {
      [this.puntos, this.unidades] = await Promise.all([
        this.transporteService.listarPuntos(),
        this.transporteService.listarUnidades()
      ]);
    } catch { this.puntos = []; this.unidades = []; }
    this.obtenerUbicacion();
    await this.cargar();
    this.reportarGps();
    this.timerGps = setInterval(() => this.reportarGps(), 30000);
  }

  ngOnDestroy() {
    if (this.timerGps) clearInterval(this.timerGps);
  }

  // Ubicación en vivo: se reporta a cada traslado EN_RUTA de la unidad
  // (una solicitud multi-unidad puede tener varios traslados por placa).
  private reportarGps() {
    if (!navigator.geolocation || !this.usuario?.placa) return;
    const traslados = new Set(
      this.servicios
        .filter(s => s.estado === 'EN_RUTA' && s.idTraslado != null)
        .map(s => s.idTraslado!)
    );
    if (!traslados.size) return;
    navigator.geolocation.getCurrentPosition(pos => {
      const geo: PosicionGeo = {
        latitud: pos.coords.latitude,
        longitud: pos.coords.longitude,
        precision: pos.coords.accuracy
      };
      this.ubicacionActual = { latitud: geo.latitud, longitud: geo.longitud };
      traslados.forEach(idTraslado =>
        this.transporteService.reportarUbicacion(idTraslado, this.usuario!.placa!, geo));
    });
  }

  async cargar() {
    if (!this.usuario?.placa) {
      this.alertService.showAlert('warning', 'Este usuario no tiene una unidad asignada', 'Atención');
      return;
    }
    this.cargando = true;
    try {
      this.servicios = await this.transporteService.serviciosConductor(this.usuario.placa, this.fechaFiltro || undefined);
    } catch {
      this.alertService.showAlert('error', 'No se pudieron cargar los servicios', 'Error');
    } finally {
      this.cargando = false;
    }
  }

  async cambiarEstado(s: Solicitud, estado: 'ASIGNADO' | 'EN_RUTA' | 'REALIZADO') {
    try {
      await this.transporteService.cambiarEstado(s.idSolicitud, estado, s.idSolicitudUnidad, this.usuario?.usuario);
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo actualizar el servicio', 'Error');
    }
  }

  obtenerUbicacion() {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(pos => {
      this.ubicacionActual = { latitud: pos.coords.latitude, longitud: pos.coords.longitude };
      this.origenMapa = { ...this.ubicacionActual, etiqueta: 'Mi ubicación' };
    });
  }

  // Posición GPS en el momento del evento (marca de parada). Si el usuario
  // niega el permiso o tarda, se envía sin coordenadas para no bloquear.
  private posicionActual(): Promise<PosicionGeo | undefined> {
    if (!navigator.geolocation) return Promise.resolve(undefined);
    return new Promise(resolve =>
      navigator.geolocation.getCurrentPosition(
        pos => resolve({ latitud: pos.coords.latitude, longitud: pos.coords.longitude }),
        () => resolve(undefined),
        { timeout: 5000 }
      )
    );
  }

  verMapa(s: Solicitud) {
    const puntos = this.puntosMapaServicio(s);
    if (!puntos.length) {
      this.alertService.showAlert('warning', 'La ruta no tiene puntos con coordenadas registradas', 'Atención');
      return;
    }
    if (this.servicioMapa?.idSolicitud === s.idSolicitud) {
      this.servicioMapa = undefined;
      this.puntosMapaSel = [];
      return;
    }
    this.puntosMapaSel = puntos;
    this.servicioMapa = s;
  }

  // Paradas del servicio en orden de recorrido (el backend puede no mandarlas ordenadas)
  paradasOrdenadas(s?: Solicitud): Parada[] {
    return [...(s?.paradas ?? [])].sort((a, b) => (a.orden ?? 0) - (b.orden ?? 0));
  }

  get paradasMapa(): Parada[] {
    return this.paradasOrdenadas(this.servicioMapa);
  }

  // ===== Seguimiento de paradas (checklist del conductor) =====

  // Primera parada no ejecutada: es la única sobre la que se puede actuar.
  paradaActual(s: Solicitud): Parada | undefined {
    return this.paradasOrdenadas(s).find(p => (p.estado ?? 'PENDIENTE') === 'PENDIENTE' || p.estado === 'EN_PARADA');
  }

  esParadaActual(s: Solicitud, p: Parada): boolean {
    return this.paradaActual(s)?.idParada === p.idParada;
  }

  // Solo se marcan paradas con la unidad en ruta
  puedeMarcarParadas(s: Solicitud): boolean {
    return s.estado === 'EN_RUTA' && !!this.paradaActual(s);
  }

  resumenParadas(s: Solicitud): string {
    const paradas = s.paradas ?? [];
    if (!paradas.length) return '';
    const hechas = paradas.filter(p => p.estado === 'REALIZADA' || p.estado === 'OMITIDA').length;
    return `${hechas}/${paradas.length}`;
  }

  // Pasajeros a bordo al salir de la parada i: conteo real si existe, planeado si no
  aBordoTramo(s: Solicitud, indice: number): number {
    return this.paradasOrdenadas(s).slice(0, indice + 1).reduce((a, p) => {
      const sube = p.subieronReal ?? p.cantidadSube ?? 0;
      const baja = p.bajaronReal ?? p.cantidadBaja ?? 0;
      return a + sube - baja;
    }, 0);
  }

  severidadParada(estado?: EstadoParada): 'success' | 'info' | 'warn' | 'danger' | 'secondary' {
    switch (estado ?? 'PENDIENTE') {
      case 'REALIZADA': return 'success';
      case 'EN_PARADA': return 'info';
      case 'OMITIDA': return 'danger';
      default: return 'warn';
    }
  }

  // PENDIENTE → EN_PARADA: marca la llegada con hora y GPS del dispositivo
  async llegarParada(s: Solicitud, p: Parada) {
    if (!p.idParada || this.marcando) return;
    this.marcando = true;
    try {
      const geo = await this.posicionActual();
      await this.transporteService.llegadaParada(p.idParada, geo);
      await this.cargar();
      if (this.servicioMapa?.idSolicitud === s.idSolicitud) {
        this.servicioMapa = this.servicios.find(x => x.idSolicitud === s.idSolicitud);
      }
    } catch {
      this.alertService.showAlert('error', 'No se pudo marcar la llegada a la parada', 'Error');
    } finally {
      this.marcando = false;
    }
  }

  // EN_PARADA → formulario de conteos reales (prellenado con lo planeado)
  abrirRegistroParada(s: Solicitud, p: Parada) {
    this.paradaRegistrando = { servicio: s, parada: p };
    this.subenReal = p.cantidadSube ?? 0;
    this.bajanReal = p.cantidadBaja ?? 0;
  }

  cancelarRegistroParada() {
    this.paradaRegistrando = undefined;
  }

  // EN_PARADA → REALIZADA
  async confirmarRegistroParada() {
    const ctx = this.paradaRegistrando;
    if (!ctx?.parada.idParada || this.marcando) return;
    if (this.subenReal < 0 || this.bajanReal < 0) return;
    this.marcando = true;
    try {
      const geo = await this.posicionActual();
      await this.transporteService.registrarParada(ctx.parada.idParada, this.subenReal, this.bajanReal, ctx.parada.detalle, geo);
      this.paradaRegistrando = undefined;
      await this.cargar();
      if (this.servicioMapa?.idSolicitud === ctx.servicio.idSolicitud) {
        this.servicioMapa = this.servicios.find(x => x.idSolicitud === ctx.servicio.idSolicitud);
      }
    } catch {
      this.alertService.showAlert('error', 'No se pudo registrar la parada', 'Error');
    } finally {
      this.marcando = false;
    }
  }

  // Inserta una parada no programada como la siguiente del recorrido
  // (recojo no previsto, desvío, punto de control, etc.)
  abrirParadaImprevista() {
    this.agregandoParada = true;
    this.paradaNuevaPunto = undefined;
    this.paradaNuevaCantidad = 1;
  }

  async guardarParadaImprevista(s: Solicitud) {
    if (!this.paradaNuevaPunto || this.paradaNuevaCantidad < 1 || this.marcando) return;
    this.marcando = true;
    try {
      const geo = await this.posicionActual();
      await this.transporteService.agregarParadaImprevista(
        s.idTraslado ?? null, s.idTraslado ? null : s.idSolicitud,
        this.paradaNuevaPunto, this.paradaNuevaCantidad, geo);
      this.agregandoParada = false;
      await this.cargar();
      if (this.servicioMapa?.idSolicitud === s.idSolicitud) {
        this.servicioMapa = this.servicios.find(x => x.idSolicitud === s.idSolicitud);
      }
    } catch {
      this.alertService.showAlert('error', 'No se pudo agregar la parada', 'Error');
    } finally {
      this.marcando = false;
    }
  }

  // PENDIENTE/EN_PARADA → OMITIDA (pasajeros no se presentaron, punto sin movimiento, etc.)
  async omitirParada(s: Solicitud, p: Parada) {
    if (!p.idParada || this.marcando) return;
    const previsto = (p.cantidadSube ?? 0) + (p.cantidadBaja ?? 0);
    const motivo = await this.alertService.input(
      'Omitir parada',
      `¿Por qué se omite "${p.punto}"?` + (previsto > 0 ? ` Estaba previsto que suban/bajen ${previsto} pasajeros.` : ''),
      'Motivo de la omisión'
    );
    if (motivo === undefined) return;
    this.marcando = true;
    try {
      await this.transporteService.omitirParada(p.idParada, motivo);
      await this.cargar();
      if (this.servicioMapa?.idSolicitud === s.idSolicitud) {
        this.servicioMapa = this.servicios.find(x => x.idSolicitud === s.idSolicitud);
      }
    } catch {
      this.alertService.showAlert('error', 'No se pudo omitir la parada', 'Error');
    } finally {
      this.marcando = false;
    }
  }

  puntosMapaServicio(s: Solicitud): PuntoMapa[] {
    // RF-023: si el traslado tiene paradas definidas, el mapa sigue ese orden
    const nombres = s.paradas?.length ? s.paradas.map(p => p.punto) : [s.puntoPartida, s.puntoLlegada];
    return nombres
      .map(n => this.puntos.find(p => p.nombre === n))
      .filter(p => p?.latitud != null && p?.longitud != null)
      .map(p => ({ latitud: p!.latitud!, longitud: p!.longitud!, etiqueta: p!.nombre }));
  }

  // Cupo del viaje: ocupación de la unidad en los servicios activos del día
  cupoServicio(s: Solicitud): { ocupada: number; libre: number; capacidad: number } | null {
    const unidad = this.unidades.find(u => u.placa === this.usuario?.placa);
    if (!unidad) return null;
    const ocupada = this.servicios
      .filter(x => x.fechaProgramada === s.fechaProgramada && (x.estado === 'ASIGNADO' || x.estado === 'EN_RUTA'))
      .reduce((a, x) => a + (x.cantidad ?? 0), 0);
    return { ocupada, libre: unidad.capacidad - ocupada, capacidad: unidad.capacidad };
  }

  severidadCupo(s: Solicitud): 'success' | 'warn' | 'danger' {
    const c = this.cupoServicio(s);
    if (!c) return 'success';
    return c.libre <= 0 ? 'danger' : c.libre <= c.capacidad * 0.25 ? 'warn' : 'success';
  }

  // RF-024: el conductor registra pasajeros extra de emergencia si hay cupo
  abrirPasajeros(s: Solicitud) {
    this.servicioPasajeros = s;
    this.pasajerosExtra = 1;
  }

  async guardarPasajeros() {
    const s = this.servicioPasajeros;
    if (!s || this.pasajerosExtra < 1) return;
    const cupo = this.cupoServicio(s);
    if (cupo && this.pasajerosExtra > cupo.libre) {
      this.alertService.showAlert('warning', `La unidad solo tiene ${cupo.libre} asientos libres`, 'Sin cupo');
      return;
    }
    try {
      // Si el servicio tiene ruta con paradas, el extra se amarra a la parada actual
      await this.transporteService.agregarPasajeros(
        s.idSolicitud, this.pasajerosExtra, s.idSolicitudUnidad, this.paradaActual(s)?.idParada ?? null);
      this.servicioPasajeros = undefined;
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No hay cupo suficiente en la unidad', 'Error');
    }
  }

  mapaUrl(s: Solicitud): string | null {
    const destino = this.puntos.find(p => p.nombre === s.puntoLlegada && p.latitud != null && p.longitud != null);
    if (!destino) return null;
    const origen = this.ubicacionActual;
    if (origen) return `https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=${origen.latitud},${origen.longitud};${destino.latitud},${destino.longitud}`;
    return `https://www.openstreetmap.org/?mlat=${destino.latitud}&mlon=${destino.longitud}#map=16/${destino.latitud}/${destino.longitud}`;
  }

  verTodas() {
    this.fechaFiltro = '';
    void this.cargar();
  }

  verHoy() {
    this.fechaFiltro = this.fechaLocal();
    void this.cargar();
  }

  fechaLocal(d = new Date()): string {
    const p = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  }

  // Ruta del día: usa la ruta definida del traslado si existe; los servicios
  // sueltos se encadenan por hora programada.
  get rutaDelDia(): string {
    if (!this.fechaFiltro) return ''; // sin fecha no hay "día" que resumir
    const activos = this.servicios
      .filter(s => !s.realizado && s.estado !== 'ANULADO')
      .sort((a, b) => (a.horaProgramada ?? '').localeCompare(b.horaProgramada ?? ''));
    if (!activos.length) return '';

    const rutas: string[] = [];
    const trasladosVistos = new Set<number>();
    const sueltos: Solicitud[] = [];

    for (const s of activos) {
      if (s.idTraslado != null) {
        if (!trasladosVistos.has(s.idTraslado)) {
          trasladosVistos.add(s.idTraslado);
          rutas.push(s.ruta || `${s.puntoPartida} > ${s.puntoLlegada}`);
        }
      } else {
        sueltos.push(s);
      }
    }
    if (sueltos.length) {
      const puntos = sueltos.map(s => s.puntoPartida);
      puntos.push(sueltos[sueltos.length - 1].puntoLlegada);
      rutas.push(puntos.join(' > '));
    }
    return rutas.join('  ·  ');
  }
}
