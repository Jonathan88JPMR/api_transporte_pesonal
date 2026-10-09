import { Component, OnDestroy, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormBuilder, FormGroup, FormsModule, ReactiveFormsModule, Validators } from '@angular/forms';
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
import { MapaComponent, PuntoMapa } from '@/app/shared/mapa/mapa.component';

@Component({
  selector: 'app-solicitudes',
  standalone: true,
  imports: [
    CommonModule, ReactiveFormsModule, FormsModule,
    TableModule, DialogModule, SelectModule, InputNumberModule, ButtonModule, TagModule, TooltipModule,
    MapaComponent
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

  cargando = false;
  mostrarDialogo = false;
  mostrarDetalle = false;
  detalle?: Solicitud;
  editando?: Solicitud;

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
      puntoPartida: [null, Validators.required],
      puntoLlegada: [null, Validators.required],
      cantidad: [1, [Validators.required, Validators.min(1)]],
      motivo: [null, Validators.required],
      observacion: [''],
      prioridad: ['NORMAL'],
      esEmergencia: [false]
    });
  }

  async ngOnInit() {
    this.usuario = await this.authService.getUser();
    await Promise.all([this.cargar(), this.cargarCatalogos(), this.cargarTraslados()]);
  }

  async cargar() {
    this.cargando = true;
    try {
      // El backend filtra por área cuando quien consulta es supervisor (SPTRANS)
      const todas = await this.transporteService.listarSolicitudes({ usuario: this.usuario?.usuario });
      let { filtroDesde: desde, filtroHasta: hasta } = this;
      if (desde && hasta && desde > hasta) [desde, hasta] = [hasta, desde];
      this.solicitudes = todas.filter(s => {
        const f = s.fechaProgramada?.slice(0, 10) ?? '';
        return (!desde || f >= desde) && (!hasta || f <= hasta);
      });
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
  async cargarPorciones() {
    const mapa: Record<number, { placa: string; cantidad: number; estado: string }[]> = {};
    for (const { placa, servicios } of await this.transporteService.serviciosPorPlacas(this.unidades.map(u => u.placa))) {
      for (const s of servicios) {
        if (s.idSolicitudUnidad != null) {
          (mapa[s.idSolicitud] ??= []).push({ placa, cantidad: s.cantidad, estado: s.estado });
        }
      }
    }
    this.porciones = mapa;
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

  crear() {
    this.editando = undefined;
    // Fecha y hora siempre del sistema — el backend además las fuerza a GETDATE()
    this.form.reset({
      fechaProgramada: this.fechaHoy(), horaProgramada: this.horaAhora(),
      cantidad: 1, observacion: '', prioridad: 'NORMAL', esEmergencia: false
    });
    this.form.get('prioridad')?.enable({ emitEvent: false });
    this.mostrarDialogo = true;
  }

  editar(s: Solicitud) {
    this.editando = s;
    this.form.reset({
      fechaProgramada: s.fechaProgramada,
      horaProgramada: s.horaProgramada,
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
