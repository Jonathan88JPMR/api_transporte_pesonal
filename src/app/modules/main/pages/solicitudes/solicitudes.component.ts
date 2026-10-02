import { Component, OnInit } from '@angular/core';
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
import { Motivo, Punto, Solicitud, Traslado, Unidad, Usuario } from '@/app/models/transporte.models';

@Component({
  selector: 'app-solicitudes',
  standalone: true,
  imports: [
    CommonModule, ReactiveFormsModule, FormsModule,
    TableModule, DialogModule, SelectModule, InputNumberModule, ButtonModule, TagModule, TooltipModule
  ],
  templateUrl: './solicitudes.component.html',
  styleUrl: './solicitudes.component.scss'
})
export class SolicitudesComponent implements OnInit {

  solicitudes: Solicitud[] = [];
  puntos: Punto[] = [];
  motivos: Motivo[] = [];
  traslados: Traslado[] = [];
  unidades: Unidad[] = [];
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
      const todas = await this.transporteService.listarSolicitudes({});
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
    } catch {
      // catálogos no críticos para listar
    }
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
    this.form.reset({ fechaProgramada: this.fechaHoy(), cantidad: 1, observacion: '', esEmergencia: false });
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
      esEmergencia: s.esEmergencia
    });
    this.mostrarDialogo = true;
  }

  verDetalle(s: Solicitud) {
    this.detalle = s;
    this.mostrarDetalle = true;
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
    return new Date().toISOString().slice(0, 10);
  }

  trasladoDe(s?: Solicitud): Traslado | undefined {
    return this.traslados.find(t => t.idTraslado === s?.idTraslado);
  }

  cupoDe(s: Solicitud): { ocupada: number; capacidad: number } | null {
    const t = this.trasladoDe(s);
    if (t) {
      const unidad = this.unidades.find(u => u.placa === t.placa);
      const ocupada = (t.solicitudes ?? []).reduce((a, x) => a + (x.cantidad ?? 0), 0);
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
