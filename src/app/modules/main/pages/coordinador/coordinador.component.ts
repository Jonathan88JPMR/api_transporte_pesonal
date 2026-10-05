import { Component, OnInit } from '@angular/core';
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
import { AsignacionUnidad, Motivo, Parada, Punto, Solicitud, Traslado, Unidad, Usuario } from '@/app/models/transporte.models';
import { MapaComponent, PuntoMapa } from '@/app/shared/mapa/mapa.component';

@Component({
  selector: 'app-coordinador',
  standalone: true,
  imports: [CommonModule, FormsModule, TableModule, SelectModule, ButtonModule, TagModule, CheckboxModule, TooltipModule, DialogModule, MapaComponent],
  templateUrl: './coordinador.component.html',
  styleUrl: './coordinador.component.scss'
})
export class CoordinadorComponent implements OnInit {

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
  trasladoEditando?: Traslado;
  trasladoMapa?: Traslado;
  puntosMapaT: PuntoMapa[] = [];
  paradasEditando: Parada[] = [];
  solicitudMultiple?: Solicitud;
  asignaciones: AsignacionUnidad[] = [];
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
        this.transporteService.listarTraslados()
      ]);
      this.seleccionadas = [];
    } catch {
      this.alertService.showAlert('error', 'No se pudieron cargar los datos', 'Error');
    } finally {
      this.cargando = false;
    }
  }

  async cargarUnidades() {
    try {
      this.unidades = await this.transporteService.listarUnidades();
    } catch { }
  }

  async cargarPuntos() {
    try {
      this.puntos = await this.transporteService.listarPuntos();
    } catch { this.puntos = []; }
  }

  // RF-012: opciones del select con cupo visible; sin cupo quedan deshabilitadas
  get unidadesOpciones() {
    return this.unidades.map(u => ({
      ...u,
      etiqueta: `${u.placa} · ${u.cupoDisponible ?? u.capacidad}/${u.capacidad} libres`,
      sinCupo: (u.cupoDisponible ?? u.capacidad) <= 0
    }));
  }

  cupoUnidad(u: Unidad): number { return u.cupoDisponible ?? u.capacidad; }

  claseUnidad(u: Unidad): string {
    const libre = this.cupoUnidad(u);
    if (libre <= 0) return 'bg-danger';
    if (!u.disponible || libre < u.capacidad) return 'bg-warning text-dark';
    return 'bg-success';
  }

  capacidadDe(placa?: string | null): number {
    return this.unidades.find(u => u.placa === placa)?.capacidad ?? 0;
  }

  ocupacionTraslado(t: Traslado): number {
    return (t.solicitudes ?? []).reduce((a, s) => a + (s.cantidad ?? 0), 0);
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
    const unidad = this.unidades.find(u => u.placa === placa);
    if (!unidad || s.cantidad > this.cupoUnidad(unidad)) {
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
    const candidata = this.unidades.find(u => this.cupoUnidad(u) >= s.cantidad);
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

  // Unir las solicitudes seleccionadas en un solo traslado con una placa
  async unir() {
    if (this.seleccionadas.length < 2) {
      this.alertService.showAlert('warning', 'Seleccione al menos 2 solicitudes para unir', 'Atención');
      return;
    }
    if (!this.placaUnir) {
      this.alertService.showAlert('warning', 'Seleccione la placa del traslado', 'Atención');
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
    if (puntos.length < 1) {
      this.alertService.showAlert('warning', 'La ruta no tiene puntos con coordenadas registradas', 'Atención');
      return;
    }
    if (this.trasladoMapa?.idTraslado === t.idTraslado) {
      this.trasladoMapa = undefined;
      this.puntosMapaT = [];
      return;
    }
    this.puntosMapaT = puntos;
    this.trasladoMapa = t;
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
      await this.transporteService.guardarParadas(this.trasladoEditando.idTraslado, this.paradasEditando);
      this.trasladoEditando = undefined;
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo guardar la ruta', 'Error');
    }
  }

  abrirAsignacionMultiple(s: Solicitud) {
    this.solicitudMultiple = s;
    this.asignaciones = [{ placa: '', cantidad: s.cantidad }];
  }

  agregarUnidad() {
    this.asignaciones.push({ placa: '', cantidad: 1 });
  }

  async guardarAsignacionMultiple() {
    if (!this.solicitudMultiple || this.asignaciones.some(a => !a.placa || a.cantidad < 1)) return;
    try {
      await this.transporteService.asignarMultiplesUnidades(this.solicitudMultiple.idSolicitud, this.asignaciones);
      this.solicitudMultiple = undefined;
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'La distribución no coincide con la cantidad o capacidad disponible', 'Error');
    }
  }

  esSeleccionable(s: Solicitud): boolean {
    return !s.realizado && s.estado !== 'ANULADO';
  }
}
