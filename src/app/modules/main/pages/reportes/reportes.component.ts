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

  // Excel con el formato del reporte de movilidad (MES, SEMANA, DIA, ... INTERVALO)
  // exceljs/file-saver se cargan bajo demanda para no inflar el bundle inicial
  async exportarExcel(): Promise<void> {
    if (!this.registrosFiltrados.length) return;
    const ExcelJS = await import('exceljs');
    const { saveAs } = await import('file-saver');
    const MESES = ['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
    const DIAS = ['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'];
    const hhmm = (iso?: string | null) => iso ? iso.substring(11, 16) : '';
    const fechaProg = (r: Solicitud) => r.fechaProgramada ? new Date(r.fechaProgramada + 'T00:00:00') : null;
    // Número de semana ISO del año
    const semana = (f: Date) => {
      const d = new Date(Date.UTC(f.getFullYear(), f.getMonth(), f.getDate()));
      d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
      return 'SEM-' + String(Math.ceil((((d.getTime() - Date.UTC(d.getUTCFullYear(), 0, 1)) / 86400000) + 1) / 7)).padStart(2, '0');
    };
    // Minutos entre lo programado y el inicio real del servicio
    const demora = (r: Solicitud) => {
      const f = fechaProg(r);
      if (!f || !r.fechaInicio || !r.horaProgramada) return '';
      const [h, m] = r.horaProgramada.split(':').map(Number);
      const prog = new Date(f); prog.setHours(h, m, 0, 0);
      return Math.round((new Date(r.fechaInicio).getTime() - prog.getTime()) / 60000) + ' min';
    };
    const intervalo = (r: Solicitud) =>
      r.fechaInicio && r.fechaFin ? `${hhmm(r.fechaInicio)} - ${hhmm(r.fechaFin)}` : '';

    const wb = new ExcelJS.Workbook();
    const ws = wb.addWorksheet('Movilidad');
    const columnas = ['MES', 'SEMANA', 'DIA', 'NOMBRE', 'H.PROGRAMADA', 'AREA', 'PTO. PARTIDA',
      'PTO. LLEGADA', 'CANTIDAD', 'MOTIVO', 'PLACA', 'REALIZADO', 'DEMORA', 'APOYO/HR', 'INTERVALO'];
    const header = ws.addRow(columnas);
    header.height = 20;
    const borde = {
      top: { style: 'thin' as const }, left: { style: 'thin' as const },
      bottom: { style: 'thin' as const }, right: { style: 'thin' as const }
    };
    header.eachCell(c => {
      c.font = { bold: true, color: { argb: 'FFFFFFFF' } };
      c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF337AB7' } };
      c.alignment = { horizontal: 'center', vertical: 'middle' };
      c.border = borde;
    });
    ws.columns = columnas.map(c => ({ key: c, width: ['AREA', 'PTO. PARTIDA', 'PTO. LLEGADA', 'MOTIVO'].includes(c) ? 18 : 12 }));

    this.registrosFiltrados.forEach((r, i) => {
      const f = fechaProg(r);
      const row = ws.addRow([
        f ? MESES[f.getMonth()] : '', f ? semana(f) : '', r.fechaProgramada ?? '',
        r.nombre, r.horaProgramada, r.area ?? '', r.puntoPartida, r.puntoLlegada,
        r.cantidad, r.motivo ?? '', this.placaTexto(r), r.realizado ? 'SI' : 'NO',
        demora(r), '', intervalo(r)
      ]);
      const bg = i % 2 === 0 ? 'FFFFFFFF' : 'FFEBEBEB';
      row.eachCell(c => { c.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: bg } }; c.border = borde; });
    });

    const buf = await wb.xlsx.writeBuffer();
    saveAs(new Blob([buf], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }),
      `reporte-movilidad-${this.desde}-${this.hasta}.xlsx`);
  }

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
