import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ChartModule } from 'primeng/chart';
import { TransporteService } from '../../services/transporte.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';
import { IndicadoresReporte } from '@/app/models/transporte.models';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, FormsModule, ChartModule],
  templateUrl: './dashboard.component.html',
  styleUrl: './dashboard.component.scss'
})
export class DashboardComponent implements OnInit {

  indicadores?: IndicadoresReporte;
  desde?: string;
  hasta?: string;
  cargando = false;

  // Réplica de los gráficos del Excel (hoja DASHBOARD)
  chartArea: any;            // 1. Movimiento de personal por cada área
  chartMotivo: any;          // 2. Motivo de movimiento
  chartRealizados: any;      // 3. Total de viajes realizados (pie)
  chartHoras: any;           // 4. Horas con mayor frecuencia
  chartUnidad: any;          // 5. Personal trasladado por unidad
  chartAreaTop: any;         // 6. Área que trasladó más personal
  chartSemana: any;          // 7. Personal transportado por semana
  chartMes: any;             // 8. Tendencia por mes (línea)

  readonly opcionesBar = {
    responsive: true, maintainAspectRatio: false,
    plugins: { legend: { display: false } },
    scales: { y: { beginAtZero: true, ticks: { precision: 0 } } }
  };
  readonly opcionesPie = {
    responsive: true, maintainAspectRatio: false,
    plugins: { legend: { position: 'bottom' } }
  };

  private readonly paleta = ['#42A5F5', '#66BB6A', '#FFA726', '#AB47BC', '#26C6DA', '#EC407A', '#8D6E63', '#78909C', '#D4E157', '#5C6BC0'];

  constructor(private transporteService: TransporteService, private alerts: AlertService) { }

  async ngOnInit() {
    const hoy = new Date();
    this.desde = this.toIso(new Date(hoy.getFullYear(), hoy.getMonth(), 1));
    this.hasta = this.toIso(hoy);
    await this.cargar();
  }

  async cargar() {
    this.cargando = true;
    try {
      this.indicadores = await this.transporteService.reporteIndicadores(this.desde, this.hasta);
      this.armarCharts();
    } catch {
      this.alerts.showAlert('error', 'No se pudo cargar el dashboard', 'Error');
    } finally {
      this.cargando = false;
    }
  }

  get porMotivo() { return this.indicadores?.porMotivo ?? []; }
  // % de cobertura real: cuánto de lo planificado quedó registrado en las paradas
  get porcentajeReal(): number {
    const total = this.indicadores?.totalPersonas ?? 0;
    return total ? (100 * (this.indicadores?.personasReales ?? 0)) / total : 0;
  }

  private barra(labels: string[], valores: number[], extra?: any) {
    return {
      labels,
      datasets: [{ data: valores, backgroundColor: this.paleta, borderWidth: 0, ...extra }]
    };
  }

  private armarCharts() {
    const i = this.indicadores;
    if (!i) return;
    const porArea = [...(i.areas ?? [])].sort((a, b) => b.personas - a.personas);
    const porUnidad = [...(i.unidades ?? [])].sort((a, b) => b.personas - a.personas);
    const porEstado = i.porEstado ?? [];

    this.chartArea = this.barra(porArea.map(a => a.area || '(sin área)'), porArea.map(a => a.personas));
    this.chartMotivo = this.barra(this.porMotivo.map(m => m.motivo), this.porMotivo.map(m => m.personas));
    this.chartRealizados = {
      labels: porEstado.map(e => e.realizados),
      datasets: [{ data: porEstado.map(e => e.viajes), backgroundColor: ['#66BB6A', '#FFA726', '#EF5350'] }]
    };
    this.chartHoras = this.barra((i.porIntervalo ?? []).map(h => h.intervalo), (i.porIntervalo ?? []).map(h => h.personas));
    this.chartUnidad = this.barra(porUnidad.map(u => u.placa), porUnidad.map(u => u.personas));
    this.chartAreaTop = this.barra(porArea.slice(0, 8).map(a => a.area || '(sin área)'), porArea.slice(0, 8).map(a => a.personas));
    this.chartSemana = this.barra((i.porSemana ?? []).map(s => s.semana), (i.porSemana ?? []).map(s => s.personas));
    this.chartMes = {
      labels: (i.porMes ?? []).map(m => m.mes),
      datasets: [{
        data: (i.porMes ?? []).map(m => m.personas),
        borderColor: '#42A5F5', backgroundColor: 'rgba(66,165,245,.25)',
        fill: true, tension: .35, pointRadius: 4, pointBackgroundColor: '#42A5F5'
      }]
    };
  }

  private toIso(d: Date): string {
    const p = (n: number) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
  }
}
