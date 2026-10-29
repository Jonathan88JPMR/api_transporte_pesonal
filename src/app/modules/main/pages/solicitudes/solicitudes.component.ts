import { Component, OnDestroy, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AbstractControl, FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, ValidationErrors, ValidatorFn, Validators } from '@angular/forms';
import { TableModule } from 'primeng/table';
import { DialogModule } from 'primeng/dialog';
import { SelectModule } from 'primeng/select';
import { InputNumberModule } from 'primeng/inputnumber';
import { ButtonModule } from 'primeng/button';
import { TagModule } from 'primeng/tag';
import { TooltipModule } from 'primeng/tooltip';
import { TransporteService } from '../../services/transporte.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';
import { AuthService } from '@/app/modules/auth/services/auth.service';
import { EstadoParada, Motivo, Parada, Punto, Solicitud, Traslado, Unidad, Usuario } from '@/app/models/transporte.models';
// MapaComponent se reimporta cuando se reactive el diálogo de mapa (oculto en el HTML)
//import { MapaComponent, PuntoMapa } from '@/app/shared/mapa/mapa.component';
import { PuntoMapa } from '@/app/shared/mapa/mapa.component';
import { ComunicadoModalComponent } from '@/app/shared/comunicado-modal/comunicado-modal.component';

@Component({
  selector: 'app-solicitudes',
  standalone: true,
  imports: [
    CommonModule, ReactiveFormsModule, FormsModule,
    TableModule, DialogModule, SelectModule, InputNumberModule, ButtonModule, TagModule, TooltipModule,
    //MapaComponent, ComunicadoModalComponent
    ComunicadoModalComponent
  ],
  templateUrl: './solicitudes.component.html',
  styleUrl: './solicitudes.component.scss'
})
export class SolicitudesComponent implements OnInit, OnDestroy {

  solicitudes: Solicitud[] = [];
  puntos: Punto[] = [];
  motivos: Motivo[] = [];
  traslados: Traslado[] = [];
  unidades: Unidad[] = [];
  porciones: Record<number, { placa: string; cantidad: number; estado: string }[]> = {};
  usuario?: Usuario;
  filtroDesde = '';
  filtroHasta = '';
  // Comunicados vigentes/próximos del coordinador ("horas sin servicio"):
  // si hay uno vigente ahora, no se pueden crear solicitudes (emergencia sí pasa)
  comunicados: any[] = [];
  // Modal rojo de alerta: se abre solo al entrar si hay un comunicado vigente
  mostrarComunicado = false;

  cargando = false;
  mostrarDialogo = false;
  mostrarDetalle = false;
  detalle?: Solicitud;
  editando?: Solicitud;

  // Vista móvil (<768px): sin filtros de fecha, solo los servicios de hoy
  private mediaQuery = window.matchMedia('(max-width: 767.98px)');
  esMovil = this.mediaQuery.matches;
  private alCambiarMedia = (e: MediaQueryListEvent) => {
    this.esMovil = e.matches;
    if (e.matches) void this.cargar();
  };

  form: FormGroup;

  constructor(
    private fb: FormBuilder,
    private transporteService: TransporteService,
    private alertService: AlertService,
    private authService: AuthService
  ) {
    this.form = this.fb.group({
      fechaProgramada: [this.fechaHoy(), Validators.required],
      horaProgramada: ['', Validators.required],
      horaRequerida: ['', Validators.required],
      puntoPartida: [null, Validators.required],
      puntoLlegada: [null, Validators.required],
      cantidad: [1, [Validators.required, Validators.min(1)]],
      motivo: [null, Validators.required],
      observacion: [''],
      prioridad: ['NORMAL'],
      esEmergencia: [false]
    }, { validators: this.horaRequeridaValida });
  }

  async ngOnInit() {
    this.mediaQuery.addEventListener('change', this.alCambiarMedia);
    this.usuario = await this.authService.getUser();
    await Promise.all([this.cargar(), this.cargarCatalogos(), this.cargarTraslados(), this.cargarComunicados()]);
    // La alerta de entrada la muestra el layout (modal bloqueante global);
    // aquí el modal solo reaparece si intenta crear/editar durante el bloqueo
  }

  // Comunicados publicados por el coordinador (todos los roles los ven)
  async cargarComunicados() {
    try { this.comunicados = await this.transporteService.comunicadosActivos(); } catch { this.comunicados = []; }
  }

  // El primero que está vigente en este momento → bloquea la creación
  get comunicadoVigente(): any | undefined {
    return this.comunicados.find(c => c.vigente === 1 || c.vigente === true);
  }

  // Guardar solo se habilita dentro del bloqueo si es emergencia médica
  get bloqueadoPorComunicado(): boolean {
    return !!this.comunicadoVigente && this.form.get('esEmergencia')?.value !== true;
  }

  async cargar() {
    this.cargando = true;
    try {
      // Todos los supervisores ven las solicitudes de todas las áreas;
      // la gestión (editar/anular/acoplar) sigue restringida a las propias
      const todas = await this.transporteService.listarSolicitudes({ usuario: this.usuario?.usuario });
      let { filtroDesde: desde, filtroHasta: hasta } = this;
      // En móvil los filtros de fecha no existen: siempre se muestra solo hoy
      if (this.esMovil) desde = hasta = this.fechaHoy();
      else if (desde && hasta && desde > hasta) [desde, hasta] = [hasta, desde];
      this.solicitudes = todas.filter(s => {
        const f = s.fechaProgramada?.slice(0, 10) ?? '';
        return (!desde || f >= desde) && (!hasta || f <= hasta);
      });
      // refresca el cupo del panel de unidades (por si el coordinador asignó)
      if (this.unidades.length) void this.cargarPorciones();
    } catch {
      this.alertService.showAlert('error', 'No se pudieron cargar las solicitudes', 'Error');
    } finally {
      this.cargando = false;
    }
  }

  limpiarFiltro() {
    this.filtroDesde = '';
    this.filtroHasta = '';
    void this.cargar();
  }

  async cargarCatalogos() {
    try {
      [this.puntos, this.motivos, this.unidades] = await Promise.all([
        this.transporteService.listarPuntos(),
        this.transporteService.listarMotivos(),
        this.transporteService.listarUnidades()
      ]);
      void this.cargarPorciones();
    } catch {
      // catálogos no críticos para listar
    }
  }

  // Porciones de solicitudes repartidas en varias unidades (idSolicitudUnidad)
  // + ocupación real de hoy por placa (ASIGNADO/EN_RUTA) para el panel de
  // unidades disponibles
  ocupaciones: Record<string, number> = {};

  async cargarPorciones() {
    const mapa: Record<number, { placa: string; cantidad: number; estado: string }[]> = {};
    const ocup: Record<string, number> = {};
    const hoy = this.fechaHoy();
    for (const { placa, servicios } of await this.transporteService.serviciosPorPlacas(this.unidades.map(u => u.placa))) {
      for (const s of servicios) {
        if ((s.estado === 'ASIGNADO' || s.estado === 'EN_RUTA') && (s.fechaProgramada ?? '').slice(0, 10) === hoy) {
          ocup[placa] = (ocup[placa] ?? 0) + (s.cantidad ?? 0);
        }
        if (s.idSolicitudUnidad != null) {
          (mapa[s.idSolicitud] ??= []).push({ placa, cantidad: s.cantidad, estado: s.estado });
        }
      }
    }
    this.porciones = mapa;
    this.ocupaciones = ocup;
  }

  // Cupo libre de hoy = capacidad - personas con servicios ASIGNADO/EN_RUTA
  cupoLibre(placa?: string | null): number {
    const u = this.unidades.find(x => x.placa === placa);
    return u ? Math.max(u.capacidad - (this.ocupaciones[u.placa] ?? 0), 0) : 0;
  }

  // Verde libre / ámbar parcial / rojo sin cupo (mismo criterio que Coordinación)
  claseUnidad(u: Unidad): string {
    const libre = this.cupoLibre(u.placa);
    if (libre <= 0) return 'bg-danger';
    if (libre < u.capacidad) return 'bg-warning text-dark';
    return 'bg-success';
  }

  // Las solicitudes de otras áreas son de solo lectura: Editar/Anular/Acoplar
  // solo aparece en las propias (el SP de acoplar además lo valida por área)
  esPropia(s?: Solicitud): boolean {
    if (!s || !this.usuario) return false;
    if (this.usuario.idrol === 'ADTRANS') return true;
    if (this.usuario.idArea != null)
      return s.idArea === this.usuario.idArea || (s.idArea == null && s.area === this.usuario.area);
    return s.usuarioRegistra === this.usuario.usuario;
  }

  placaTexto(s: Solicitud): string {
    if (s.placa !== 'MULTIPLE') return s.placa ?? '';
    const partes = this.porciones[s.idSolicitud]?.map(p => `${p.placa} (${p.cantidad})`);
    return partes?.length ? `MULTIPLE · ${partes.join(' · ')}` : 'MULTIPLE';
  }

  async cargarTraslados() {
    try {
      this.traslados = await this.transporteService.listarTraslados();
    } catch {
      this.traslados = [];
    }
  }

  async acoplar(t: Traslado) {
    if (!this.detalle) return;
    try {
      await this.transporteService.acoplarSolicitud(this.detalle.idSolicitud, t.idTraslado, this.usuario?.usuario);
      this.mostrarDetalle = false;
      await Promise.all([this.cargar(), this.cargarTraslados()]);
    } catch {
      this.alertService.showAlert('warning', 'El traslado no tiene cupo o ya no está disponible', 'No se pudo acoplar');
    }
  }

  async crear() {
    // Si hay un comunicado vigente, Crear no abre el formulario: vuelve al
    // modal bloqueante. La única salida es "Es emergencia médica".
    await this.cargarComunicados();
    if (this.comunicadoVigente) { this.mostrarComunicado = true; return; }
    this.editando = undefined;
    // Fecha y hora siempre del sistema — el backend además las fuerza a GETDATE()
    this.form.reset({
      fechaProgramada: this.fechaHoy(), horaProgramada: this.horaAhora(), horaRequerida: this.horaAhora(),
      cantidad: 1, observacion: '', prioridad: 'NORMAL', esEmergencia: false
    });
    this.form.get('prioridad')?.enable({ emitEvent: false });
    this.mostrarDialogo = true;
  }

  // Botón del modal de comunicado: la única solicitud permitida durante el
  // bloqueo es una emergencia médica (el SP también la deja pasar)
  crearEmergencia() {
    this.mostrarComunicado = false;
    this.editando = undefined;
    this.form.reset({
      fechaProgramada: this.fechaHoy(), horaProgramada: this.horaAhora(), horaRequerida: this.horaAhora(),
      cantidad: 1, observacion: '', prioridad: 'EMERGENCIA', esEmergencia: true
    });
    this.alCambiarEmergencia(true);
    this.mostrarDialogo = true;
  }

  async editar(s: Solicitud) {
    // Editar también está bloqueado en el rango sin servicio (salvo que la
    // propia solicitud ya sea una emergencia)
    await this.cargarComunicados();
    if (this.comunicadoVigente && !s.esEmergencia) { this.mostrarComunicado = true; return; }
    this.editando = s;
    this.form.reset({
      fechaProgramada: s.fechaProgramada,
      horaProgramada: s.horaProgramada,
      horaRequerida: s.horaRequerida ?? s.horaProgramada,
      puntoPartida: s.puntoPartida,
      puntoLlegada: s.puntoLlegada,
      cantidad: s.cantidad,
      motivo: s.motivo,
      observacion: s.observacion,
      prioridad: s.prioridad ?? 'NORMAL',
      esEmergencia: s.esEmergencia
    });
    if (s.esEmergencia) this.form.get('prioridad')?.disable({ emitEvent: false });
    else this.form.get('prioridad')?.enable({ emitEvent: false });
    this.mostrarDialogo = true;
  }

  // Emergencia médica: aplica EMERGENCIA + 1 persona + motivo Salud +
  // destino Tópico por defecto (cantidad/motivo/destino quedan editables)
  alCambiarEmergencia(marcado: boolean) {
    if (marcado) {
      const salud = this.motivos.find(m => m.nombre?.toUpperCase().includes('SALUD'))?.nombre;
      const topico = this.puntos.find(p => p.nombre?.toUpperCase().includes('TOPICO'))?.nombre;
      this.form.patchValue({
        prioridad: 'EMERGENCIA',
        cantidad: 1,
        ...(salud ? { motivo: salud } : {}),
        ...(topico ? { puntoLlegada: topico } : {})
      });
      this.form.get('prioridad')?.disable({ emitEvent: false });
    } else {
      this.form.patchValue({ prioridad: 'NORMAL' });
      this.form.get('prioridad')?.enable({ emitEvent: false });
    }
  }

  verDetalle(s: Solicitud) {
    this.detalle = s;
    this.mostrarDetalle = true;
    void this.cargarTraslados(); // refrescar el estado de las paradas al abrir
    this.iniciarPolling();
  }

  // ===== Seguimiento GPS (solo lectura, para el supervisor) =====

  trasladoMapa?: Traslado;
  puntosMapaT: PuntoMapa[] = [];
  origenMapaT?: PuntoMapa;
  private timerSeguimiento?: ReturnType<typeof setInterval>;

  get mapaAbierto(): boolean { return !!this.trasladoMapa; }
  set mapaAbierto(v: boolean) {
    if (!v) {
      this.trasladoMapa = undefined;
      this.puntosMapaT = [];
      this.origenMapaT = undefined;
      this.detenerPollingSiCerrado();
    }
  }

  horaGps(fecha?: string | null): string {
    if (!fecha) return '—';
    return new Date(fecha).toLocaleTimeString('es-PE', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  // Distancia aproximada entre la última posición GPS de la unidad y la
  // próxima parada pendiente — respuesta rápida a "¿ya está cerca?"
  distanciaParada(t: Traslado): string {
    if (t.ultimaLatitud == null || t.ultimaLongitud == null) return '';
    const prox = this.paradasDe(t).find(p => (p.estado ?? 'PENDIENTE') === 'PENDIENTE' || p.estado === 'EN_PARADA');
    const punto = prox && this.puntos.find(x => x.idPunto === prox.idPunto || x.nombre === prox.punto);
    if (!punto?.latitud || !punto.longitud || !prox) return '';
    const km = this.haversine(t.ultimaLatitud, t.ultimaLongitud, punto.latitud, punto.longitud);
    return km < 1
      ? `a ~${Math.round(km * 1000)} m de ${punto.nombre}`
      : `a ~${km.toFixed(1)} km de ${punto.nombre}`;
  }

  private haversine(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const rad = (x: number) => x * Math.PI / 180;
    const dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
    const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
    return 2 * 6371 * Math.asin(Math.sqrt(a));
  }

  // Mapa de la ruta con la posición real de la unidad (punto azul)
  verMapaTraslado(t: Traslado) {
    this.trasladoMapa = t;
    this.puntosMapaT = this.paradasDe(t)
      .map(p => this.puntos.find(pt => pt.idPunto === p.idPunto || pt.nombre === p.punto))
      .filter(pt => pt?.latitud != null && pt.longitud != null)
      .map(pt => ({ latitud: pt!.latitud!, longitud: pt!.longitud!, etiqueta: pt!.nombre }));
    this.configurarOrigenMapa(t);
    if (!this.puntosMapaT.length && !this.origenMapaT) {
      this.trasladoMapa = undefined;
      this.alertService.showAlert('warning', 'No hay coordenadas de la ruta ni señal GPS todavía', 'Atención');
      return;
    }
    this.iniciarPolling();
  }

  private configurarOrigenMapa(t: Traslado) {
    this.origenMapaT = t.ultimaLatitud != null && t.ultimaLongitud != null
      ? { latitud: t.ultimaLatitud, longitud: t.ultimaLongitud,
          etiqueta: `${t.placa} · GPS ${this.horaGps(t.ultimaUbicacionAt)}` }
      : undefined;
  }

  // Mientras el detalle o el mapa están abiertos, las paradas y el GPS se
  // refrescan cada 30 s — seguimiento en vivo sin recargar la página
  private iniciarPolling() {
    if (this.timerSeguimiento) return;
    this.timerSeguimiento = setInterval(() => void this.refrescarSeguimiento(), 30000);
  }

  private async refrescarSeguimiento() {
    await this.cargarTraslados();
    const id = this.trasladoMapa?.idTraslado;
    if (id != null) {
      const t = this.traslados.find(x => x.idTraslado === id);
      if (t) { this.trasladoMapa = t; this.configurarOrigenMapa(t); }
    }
  }

  detenerPollingSiCerrado() {
    if (!this.mostrarDetalle && !this.trasladoMapa && this.timerSeguimiento) {
      clearInterval(this.timerSeguimiento);
      this.timerSeguimiento = undefined;
    }
  }

  ngOnDestroy() {
    if (this.timerSeguimiento) clearInterval(this.timerSeguimiento);
    this.mediaQuery.removeEventListener('change', this.alCambiarMedia);
  }

  async guardar() {
    if (!this.form.valid) return;

    const payload: Partial<Solicitud> = {
      ...this.form.value,
      nombre: this.usuario?.nombre ?? this.usuario?.usuario,
      area: this.usuario?.area,
      usuarioRegistra: this.usuario?.usuario
    };
    if (this.editando) {
      payload.idSolicitud = this.editando.idSolicitud;
    }

    try {
      await this.transporteService.guardarSolicitud(payload);
      this.mostrarDialogo = false;
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo guardar la solicitud', 'Error');
    }
  }

  private fechaHoy(): string {
    const d = new Date();
    const p = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  }

  private horaAhora(): string {
    const d = new Date();
    const p = (n: number) => String(n).padStart(2, '0');
    return `${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  // La hora requerida no puede ser anterior al momento de digitar
  // (las emergencias medicas se atienden de inmediato y la saltan)
  private horaRequeridaValida: ValidatorFn = (group: AbstractControl): ValidationErrors | null => {
    const req = group.get('horaRequerida')?.value;
    if (!req || group.get('esEmergencia')?.value === true) return null;
    return req >= this.horaAhora() ? null : { horaPasada: true };
  };

  // Traslados de la solicitud: el directo (simple/unida) mas el de cada
  // porcion cuando esta repartida en varias unidades (MULTIPLE)
  trasladosDe(s?: Solicitud): Traslado[] {
    const ids = new Set<number>();
    if (s?.idTraslado) ids.add(s.idTraslado);
    for (const p of s?.porciones ?? []) if (p.idTraslado) ids.add(p.idTraslado);
    return this.traslados.filter(t => ids.has(t.idTraslado));
  }

  trasladoDe(s?: Solicitud): Traslado | undefined {
    return this.trasladosDe(s)[0];
  }

  // Paradas del traslado, en orden de recorrido (solo lectura)
  paradasDe(t?: Traslado): Parada[] {
    return [...(t?.paradas ?? [])].sort((a, b) => (a.orden ?? 0) - (b.orden ?? 0));
  }

  severidadParada(estado?: EstadoParada): 'success' | 'info' | 'warn' | 'danger' | 'secondary' {
    switch (estado ?? 'PENDIENTE') {
      case 'REALIZADA': return 'success';
      case 'EN_PARADA': return 'info';
      case 'OMITIDA': return 'danger';
      default: return 'warn';
    }
  }

  cupoDe(s: Solicitud): { ocupada: number; capacidad: number } | null {
    const t = this.trasladoDe(s);
    if (t) {
      const unidad = this.unidades.find(u => u.placa === t.placa);
      const ocupada = (t.solicitudes ?? []).filter(x => x.estado !== 'ANULADO').reduce((a, x) => a + (x.cantidad ?? 0), 0);
      return unidad ? { ocupada, capacidad: unidad.capacidad } : null;
    }
    if (s.placa && s.placa !== 'MULTIPLE') {
      const unidad = this.unidades.find(u => u.placa === s.placa);
      return unidad ? { ocupada: s.cantidad, capacidad: unidad.capacidad } : null;
    }
    return null;
  }

  severidadCupo(s: Solicitud): 'success' | 'warn' | 'danger' {
    const c = this.cupoDe(s);
    if (!c) return 'success';
    const libre = c.capacidad - c.ocupada;
    return libre <= 0 ? 'danger' : libre <= c.capacidad * 0.25 ? 'warn' : 'success';
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

  async anular(s: Solicitud) {
    const ok = await this.alertService.confirm('Anular solicitud', `¿Anular la solicitud de ${s.nombre}?`);
    if (!ok) return;

    try {
      await this.transporteService.eliminarSolicitud(s.idSolicitud);
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo anular la solicitud', 'Error');
    }
  }
}
