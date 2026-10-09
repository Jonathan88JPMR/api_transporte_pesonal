import { Component, OnDestroy, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TableModule } from 'primeng/table';
import { SelectModule } from 'primeng/select';
import { ButtonModule } from 'primeng/button';
import { TagModule } from 'primeng/tag';
import { CheckboxModule } from 'primeng/checkbox';
import { TooltipModule } from 'primeng/tooltip';
import { DialogModule } from 'primeng/dialog';
import { TransporteService } from '../../services/transporte.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';
import { AuthService } from '@/app/modules/auth/services/auth.service';
import { AsignacionUnidad, EstadoParada, Motivo, Parada, ProgresoTraslado, Punto, Solicitud, Traslado, Unidad, Usuario } from '@/app/models/transporte.models';
import { MapaComponent, PuntoMapa } from '@/app/shared/mapa/mapa.component';

@Component({
  selector: 'app-coordinador',
  standalone: true,
  imports: [CommonModule, FormsModule, TableModule, SelectModule, ButtonModule, TagModule, CheckboxModule, TooltipModule, DialogModule, MapaComponent],
  templateUrl: './coordinador.component.html',
  styleUrl: './coordinador.component.scss'
})
export class CoordinadorComponent implements OnInit, OnDestroy {

  solicitudes: Solicitud[] = [];
  traslados: Traslado[] = [];
  unidades: Unidad[] = [];
  puntos: Punto[] = [];
  motivos: Motivo[] = [];
  usuario?: Usuario;

  seleccionadas: Solicitud[] = [];
  placaUnir?: string;
  placasAsignar: Record<number, string | undefined> = {};

  cargando = false;
  // Paginación del panel de traslados (evita scroll vertical largo)
  paginaTraslados = 0;
  readonly trasladosPorPagina = 5;

  get paginasTraslados(): number {
    return Math.max(1, Math.ceil(this.traslados.length / this.trasladosPorPagina));
  }

  trasladosPagina(): Traslado[] {
    const ini = this.paginaTraslados * this.trasladosPorPagina;
    return this.traslados.slice(ini, ini + this.trasladosPorPagina);
  }

  irPaginaTraslados(delta: number) {
    this.paginaTraslados = Math.min(Math.max(0, this.paginaTraslados + delta), this.paginasTraslados - 1);
  }

  // Fecha de trabajo de la vista: tabla, badges de cupo y combos usan esta fecha.
  fechaFiltro = this.fechaLocal();
  trasladoEditando?: Traslado;
  trasladoMapa?: Traslado;

  // Flags two-way para los modales (p-dialog necesita [(visible)] writable:
  // con [visible] de solo lectura la X no puede cerrarlo)
  get mapaAbierto(): boolean { return !!this.trasladoMapa; }
  set mapaAbierto(v: boolean) {
    if (!v) {
      this.trasladoMapa = undefined;
      this.puntosMapaT = [];
      this.origenMapaT = undefined;
      if (this.timerMapa) { clearInterval(this.timerMapa); this.timerMapa = undefined; }
    }
  }

  get progresoAbierto(): boolean { return !!this.trasladoProgreso; }
  set progresoAbierto(v: boolean) { if (!v) this.cerrarProgreso(); }

  get editorAbierto(): boolean { return !!this.trasladoEditando; }
  set editorAbierto(v: boolean) { if (!v) this.trasladoEditando = undefined; }
  puntosMapaT: PuntoMapa[] = [];
  origenMapaT?: PuntoMapa;
  private timerMapa?: ReturnType<typeof setInterval>;
  paradasEditando: Parada[] = [];
  // Seguimiento en vivo del traslado seleccionado (se refresca por polling)
  trasladoProgreso?: Traslado;
  progreso?: ProgresoTraslado;
  private timerProgreso?: ReturnType<typeof setInterval>;
  solicitudMultiple?: Solicitud;
  asignaciones: AsignacionUnidad[] = [];
  mostrarMultiple = false;
  solicitudEditando?: Solicitud;
  mostrarEdicion = false;
  formEdicion: any = {};

  constructor(
    private transporteService: TransporteService,
    private alertService: AlertService,
    private authService: AuthService
  ) { }

  async ngOnInit() {
    this.usuario = await this.authService.getUser();
    await Promise.all([this.cargar(), this.cargarUnidades(), this.cargarPuntos()]);
    try { this.motivos = await this.transporteService.listarMotivos(); } catch { this.motivos = []; }
  }

  async cargar() {
    this.cargando = true;
    try {
      [this.solicitudes, this.traslados] = await Promise.all([
        this.transporteService.listarSolicitudes(),
        this.transporteService.listarTraslados(this.fechaFiltro ? { fecha: this.fechaFiltro } : {})
      ]);
      this.seleccionadas = [];
      this.paginaTraslados = 0;
      this.anuladasCargadas = false; // el tab Anuladas se recarga al abrirse
      void this.cargarPorciones();
    } catch {
      this.alertService.showAlert('error', 'No se pudieron cargar los datos', 'Error');
    } finally {
      this.cargando = false;
    }
  }

  async cargarUnidades() {
    try {
      this.unidades = await this.transporteService.listarUnidades();
      void this.cargarPorciones();
    } catch { }
  }

  async cargarPuntos() {
    try {
      this.puntos = await this.transporteService.listarPuntos();
    } catch { this.puntos = []; }
  }

  // RF-012: opciones del select con cupo visible; sin cupo quedan deshabilitadas.
  // El cupo se calcula por fecha; si la solicitud no es de hoy, se indica la fecha.
  unidadesOpcionesFecha(fecha?: string) {
    const sufijo = fecha && fecha.slice(0, 10) !== this.fechaLocal()
      ? ` (${fecha.slice(8, 10)}/${fecha.slice(5, 7)})` : '';
    return this.unidades.map(u => {
      const libre = this.cupoLibre(u.placa, fecha);
      return { ...u, etiqueta: `${u.placa} · ${libre}/${u.capacidad} libres${sufijo}`, sinCupo: libre <= 0 };
    });
  }

  // Cupo real = capacidad - personas con servicios ASIGNADO/EN_RUTA en esa fecha
  cupoLibre(placa: string | undefined | null, fecha?: string): number {
    if (!placa) return 0;
    const u = this.unidades.find(x => x.placa === placa);
    if (!u) return 0;
    const f = (fecha ?? this.fechaLocal()).slice(0, 10);
    return u.capacidad - (this.ocupaciones[placa]?.[f] ?? 0);
  }

  cupoUnidad(u: Unidad): number { return this.cupoLibre(u.placa, this.fechaFiltro); }

  // Tabs de estado: la vista operativa muestra las activas (PENDIENTE/ASIGNADO/
  // EN_RUTA); realizadas y anuladas van en tabs aparte para no confundir
  tabEstado: 'ACTIVAS' | 'REALIZADO' | 'ANULADO' = 'ACTIVAS';
  solicitudesAnuladas: Solicitud[] = [];
  private anuladasCargadas = false;

  seleccionarTab(t: 'ACTIVAS' | 'REALIZADO' | 'ANULADO') {
    this.tabEstado = t;
    if (t === 'ANULADO' && !this.anuladasCargadas) void this.cargarAnuladas();
  }

  private async cargarAnuladas() {
    try {
      this.solicitudesAnuladas = await this.transporteService.listarSolicitudes({ estado: 'ANULADO' });
      this.anuladasCargadas = true;
    } catch { this.solicitudesAnuladas = []; }
  }

  private baseFecha(src: Solicitud[]): Solicitud[] {
    if (!this.fechaFiltro) return src; // modo "Todas"
    return src.filter(s => (s.fechaProgramada ?? '').slice(0, 10) === this.fechaFiltro);
  }

  solicitudesFiltradas(): Solicitud[] {
    const fuente = this.tabEstado === 'ANULADO' ? this.solicitudesAnuladas : this.solicitudes;
    const porFecha = this.baseFecha(fuente);
    switch (this.tabEstado) {
      case 'REALIZADO': return porFecha.filter(s => s.estado === 'REALIZADO');
      case 'ANULADO': return porFecha;
      default: return porFecha.filter(s => s.estado !== 'REALIZADO');
    }
  }

  conteoTab(t: 'ACTIVAS' | 'REALIZADO' | 'ANULADO'): number {
    if (t === 'ANULADO') return this.baseFecha(this.solicitudesAnuladas).length;
    const activas = this.baseFecha(this.solicitudes);
    return t === 'REALIZADO'
      ? activas.filter(s => s.estado === 'REALIZADO').length
      : activas.filter(s => s.estado !== 'REALIZADO').length;
  }

  pendientesOtrosDias(): number {
    return this.solicitudes.filter(s => s.estado === 'PENDIENTE'
      && (s.fechaProgramada ?? '').slice(0, 10) !== this.fechaFiltro).length;
  }

  // "05/10 (2) · 04/10 (1)" — fechas con pendientes fuera del día seleccionado.
  resumenPendientes(): string {
    const porFecha = new Map<string, number>();
    for (const s of this.solicitudes) {
      const f = (s.fechaProgramada ?? '').slice(0, 10);
      if (s.estado === 'PENDIENTE' && f && f !== this.fechaFiltro) {
        porFecha.set(f, (porFecha.get(f) ?? 0) + 1);
      }
    }
    const fechas = [...porFecha.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    const visibles = fechas.slice(0, 3).map(([f, n]) => `${f.slice(8, 10)}/${f.slice(5, 7)} (${n})`);
    if (fechas.length > 3) visibles.push(`+${fechas.length - 3} más`);
    return visibles.join(' · ');
  }

  // Salta a la fecha pendiente más antigua.
  irAPendienteAntiguo() {
    const fechas = this.solicitudes
      .filter(s => s.estado === 'PENDIENTE')
      .map(s => (s.fechaProgramada ?? '').slice(0, 10))
      .filter(f => f && f !== this.fechaFiltro)
      .sort();
    if (!fechas.length) return;
    this.fechaFiltro = fechas[0];
    this.alCambiarFecha();
  }

  alCambiarFecha() {
    this.seleccionadas = [];
    this.placaUnir = undefined;
    void this.cargarTraslados();
  }

  verTodas() {
    this.fechaFiltro = '';
    this.alCambiarFecha();
  }

  verHoy() {
    this.fechaFiltro = this.fechaLocal();
    this.alCambiarFecha();
  }

  async cargarTraslados() {
    try {
      this.traslados = await this.transporteService.listarTraslados(this.fechaFiltro ? { fecha: this.fechaFiltro } : {});
    } catch { this.traslados = []; }
  }

  fechaLocal(d = new Date()): string {
    const p = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  }

  claseUnidad(u: Unidad): string {
    const libre = this.cupoUnidad(u);
    if (libre <= 0) return 'bg-danger';
    if (!u.disponible || libre < u.capacidad) return 'bg-warning text-dark';
    return 'bg-success';
  }

  capacidadDe(placa?: string | null): number {
    return this.unidades.find(u => u.placa === placa)?.capacidad ?? 0;
  }

  severidadEstado(estado?: string): 'success' | 'info' | 'warn' | 'danger' | 'secondary' {
    switch (estado) {
      case 'REALIZADO': return 'success';
      case 'EN_RUTA': return 'info';
      case 'ASIGNADO': return 'secondary';
      case 'ANULADO': return 'danger';
      default: return 'warn';
    }
  }

  ocupacionTraslado(t: Traslado): number {
    return (t.solicitudes ?? []).filter(s => s.estado !== 'ANULADO').reduce((a, s) => a + (s.cantidad ?? 0), 0);
  }

  // Solicitudes repartidas en varias unidades: porciones por placa.
  // Desde listarSolicitudes llegan en s.porciones (con su idTraslado);
  // este mapa queda como respaldo construido desde conductor/servicios.
  porcionesPorSolicitud: Record<number, { placa: string; cantidad: number; estado: string; idTraslado?: number | null }[]> = {};
  // Ocupación real por placa y fecha (ASIGNADO/EN_RUTA); el cupoDisponible
  // del catálogo no descuenta asignaciones pendientes.
  ocupaciones: Record<string, Record<string, number>> = {};

  async cargarPorciones() {
    const mapa: Record<number, { placa: string; cantidad: number; estado: string; idTraslado?: number | null }[]> = {};
    const ocup: Record<string, Record<string, number>> = {};
    const porPlaca = await this.transporteService.serviciosPorPlacas(this.unidades.map(u => u.placa));
    for (const { placa, servicios } of porPlaca) {
      for (const s of servicios) {
        if (s.estado === 'ASIGNADO' || s.estado === 'EN_RUTA') {
          const f = (s.fechaProgramada ?? '').slice(0, 10);
          const porFecha = (ocup[placa] ??= {});
          porFecha[f] = (porFecha[f] ?? 0) + (s.cantidad ?? 0);
        }
        if (s.idSolicitudUnidad != null) {
          (mapa[s.idSolicitud] ??= []).push({ placa, cantidad: s.cantidad, estado: s.estado, idTraslado: s.idTraslado ?? null });
        }
      }
    }
    this.porcionesPorSolicitud = mapa;
    this.ocupaciones = ocup;
  }

  unidadesDe(s: Solicitud): { placa: string; cantidad: number; estado: string; idTraslado?: number | null }[] {
    if (s.porciones?.length)
      return s.porciones.map(p => ({ placa: p.placa, cantidad: p.cantidadAsignada, estado: p.estado, idTraslado: p.idTraslado }));
    return this.porcionesPorSolicitud[s.idSolicitud] ?? [];
  }

  detalleUnidades(s: Solicitud): string {
    const partes = this.unidadesDe(s).map(u => `${u.placa} · ${u.cantidad} pers. · ${u.estado}`);
    return partes.length ? partes.join('\n') : 'Sin detalle de unidades';
  }

  severidadCupo(ocupada: number, capacidad: number): 'success' | 'warn' | 'danger' {
    const libre = capacidad - ocupada;
    return libre <= 0 ? 'danger' : libre <= capacidad * 0.25 ? 'warn' : 'success';
  }

  // Asignar placa a una sola solicitud
  async asignar(s: Solicitud) {
    const placa = this.placasAsignar[s.idSolicitud];
    if (!placa) {
      this.alertService.showAlert('warning', 'Seleccione una placa primero', 'Atención');
      return;
    }
    if (s.cantidad > this.cupoLibre(placa, s.fechaProgramada)) {
      this.alertService.showAlert('warning', 'La unidad no tiene capacidad suficiente', 'Atención');
      return;
    }
    try {
      await this.transporteService.asignarUnidad(s.idSolicitud, placa);
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo asignar la unidad', 'Error');
    }
  }

  // RF-013: asignación automática — primera unidad libre con cupo suficiente
  async asignarAutomatico(s: Solicitud) {
    const candidata = this.unidades.find(u => this.cupoLibre(u.placa, s.fechaProgramada) >= s.cantidad);
    if (!candidata) {
      this.alertService.showAlert('warning', 'Ninguna unidad tiene cupo suficiente; use la asignación múltiple', 'Sin cupo');
      return;
    }
    try {
      await this.transporteService.asignarUnidad(s.idSolicitud, candidata.placa);
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo asignar la unidad', 'Error');
    }
  }

  // Devuelve la solicitud a PENDIENTE liberando su(s) unidad(es)
  async desasignar(s: Solicitud) {
    const ok = await this.alertService.confirm('Desasignar unidad',
      `¿Quitar la(s) unidad(es) de la solicitud de ${s.nombre}? Volverá a Pendiente.`);
    if (!ok) return;
    try {
      await this.transporteService.desasignarUnidad(s.idSolicitud);
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo desasignar la unidad', 'Error');
    }
  }

  // RF-003: el jefe de transporte puede modificar o anular cualquier solicitud
  editarSolicitud(s: Solicitud) {
    this.solicitudEditando = s;
    this.formEdicion = {
      fechaProgramada: (s.fechaProgramada ?? '').slice(0, 10),
      horaProgramada: s.horaProgramada,
      puntoPartida: s.puntoPartida,
      puntoLlegada: s.puntoLlegada,
      cantidad: s.cantidad,
      motivo: s.motivo,
      observacion: s.observacion,
      prioridad: s.prioridad ?? 'NORMAL',
      esEmergencia: s.esEmergencia
    };
    this.mostrarEdicion = true;
  }

  cerrarEdicion() {
    this.mostrarEdicion = false;
    this.solicitudEditando = undefined;
  }

  async guardarEdicion() {
    if (!this.solicitudEditando) return;
    try {
      await this.transporteService.guardarSolicitud({
        ...this.formEdicion,
        idSolicitud: this.solicitudEditando.idSolicitud,
        nombre: this.solicitudEditando.nombre,
        area: this.solicitudEditando.area,
        usuarioRegistra: this.usuario?.usuario
      });
      this.cerrarEdicion();
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo guardar la solicitud', 'Error');
    }
  }

  async anularSolicitud(s: Solicitud) {
    const ok = await this.alertService.confirm('Anular solicitud', `¿Anular la solicitud de ${s.nombre}?`);
    if (!ok) return;
    try {
      await this.transporteService.eliminarSolicitud(s.idSolicitud);
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo anular la solicitud', 'Error');
    }
  }

  totalSeleccionadas(): number {
    return this.seleccionadas.reduce((a, s) => a + (s.cantidad ?? 0), 0);
  }

  fechasUnir(): string[] {
    return [...new Set(this.seleccionadas.map(s => (s.fechaProgramada ?? '').slice(0, 10)))];
  }

  excedeCupoUnir(): boolean {
    return !!this.placaUnir && this.totalSeleccionadas() > this.cupoLibre(this.placaUnir, this.fechasUnir()[0]);
  }

  // Unir las solicitudes seleccionadas en un solo traslado con una placa
  async unir() {
    if (this.seleccionadas.length < 2) {
      this.alertService.showAlert('warning', 'Seleccione al menos 2 solicitudes para unir', 'Atención');
      return;
    }
    if (this.fechasUnir().length > 1) {
      this.alertService.showAlert('warning', 'Solo se pueden unir solicitudes de la misma fecha', 'Atención');
      return;
    }
    if (!this.placaUnir) {
      this.alertService.showAlert('warning', 'Seleccione la placa del traslado', 'Atención');
      return;
    }
    if (this.excedeCupoUnir()) {
      this.alertService.showAlert('warning',
        `Las solicitudes suman ${this.totalSeleccionadas()} personas y ${this.placaUnir} tiene ${this.cupoLibre(this.placaUnir, this.fechasUnir()[0])} libres`, 'Sin cupo');
      return;
    }
    const ids = this.seleccionadas.map(s => s.idSolicitud);
    try {
      await this.transporteService.unirSolicitudes(ids, this.placaUnir);
      this.placaUnir = undefined;
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudieron unir las solicitudes', 'Error');
    }
  }

  // Separar una solicitud de su traslado (la devuelve a pendiente sin placa)
  async separar(s: Solicitud) {
    const ok = await this.alertService.confirm('Separar solicitud',
      `¿Quitar la solicitud de ${s.nombre} del traslado ${s.idTraslado}?`);
    if (!ok) return;

    try {
      await this.transporteService.separarSolicitud(s.idSolicitud);
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo separar la solicitud', 'Error');
    }
  }

  editarRuta(t: Traslado) {
    this.trasladoEditando = t;
    this.paradasEditando = t.paradas?.map(p => ({ ...p })) ?? [];
    if (!this.paradasEditando.length && t.solicitudes?.length) {
      this.paradasEditando = t.solicitudes.map(s => ({ punto: s.puntoPartida, cantidadSube: s.cantidad, cantidadBaja: 0 }));
      const ultima = t.solicitudes[t.solicitudes.length - 1];
      this.paradasEditando.push({ punto: ultima.puntoLlegada, cantidadSube: 0, cantidadBaja: t.solicitudes.reduce((a, s) => a + s.cantidad, 0) });
    }
  }

  agregarParada() {
    this.paradasEditando.push({ punto: '', cantidadSube: 0, cantidadBaja: 0 });
  }

  quitarParada(indice: number) {
    this.paradasEditando.splice(indice, 1);
  }

  moverParada(indice: number, direccion: -1 | 1) {
    const destino = indice + direccion;
    if (destino < 0 || destino >= this.paradasEditando.length) return;
    [this.paradasEditando[indice], this.paradasEditando[destino]] = [this.paradasEditando[destino], this.paradasEditando[indice]];
    // El orden visual manda: re-numerar para que el backend lo respete
    this.paradasEditando.forEach((p, i) => p.orden = i + 1);
  }

  puntosMapa(t: Traslado): PuntoMapa[] {
    const nombres = (t.paradas?.length ? t.paradas.map(p => p.punto)
      : (t.ruta ?? '').split('>').map(x => x.trim()))
      .filter(Boolean);
    return nombres
      .map(n => this.puntos.find(p => p.nombre === n))
      .filter(p => p?.latitud != null && p?.longitud != null)
      .map(p => ({ latitud: p!.latitud!, longitud: p!.longitud!, etiqueta: p!.nombre }));
  }

  verMapa(t: Traslado) {
    const puntos = this.puntosMapa(t);
    if (!puntos.length && t.ultimaLatitud == null) {
      this.alertService.showAlert('warning', 'La ruta no tiene puntos con coordenadas registradas', 'Atención');
      return;
    }
    if (this.trasladoMapa?.idTraslado === t.idTraslado) {
      this.mapaAbierto = false;
      return;
    }
    this.puntosMapaT = puntos;
    this.trasladoMapa = t;
    this.actualizarPosicionMapa();
    // Refrescar la posición de la unidad mientras el mapa está abierto
    if (this.timerMapa) clearInterval(this.timerMapa);
    this.timerMapa = setInterval(() => void this.refrescarPosicionMapa(), 30000);
  }

  // Marcador azul de la unidad: última posición GPS reportada por el conductor
  private actualizarPosicionMapa() {
    const t = this.trasladoMapa;
    this.origenMapaT = (t?.ultimaLatitud != null && t.ultimaLongitud != null)
      ? { latitud: t.ultimaLatitud, longitud: t.ultimaLongitud,
          etiqueta: `${t.placa} · GPS ${this.horaGps(t.ultimaUbicacionAt)}` }
      : undefined;
  }

  private async refrescarPosicionMapa() {
    const t = this.trasladoMapa;
    if (!t) return;
    try {
      const p = await this.transporteService.progresoTraslado(t.idTraslado);
      if (p) {
        t.ultimaLatitud = p.ultimaLatitud;
        t.ultimaLongitud = p.ultimaLongitud;
        t.ultimaUbicacionAt = p.ultimaUbicacionAt;
        this.actualizarPosicionMapa();
      }
    } catch { }
  }

  horaGps(fecha?: string | null): string {
    if (!fecha) return '—';
    return new Date(fecha).toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  verRutaMapa(t: Traslado) {
    const nombres = (t.paradas?.length ? t.paradas.map(p => p.punto)
      : [t.ruta ?? ''].flatMap(r => r.split('>').map(x => x.trim())))
      .filter(Boolean);
    const coords = nombres
      .map(n => this.puntos.find(p => p.nombre === n))
      .filter(p => p?.latitud != null && p?.longitud != null) as Punto[];
    if (coords.length < 2) {
      this.alertService.showAlert('warning', 'La ruta necesita al menos 2 puntos con coordenadas registradas', 'Atención');
      return;
    }
    const url = 'https://www.openstreetmap.org/directions?from=' +
      `${coords[0].latitud}%2C${coords[0].longitud}&to=` +
      `${coords[coords.length - 1].latitud}%2C${coords[coords.length - 1].longitud}` +
      (coords.length > 2
        ? '&via=' + coords.slice(1, -1).map(p => `${p.latitud}%2C${p.longitud}`).join('%3B')
        : '');
    window.open(url, '_blank');
  }

  async guardarRuta() {
    if (!this.trasladoEditando || this.paradasEditando.some(p => !p.punto)) return;
    try {
      // El SP usa el índice del array como orden; se envía además explícito
      const paradas = this.paradasEditando.map((p, i) => ({
        ...p,
        orden: i + 1,
        idPunto: p.idPunto ?? this.puntos.find(pt => pt.nombre === p.punto)?.idPunto ?? null
      }));
      await this.transporteService.guardarParadas(this.trasladoEditando.idTraslado, paradas);
      this.trasladoEditando = undefined;
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo guardar la ruta', 'Error');
    }
  }

  // Ruta sugerida: fusiona partidas/llegadas de las solicitudes del traslado
  // en una secuencia de paradas (cada punto aparece una vez, con sus totales).
  generarRutaSugerida() {
    const solicitudes = (this.trasladoEditando?.solicitudes ?? [])
      .filter(s => s.estado !== 'ANULADO')
      .sort((a, b) => (a.horaProgramada ?? '').localeCompare(b.horaProgramada ?? ''));
    if (!solicitudes.length) {
      this.alertService.showAlert('warning', 'Este traslado no tiene solicitudes para sugerir una ruta', 'Atención');
      return;
    }

    const paradas: Parada[] = [];
    const porPunto = new Map<string, Parada>();
    const tocar = (punto: string, sube: number, baja: number) => {
      let p = porPunto.get(punto);
      if (!p) {
        p = { punto, orden: paradas.length + 1, cantidadSube: 0, cantidadBaja: 0, detalle: [] };
        porPunto.set(punto, p);
        paradas.push(p);
      }
      p.cantidadSube += sube;
      p.cantidadBaja += baja;
    };
    for (const s of solicitudes) {
      tocar(s.puntoPartida, s.cantidad, 0);
      tocar(s.puntoLlegada, 0, s.cantidad);
      // Detalle parada ↔ solicitud: quién sube y quién baja en cada punto
      porPunto.get(s.puntoPartida)!.detalle!.push({ idSolicitud: s.idSolicitud, tipo: 'S', cantidadPlaneada: s.cantidad, nombre: s.nombre });
      porPunto.get(s.puntoLlegada)!.detalle!.push({ idSolicitud: s.idSolicitud, tipo: 'B', cantidadPlaneada: s.cantidad, nombre: s.nombre });
    }
    // Vincular al catálogo para que el mapa y el GPS funcionen
    for (const p of paradas) p.idPunto = this.puntos.find(pt => pt.nombre === p.punto)?.idPunto ?? null;
    this.paradasEditando = paradas;
    this.alertService.showAlert('success', `Ruta sugerida aplicada: ${paradas.length} parada(s)`, 'Ruta sugerida');
  }

  // ===== Seguimiento en vivo del traslado =====

  paradasOrdenadas(t?: Traslado): Parada[] {
    return [...(t?.paradas ?? [])].sort((a, b) => (a.orden ?? 0) - (b.orden ?? 0));
  }

  paradasProgreso(): Parada[] {
    return this.progreso?.paradas?.length
      ? [...this.progreso.paradas].sort((a, b) => (a.orden ?? 0) - (b.orden ?? 0))
      : this.paradasOrdenadas(this.trasladoProgreso);
  }

  // Resumen para la tarjeta del traslado: "2/5 paradas · 8 a bordo"
  resumenParadas(t: Traslado): string {
    const paradas = t.paradas ?? [];
    if (!paradas.length) return '';
    const hechas = paradas.filter(p => p.estado === 'REALIZADA' || p.estado === 'OMITIDA').length;
    const aBordo = paradas.reduce((a, p) =>
      a + (p.subieronReal ?? p.cantidadSube ?? 0) - (p.bajaronReal ?? p.cantidadBaja ?? 0), 0);
    return `${hechas}/${paradas.length} paradas · ${aBordo} a bordo`;
  }

  // A bordo al salir de la parada i (real si existe, planeado si no)
  aBordoTramo(paradas: Parada[], indice: number): number {
    return paradas.slice(0, indice + 1).reduce((a, p) =>
      a + (p.subieronReal ?? p.cantidadSube ?? 0) - (p.bajaronReal ?? p.cantidadBaja ?? 0), 0);
  }

  severidadParada(estado?: EstadoParada): 'success' | 'info' | 'warn' | 'danger' | 'secondary' {
    switch (estado ?? 'PENDIENTE') {
      case 'REALIZADA': return 'success';
      case 'EN_PARADA': return 'info';
      case 'OMITIDA': return 'danger';
      default: return 'warn';
    }
  }

  verProgreso(t: Traslado) {
    if (this.trasladoProgreso?.idTraslado === t.idTraslado) {
      this.cerrarProgreso();
      return;
    }
    this.trasladoProgreso = t;
    void this.refrescarProgreso();
    // Polling cada 30 s mientras la vista está abierta
    this.timerProgreso = setInterval(() => void this.refrescarProgreso(), 30000);
  }

  cerrarProgreso() {
    this.trasladoProgreso = undefined;
    this.progreso = undefined;
    if (this.timerProgreso) { clearInterval(this.timerProgreso); this.timerProgreso = undefined; }
  }

  // El endpoint traslados/progreso es el resumen liviano; si aún no existe en
  // el API, se recargan los traslados y se usa la data local del traslado.
  async refrescarProgreso() {
    const id = this.trasladoProgreso?.idTraslado;
    if (id == null) return;
    try {
      this.progreso = await this.transporteService.progresoTraslado(id);
    } catch {
      try {
        this.traslados = await this.transporteService.listarTraslados(this.fechaFiltro ? { fecha: this.fechaFiltro } : {});
        const actualizado = this.traslados.find(x => x.idTraslado === id);
        if (actualizado) this.trasladoProgreso = actualizado;
      } catch { }
      this.progreso = undefined;
    }
  }

  ngOnDestroy() {
    if (this.timerProgreso) clearInterval(this.timerProgreso);
    if (this.timerMapa) clearInterval(this.timerMapa);
  }

  abrirAsignacionMultiple(s: Solicitud) {
    this.solicitudMultiple = s;
    this.asignaciones = [{ placa: '', cantidad: s.cantidad }];
    this.mostrarMultiple = true;
  }

  cerrarMultiple() {
    this.mostrarMultiple = false;
    this.solicitudMultiple = undefined;
  }

  agregarUnidad() {
    this.asignaciones.push({ placa: '', cantidad: Math.max(1, this.restanteAsignacion()) });
  }

  quitarUnidad(indice: number) {
    this.asignaciones.splice(indice, 1);
  }

  totalAsignado(): number {
    return this.asignaciones.reduce((a, x) => a + (x.cantidad ?? 0), 0);
  }

  restanteAsignacion(): number {
    return (this.solicitudMultiple?.cantidad ?? 0) - this.totalAsignado();
  }

  cupoDePlaca(placa?: string): number {
    return this.cupoLibre(placa, this.solicitudMultiple?.fechaProgramada);
  }

  excedeCupo(a: AsignacionUnidad): boolean {
    return !!a.placa && a.cantidad > this.cupoDePlaca(a.placa);
  }

  unidadesOpcionesPara(actual: AsignacionUnidad) {
    const usadas = new Set(this.asignaciones.filter(x => x !== actual && x.placa).map(x => x.placa));
    return this.unidadesOpcionesFecha(this.solicitudMultiple?.fechaProgramada)
      .map(o => ({ ...o, sinCupo: o.sinCupo || usadas.has(o.placa) }));
  }

  alCambiarUnidad(a: AsignacionUnidad) {
    a.cantidad = Math.max(1, Math.min(a.cantidad ?? 1, this.cupoDePlaca(a.placa)));
  }

  get distribucionValida(): boolean {
    if (!this.solicitudMultiple) return false;
    return this.asignaciones.length > 0
      && this.asignaciones.every(a => !!a.placa && a.cantidad >= 1 && !this.excedeCupo(a))
      && this.totalAsignado() === this.solicitudMultiple.cantidad;
  }

  async guardarAsignacionMultiple() {
    if (!this.solicitudMultiple) return;
    if (!this.distribucionValida) {
      this.alertService.showAlert('warning', 'La suma debe ser igual al total y no exceder el cupo de cada unidad', 'Atención');
      return;
    }
    try {
      await this.transporteService.asignarMultiplesUnidades(this.solicitudMultiple.idSolicitud, this.asignaciones);
      this.cerrarMultiple();
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'La distribución no coincide con la cantidad o capacidad disponible', 'Error');
    }
  }

  esSeleccionable(s: Solicitud): boolean {
    return s.estado === 'PENDIENTE' && !s.realizado;
  }
}
