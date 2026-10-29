import { Injectable } from '@angular/core';
import { environment } from '@/environments/environment';

export type UpdateMode = 'AUTO' | 'MANUAL' | 'DISABLED';

@Injectable({ providedIn: 'root' })
export class VersionService {

  private versionUrl = '/assets/version.json';

  /** � NUEVO: configuración */
  private updateMode: UpdateMode = environment.updateMode as UpdateMode ?? 'AUTO';
  private showModal = environment.showUpdateModal ?? true;

  /** 🔧 setters */
  setMode(mode: UpdateMode) {
    this.updateMode = mode;
  }

  setShowModal(show: boolean) {
    this.showModal = show;
  }

  /** 🔍 getters */
  getMode(): UpdateMode {
    return this.updateMode;
  }

  canShowModal(): boolean {
    return this.showModal;
  }

  async getServerVersion(): Promise<string | null> {
    try {
      // Fuerza bypass del service worker y del cache del navegador.
      const timestamp = new Date().getTime();
      const url = `${this.versionUrl}?ngsw-bypass=true&t=${timestamp}`;
      const response = await fetch(url, {
        cache: 'no-store',
        headers: {
          'ngsw-bypass': 'true',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0'
        }
      });
      if (!response.ok) throw new Error('Error al obtener version.json');
      const data = await response.json();
      return data.version;
    } catch (err) {
      console.error('❌ No se pudo obtener la versión del servidor:', err);
      return null;
    }
  }

  async getLocalVersion(): Promise<string> {
    // Esta es la versión con la que fue construido el bundle que ya está corriendo.
    return environment.appVersion;
  }

  setLocalVersion(version: string) {
    localStorage.setItem('app_version', version);
  }

  getStoredVersion(): string | null {
    return localStorage.getItem('app_version');
  }

  /** Guardar la versión actualizada para no volver a mostrar el modal */
  setUpdatedVersion(version: string) {
    localStorage.setItem('app_updated_version', version);
  }

  getUpdatedVersion(): string | null {
    return localStorage.getItem('app_updated_version');
  }
}
