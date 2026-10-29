import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { BehaviorSubject } from 'rxjs';
import { lastValueFrom } from 'rxjs';
import { environment } from '@/environments/environment';

export type VersionControlApi = 'TRANSPORTE' | 'MAESTRA';
const VERSION_API_STORAGE_KEY = 'version_control_api';

export interface DeploymentRecord {
  id?: number;
  appName: string;
  environment: string;
  version: string;
  buildTime?: string | null;
  deployedAt?: string | null;
  deployedBy?: string | null;
  serverName?: string | null;
  notes?: string | null;
  isActive?: boolean;
}

export interface VersionAuditSnapshot {
  appName: string;
  environment: string;
  localVersion: string;
  serverVersion: string | null;
  apiVersion: string | null;
  apiDeployment: DeploymentRecord | null;
  confirmedUpdateVersion: string | null;
  promptDecisionReason: string;
  isLocalBehindServer: boolean;
  isServerOutOfSyncWithApi: boolean;
  isFullyAligned: boolean;
}

/**
 * Servicio dual de control de versiones.
 *
 * Soporta ambas APIs con un switch runtime:
 *   - 'TRANSPORTE' → api_transporte_personal (GET con query params, SQL inline)
 *   - 'MAESTRA'    → api_maestros  (POST con JSON body, Stored Procedures)
 *
 * Selección de la API en este orden de prioridad:
 *   1. localStorage[VERSION_API_STORAGE_KEY] (override manual desde la UI)
 *   2. environment.versionControlApi (default por entorno)
 *   3. 'MAESTRA' como fallback final
 *
 * El usuario puede cambiar la API en runtime desde el switcher en Administración.
 */
@Injectable({ providedIn: 'root' })
export class DeploymentTrackingService {
  private readonly transporteBaseUrl = environment.baseUrl;
  private readonly maestraBaseUrl = environment.apiMaestra;
  private readonly appName = 'transporte-personal';
  private readonly environmentName = environment.production ? 'production' : 'development';

  /** Estado reactivo de la API activa para que la UI pueda observarlo. */
  private readonly _activeApi$ = new BehaviorSubject<VersionControlApi>(this.resolveActiveApi());
  public readonly activeApi$ = this._activeApi$.asObservable();

  constructor(private http: HttpClient) {}

  getAppName(): string {
    return this.appName;
  }

  getEnvironmentName(): string {
    return this.environmentName;
  }

  /** Devuelve la API actualmente activa. */
  getActiveApi(): VersionControlApi {
    return this._activeApi$.value;
  }

  /** Cambia la API activa (persiste en localStorage). */
  setActiveApi(api: VersionControlApi): void {
    try {
      localStorage.setItem(VERSION_API_STORAGE_KEY, api);
    } catch {
      // localStorage no disponible (modo privado, etc.)
    }
    this._activeApi$.next(api);
    console.log(`🔁 API de control de versiones cambiada a: ${api}`);
  }

  /** Resuelve la API activa al iniciar el servicio. */
  private resolveActiveApi(): VersionControlApi {
    try {
      const stored = localStorage.getItem(VERSION_API_STORAGE_KEY);
      if (stored === 'TRANSPORTE' || stored === 'MAESTRA') {
        return stored;
      }
    } catch {
      // ignore
    }
    const envValue = (environment as any).versionControlApi as VersionControlApi | undefined;
    if (envValue === 'TRANSPORTE' || envValue === 'MAESTRA') {
      return envValue;
    }
    return 'MAESTRA';
  }

  /** Devuelve la URL base + ruta según la API activa. */
  private endpointFor(path: 'current' | 'history' | 'register'): string {
    if (this.getActiveApi() === 'MAESTRA') {
      return `${this.maestraBaseUrl}/api/app-deployments/${path}`;
    }
    // En api_transporte_personal el registro va al raíz (POST /api/app-deployments)
    if (path === 'register') {
      return `${this.transporteBaseUrl}/api/app-deployments`;
    }
    return `${this.transporteBaseUrl}/api/app-deployments/${path}`;
  }

  /** Obtiene el despliegue activo. Detecta API y usa GET o POST. */
  async getCurrentDeployment(): Promise<DeploymentRecord | null> {
    const api = this.getActiveApi();
    try {
      if (api === 'MAESTRA') {
        const body = { appName: this.appName, environment: this.environmentName };
        const response = await lastValueFrom(
          this.http.post<DeploymentRecord | null>(this.endpointFor('current'), body)
        );
        return response ?? null;
      } else {
        const params = new HttpParams()
          .set('appName', this.appName)
          .set('environment', this.environmentName);
        const response = await lastValueFrom(
          this.http.get<DeploymentRecord>(this.endpointFor('current'), { params })
        );
        return response ?? null;
      }
    } catch (error) {
      console.warn(`No se pudo consultar el despliegue actual en API ${api}:`, error);
      return null;
    }
  }

  /** Obtiene el historial de despliegues. */
  async getDeploymentHistory(take: number = 20): Promise<DeploymentRecord[]> {
    const api = this.getActiveApi();
    try {
      if (api === 'MAESTRA') {
        const body = { appName: this.appName, environment: this.environmentName, take };
        const response = await lastValueFrom(
          this.http.post<DeploymentRecord[] | null>(this.endpointFor('history'), body)
        );
        return response ?? [];
      } else {
        const params = new HttpParams()
          .set('appName', this.appName)
          .set('environment', this.environmentName)
          .set('take', String(take));
        const response = await lastValueFrom(
          this.http.get<DeploymentRecord[]>(this.endpointFor('history'), { params })
        );
        return response ?? [];
      }
    } catch (error) {
      console.warn(`No se pudo consultar el historial en API ${api}:`, error);
      return [];
    }
  }

  /** Registra un nuevo despliegue (usado por scripts CI). */
  async registerDeployment(record: DeploymentRecord): Promise<DeploymentRecord | null> {
    const api = this.getActiveApi();
    try {
      const response = await lastValueFrom(
        this.http.post<DeploymentRecord>(this.endpointFor('register'), record)
      );
      return response ?? null;
    } catch (error) {
      console.error(`No se pudo registrar el despliegue en API ${api}:`, error);
      return null;
    }
  }

  async buildVersionAudit(localVersion: string, serverVersion: string | null): Promise<VersionAuditSnapshot> {
    const apiDeployment = await this.getCurrentDeployment();
    const apiVersion = apiDeployment?.version ?? null;
    let promptDecisionReason = 'No hay una nueva version confirmada.';

    const apiLabel = this.getActiveApi() === 'MAESTRA' ? 'API Maestra' : 'API Transporte';

    if (!serverVersion) {
      promptDecisionReason = 'No se pudo obtener version.json desde IIS.';
    } else if (!apiVersion) {
      promptDecisionReason = `La ${apiLabel} no devolvio una version activa para comparar.`;
    } else if (serverVersion !== apiVersion) {
      promptDecisionReason = `IIS y ${apiLabel} no coinciden (${serverVersion} vs ${apiVersion}).`;
    } else if (serverVersion === localVersion) {
      promptDecisionReason = `El usuario ya tiene la ultima version (${localVersion}).`;
    } else {
      promptDecisionReason = `Hay una nueva version confirmada (${serverVersion}).`;
    }

    const confirmedUpdateVersion =
      !!serverVersion &&
      !!apiVersion &&
      serverVersion === apiVersion &&
      serverVersion !== localVersion
        ? serverVersion
        : null;

    return {
      appName: this.appName,
      environment: this.environmentName,
      localVersion,
      serverVersion,
      apiVersion,
      apiDeployment,
      confirmedUpdateVersion,
      promptDecisionReason,
      isLocalBehindServer: !!serverVersion && serverVersion !== localVersion,
      isServerOutOfSyncWithApi: !!serverVersion && !!apiVersion && serverVersion !== apiVersion,
      isFullyAligned: !!serverVersion && !!apiVersion && localVersion === serverVersion && serverVersion === apiVersion
    };
  }

  shouldPromptForUpdate(snapshot: VersionAuditSnapshot): boolean {
    return !!snapshot.confirmedUpdateVersion;
  }

  logAuditResult(snapshot: VersionAuditSnapshot): void {
    console.log('Version audit:', snapshot);
    console.log(`Decision modal: ${snapshot.promptDecisionReason}`);

    if (snapshot.isFullyAligned) {
      console.log(
        `Versiones alineadas: local=${snapshot.localVersion}, iis=${snapshot.serverVersion}, api=${snapshot.apiVersion}`
      );
      return;
    }

    if (snapshot.isLocalBehindServer) {
      console.warn(
        `Cliente desactualizado: local=${snapshot.localVersion}, iis=${snapshot.serverVersion}`
      );
    }

    if (snapshot.isServerOutOfSyncWithApi) {
      const apiLabel = this.getActiveApi() === 'MAESTRA' ? 'API Maestra' : 'API Transporte';
      console.warn(
        `IIS y ${apiLabel} no coinciden: iis=${snapshot.serverVersion}, api=${snapshot.apiVersion}`
      );
    }

    if (snapshot.confirmedUpdateVersion) {
      console.log(
        `Nueva version confirmada para actualizar: ${snapshot.confirmedUpdateVersion}`
      );
    }

    if (!snapshot.apiVersion) {
      const apiLabel = this.getActiveApi() === 'MAESTRA' ? 'API Maestra' : 'API Transporte';
      console.warn(`La ${apiLabel} no devolvio un despliegue activo para auditoria de version.`);
    }
  }
}
