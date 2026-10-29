import { Component, OnDestroy, OnInit, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { VersionService } from './services/version.service';
import { DeploymentTrackingService } from './services/deployment-tracking.service';
import { environment } from '@/environments/environment';
import Swal from 'sweetalert2';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet],
  templateUrl: './app.html',
  styleUrl: './app.scss'
})
export class App implements OnInit, OnDestroy {
  protected readonly title = signal('transporte-personal');
  APP_VERSION = environment.appVersion;

  private checkInterval: any;
  private readonly CHECK_INTERVAL_MINUTES = 10;
  private lastPromptKey = 'last_update_prompt';
  private isUpdateFlowRunning = false;
  private readonly onWindowFocus = () => {
    this.runVersionCheck('focus');
  };
  private readonly onWindowOnline = () => {
    this.runVersionCheck('online');
  };
  private readonly onVisibilityChange = () => {
    if (document.visibilityState === 'visible') {
      this.runVersionCheck('visibility');
    }
  };

  constructor(
    private versionService: VersionService,
    private deploymentTrackingService: DeploymentTrackingService
  ) { }

  ngOnInit() {
    const mode = this.versionService.getMode();
    this.auditDeploymentVersions();

    /** 💤 SIN EFECTO */
    if (mode === 'DISABLED') {
      console.log('🔕 Actualizaciones desactivadas');
      return;
    }

    /** 🔄 AUTOMÁTICO */
    if (mode === 'AUTO') {
      this.registerVersionCheckListeners();
      this.runVersionCheck('init');
      this.scheduleVersionChecks();
    }
    /** 🔥 MANUAL → no hace nada al iniciar */
  }

  ngOnDestroy() {
    if (this.checkInterval) clearInterval(this.checkInterval);
    this.removeVersionCheckListeners();
  }

  /** 🔄 automático */
  scheduleVersionChecks() {
    this.checkInterval = setInterval(() => {
      this.runVersionCheck('interval');
    }, this.CHECK_INTERVAL_MINUTES * 60 * 1000);
  }

  registerVersionCheckListeners() {
    window.addEventListener('focus', this.onWindowFocus);
    window.addEventListener('online', this.onWindowOnline);
    document.addEventListener('visibilitychange', this.onVisibilityChange);
  }

  removeVersionCheckListeners() {
    window.removeEventListener('focus', this.onWindowFocus);
    window.removeEventListener('online', this.onWindowOnline);
    document.removeEventListener('visibilitychange', this.onVisibilityChange);
  }

  runVersionCheck(reason: string) {
    console.log(`🔄 Ejecutando verificación de versión por: ${reason}`);
    void this.checkVersionFromServer();
  }

  async checkVersionFromServer() {
    if (this.versionService.getMode() !== 'AUTO') return;

    const remote = await this.versionService.getServerVersion();
    const local = await this.versionService.getLocalVersion();
    const updated = this.versionService.getUpdatedVersion();
    const audit = await this.auditDeploymentVersions(local, remote);

    console.log('🔍 Verificando versiones:', { remote, local, updated });

    const targetVersion = audit?.confirmedUpdateVersion ?? null;

    if (!targetVersion) {
      console.log('✅ No hay una nueva versión confirmada para mostrar al usuario.');
      return;
    }

    // Si ya se actualizó a esta versión, no mostrar el modal
    if (updated && targetVersion === updated) {
      console.log('✅ La aplicación ya está actualizada a la versión', targetVersion);
      return;
    }

    const lastPrompt = localStorage.getItem(this.lastPromptKey);
    const now = Date.now();

    // Evita mostrar el modal muchas veces (cada 15 minutos máximo)
    if (!lastPrompt || now - parseInt(lastPrompt) > 15 * 60 * 1000) {
      await this.handleUpdate(targetVersion, local);
      localStorage.setItem(this.lastPromptKey, now.toString());
    }
  }

  /** 🔥 manual */
  async triggerManualUpdate() {
    if (this.versionService.getMode() !== 'MANUAL') return;
    await this.handleUpdate();
  }

  /** 🎯 punto único de decisión */
  async handleUpdate(remoteVersion?: string | null, localVersion?: string) {
    if (this.isUpdateFlowRunning) return;

    const local = localVersion ?? await this.versionService.getLocalVersion();
    let remote = remoteVersion ?? null;

    if (!remote) {
      const audit = await this.auditDeploymentVersions(local);
      remote = audit?.confirmedUpdateVersion ?? null;
    }

    if (!remote || remote === local) return;

    this.isUpdateFlowRunning = true;

    try {
      if (this.versionService.canShowModal()) {
        await this.askUserToUpdate(remote, local);
      } else {
        await this.clearDexieAndReload();
      }
    } finally {
      this.isUpdateFlowRunning = false;
    }
  }

  async askUserToUpdate(remote?: string, local?: string) {
    const result = await Swal.fire({
      title: '⚡ Nueva versión disponible',
      html: `
        <p>Versión actual: <b>${local ?? this.APP_VERSION}</b></p>
        <p>Versión nueva: <b>${remote ?? 'desconocida'}</b></p>
        <p>¿Deseas actualizar ahora?</p>
      `,
      icon: 'info',
      confirmButtonText: 'Actualizar ahora',
      cancelButtonText: 'Más tarde',
      showCancelButton: true,
      confirmButtonColor: '#3085d6',
      cancelButtonColor: '#aaa',
      allowOutsideClick: false
    });

    if (result.isConfirmed) {
      await this.clearDexieAndReload();
    }
  }

  async auditDeploymentVersions(localVersion?: string, serverVersion?: string | null) {
    const local = localVersion ?? await this.versionService.getLocalVersion();
    const server = typeof serverVersion === 'undefined'
      ? await this.versionService.getServerVersion()
      : serverVersion;

    const audit = await this.deploymentTrackingService.buildVersionAudit(local, server);
    this.deploymentTrackingService.logAuditResult(audit);
    return audit;
  }

  async clearDexieAndReload() {
    try {
      // Guardar la versión que se está actualizando
      const remote = await this.versionService.getServerVersion();
      if (remote) {
        this.versionService.setUpdatedVersion(remote);
        console.log('💾 Guardando versión actualizada:', remote);
      }

      const dbs = await indexedDB.databases();
      for (const db of dbs) {
        if (db.name) indexedDB.deleteDatabase(db.name);
      }
    } catch (err) {
      console.error('Error limpiando Dexie:', err);
    } finally {
      Swal.fire({
        title: 'Actualizando...',
        text: 'La aplicación se recargará en un momento.',
        allowOutsideClick: false,
        showConfirmButton: false,
        didOpen: () => Swal.showLoading()
      });
      setTimeout(() => window.location.reload(), 1500);
    }
  }
}
