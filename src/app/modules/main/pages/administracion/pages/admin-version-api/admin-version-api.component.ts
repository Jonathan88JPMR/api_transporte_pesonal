import { Component, OnInit, OnDestroy, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Subscription } from 'rxjs';
import Swal from 'sweetalert2';
import {
  DeploymentTrackingService,
  DeploymentRecord,
  VersionAuditSnapshot,
  VersionControlApi
} from '@/app/services/deployment-tracking.service';
import { VersionService } from '@/app/services/version.service';
import { environment } from '@/environments/environment';

@Component({
  selector: 'app-admin-version-api',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './admin-version-api.component.html',
  styleUrls: ['./admin-version-api.component.scss']
})
export class AdminVersionApiComponent implements OnInit, OnDestroy {
  private deploymentSvc = inject(DeploymentTrackingService);
  private versionSvc = inject(VersionService);

  activeApi: VersionControlApi = 'TRANSPORTE';
  defaultApi: VersionControlApi = ((environment as any).versionControlApi as VersionControlApi) || 'MAESTRA';

  // URLs informativas
  transporteUrl = environment.baseUrl + '/api/app-deployments';
  maestraUrl = environment.apiMaestra + '/api/app-deployments';

  // Datos de la prueba en vivo
  loading = false;
  loadingHistory = false;
  localVersion = '';
  serverVersion: string | null = null;
  audit: VersionAuditSnapshot | null = null;
  currentDeployment: DeploymentRecord | null = null;

  // Historial de deployments
  history: DeploymentRecord[] = [];
  historyTake = 20;
  historyTakeOptions = [10, 20, 50, 100, 200];
  expandedId: number | null = null;

  private sub?: Subscription;

  ngOnInit(): void {
    this.activeApi = this.deploymentSvc.getActiveApi();
    this.sub = this.deploymentSvc.activeApi$.subscribe(api => (this.activeApi = api));
    void this.cargarEstado();
  }

  ngOnDestroy(): void {
    this.sub?.unsubscribe();
  }

  async cambiarApi(nueva: VersionControlApi) {
    if (nueva === this.activeApi) return;

    const result = await Swal.fire({
      title: '¿Cambiar la API de control de versiones?',
      html: `
        <p>Se usará: <b>${nueva === 'MAESTRA' ? 'API Maestra (api_maestros)' : 'API Transporte (api_transporte_personal)'}</b></p>
        <p style="font-size: 13px; color: #666;">
          El cambio aplica de inmediato para todas las consultas de versión en este navegador.
          Las demás funcionalidades de la app no se ven afectadas.
        </p>
      `,
      icon: 'question',
      showCancelButton: true,
      confirmButtonText: 'Sí, cambiar',
      cancelButtonText: 'Cancelar',
      confirmButtonColor: '#3085d6'
    });

    if (!result.isConfirmed) return;

    this.deploymentSvc.setActiveApi(nueva);
    await Swal.fire({
      icon: 'success',
      title: 'API cambiada',
      text: `Ahora se usa: ${nueva}`,
      timer: 1500,
      showConfirmButton: false
    });

    await this.cargarEstado();
  }

  async cargarEstado() {
    this.loading = true;
    try {
      this.localVersion = await this.versionSvc.getLocalVersion();
      this.serverVersion = await this.versionSvc.getServerVersion();
      this.currentDeployment = await this.deploymentSvc.getCurrentDeployment();
      this.audit = await this.deploymentSvc.buildVersionAudit(this.localVersion, this.serverVersion);
      await this.cargarHistorial();
    } catch (err) {
      console.error('Error cargando estado:', err);
    } finally {
      this.loading = false;
    }
  }

  async cargarHistorial() {
    this.loadingHistory = true;
    try {
      this.history = await this.deploymentSvc.getDeploymentHistory(this.historyTake);
    } catch (err) {
      console.error('Error cargando historial:', err);
      this.history = [];
    } finally {
      this.loadingHistory = false;
    }
  }

  toggleExpand(id: number | undefined) {
    if (id == null) return;
    this.expandedId = this.expandedId === id ? null : id;
  }

  trackById(_: number, item: DeploymentRecord): any {
    return item.id ?? item.version;
  }

  /** Calcula cuanto tiempo ha pasado desde la fecha (ej. "hace 3 dias"). */
  tiempoTranscurrido(fecha: string | null | undefined): string {
    if (!fecha) return '-';
    const d = new Date(fecha);
    if (isNaN(d.getTime())) return '-';
    const ms = Date.now() - d.getTime();
    const seg = Math.floor(ms / 1000);
    const min = Math.floor(seg / 60);
    const hor = Math.floor(min / 60);
    const dia = Math.floor(hor / 24);
    if (dia > 0) return `hace ${dia} día${dia > 1 ? 's' : ''}`;
    if (hor > 0) return `hace ${hor} h`;
    if (min > 0) return `hace ${min} min`;
    if (seg > 0) return `hace ${seg} s`;
    return 'ahora mismo';
  }

  exportarHistorialCSV() {
    if (!this.history.length) return;
    const headers = [
      'Id', 'AppName', 'Environment', 'Version', 'BuildTime',
      'DeployedAt', 'DeployedBy', 'ServerName', 'Notes', 'IsActive'
    ];
    const rows = this.history.map(d => [
      d.id ?? '',
      d.appName ?? '',
      d.environment ?? '',
      d.version ?? '',
      d.buildTime ?? '',
      d.deployedAt ?? '',
      d.deployedBy ?? '',
      d.serverName ?? '',
      (d.notes ?? '').replace(/"/g, '""'),
      d.isActive ? 'true' : 'false'
    ]);
    const csv = [
      headers.join(','),
      ...rows.map(r => r.map(c => `"${c}"`).join(','))
    ].join('\r\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `historial-versiones-${this.activeApi}-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  apiLabel(api: VersionControlApi): string {
    return api === 'MAESTRA' ? 'API Maestra (POST + SP)' : 'API Transporte (GET + SQL)';
  }

  apiUrl(api: VersionControlApi): string {
    return api === 'MAESTRA' ? this.maestraUrl : this.transporteUrl;
  }
}
