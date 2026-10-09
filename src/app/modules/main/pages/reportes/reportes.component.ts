import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TableModule } from 'primeng/table';
import { TagModule } from 'primeng/tag';
import { ButtonModule } from 'primeng/button';
import { TransporteService } from '../../services/transporte.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';
import { Auditoria, IndicadoresReporte, Solicitud, Unidad } from '@/app/models/transporte.models';

@Component({
  selector: 'app-reportes',
  standalone: true,
  imports: [CommonModule, FormsModule, TableModule, TagModule, ButtonModule],
  templateUrl: './reportes.component.html',
  styleUrl: './reportes.component.scss'
})
export class ReportesComponent implements OnInit {

  registros: Solicitud[] = [];
  indicadores?: IndicadoresReporte;
  auditoria: Auditoria[] = [];
  unidadesCatalogo: Unidad[] = [];
  porciones: Record<number, { placa: string; cantidad: number; estado: string }[]> = {};
  desde?: string;
  hasta?: string;
  cargando = false;

  filtroSupervisor = '';
  filtroPlaca = '';
  filtroEstado = '';
  estados = ['PENDIENTE', 'ASIGNADO', 'EN_RUTA', 'REALIZADO', 'ANULADO'];

  constructor(
    private transporteService: TransporteService,
    private alertService: AlertService
  ) { }

  async ngOnInit() {
    const hoy = new Date();
    const inicioMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
    this.desde = this.toIso(inicioMes);
    this.hasta = this.toIso(hoy);
    await this.cargar();
  }

  async cargar() {
    this.cargando = true;
    try {
      if (!this.unidadesCatalogo.length) {
        this.unidadesCatalogo = await this.transporteService.listarUnidades();
      }
      [this.registros, this.indicadores] = await Promise.all([
        this.transporteService.reporteSolicitudes(this.desde, this.hasta),
        this.transporteService.reporteIndicadores(this.desde, this.hasta)
      ]);
      void this.cargarPorciones();
    } catch {
      this.alertService.showAlert('error', 'No se pudo generar el reporte', 'Error');
    } finally {
      this.cargando = false;
    }
  }

  get totalPersonas(): number {
    return this.registrosFiltrados.reduce((acc, r) => acc + (r.cantidad ?? 0), 0);
  }

  get totalRealizados(): number {
    return this.registrosFiltrados.filter(r => r.realizado).length;
  }

  // RF-031: filtros por supervisor, placa y estado sobre el rango de fechas
  get supervisores(): string[] {
    return [...new Set(this.registros.map(r => r.usuarioRegistra).filter((x): x is string => !!x))].sort();
  }

  async cargarPorciones() {
    const mapa: Record<number, { placa: string; cantidad: number; estado: string }[]> = {};
    for (const { placa, servicios } of await this.transporteService.serviciosPorPlacas(this.unidadesCatalogo.map(u => u.placa))) {
      for (const s of servicios) {
        if (s.idSolicitudUnidad != null) {
          (mapa[s.idSolicitud] ??= []).push({ placa, cantidad: s.cantidad, estado: s.estado });
        }
      }
    }
    this.porciones = mapa;
  }

  placasDe(r: Solicitud): string[] {
    return this.porciones[r.idSolicitud]?.map(p => p.placa) ?? [];
  }

  placaTexto(r: Solicitud): string {
    if (r.placa !== 'MULTIPLE') return r.placa ?? '';
    const partes = this.placasDe(r);
    return partes.length ? `MULTIPLE · ${partes.join(' · ')}` : 'MULTIPLE';
  }

  get placas(): string[] {
    return [...new Set(this.registros.map(r => r.placa).filter((x): x is string => !!x))].sort();
  }

  get registrosFiltrados(): Solicitud[] {
    return this.registros.filter(r =>
      (!this.filtroSupervisor || r.usuarioRegistra === this.filtroSupervisor) &&
      (!this.filtroPlaca || r.placa === this.filtroPlaca || this.placasDe(r).includes(this.filtroPlaca)) &&
      (!this.filtroEstado || r.estado === this.filtroEstado));
  }

  get unidades() { return this.indicadores?.unidades ?? []; }
  get conductores() { return this.indicadores?.conductores ?? []; }
  get areas() { return this.indicadores?.areas ?? []; }

  async cargarAuditoria() {
    try { this.auditoria = await this.transporteService.listarAuditoria(); }
    catch { this.alertService.showAlert('error', 'No se pudo cargar la auditoría', 'Error'); }
  }

  imprimirPdf(): void { window.print(); }

  exportarCsv(): void {
    const columnas = ['Fecha', 'Solicitante', 'Área', 'Hora', 'Origen', 'Destino', 'Cantidad', 'Motivo', 'Prioridad', 'Placa', 'Estado'];
    const filas = this.registrosFiltrados.map(r => [r.fechaProgramada, r.nombre, r.area ?? '', r.horaProgramada,
      r.puntoPartida, r.puntoLlegada, r.cantidad, r.motivo ?? '', r.prioridad ?? (r.esEmergencia ? 'EMERGENCIA' : 'NORMAL'), this.placaTexto(r), r.estado]);
    const csv = [columnas, ...filas].map(f => f.map(v => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\n');
    const enlace = document.createElement('a');
    enlace.href = URL.createObjectURL(new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8' }));
    enlace.download = `reporte-transporte-${this.desde}-${this.hasta}.csv`;
    enlace.click();
    URL.revokeObjectURL(enlace.href);
  }

  private toIso(d: Date): string {
    const p = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  }
}
