import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Router } from '@angular/router';
import { environment } from '@/environments/environment';
import { lastValueFrom } from 'rxjs';
import { DexieService } from '../../../shared/dixiedb/dexie-db.service';
import { Usuario } from '@/app/models/transporte.models';

@Injectable({
  providedIn: 'root',
})
export class AuthService {
  private readonly baseUrl: string = environment.baseUrl;

  constructor(
    private http: HttpClient,
    private dexieService: DexieService,
    private router: Router
  ) { }

  async login(usuario: string, clave: string): Promise<Usuario[]> {
    const url = `${this.baseUrl}/api/transporte/auth/login`;
    const body = [{ usuario, clave }];

    try {
      return await lastValueFrom(this.http.post<Usuario[]>(url, body));
    } catch (error: any) {
      throw new Error(error.error?.message || 'Error de autenticación');
    }
  }

  async isLoggedIn(): Promise<boolean> {
    const user = await this.dexieService.showUsuario();
    if (!user?.token || this.tokenExpirado(user.token)) {
      await this.dexieService.clearUsuario();
      return false;
    }
    return true;
  }

  async getUser(): Promise<Usuario | undefined> {
    return await this.dexieService.getUsuarioLogueado();
  }

  async logout(): Promise<void> {
    await this.dexieService.clearUsuario();
    this.router.navigate(['/auth/login']);
  }

  private tokenExpirado(token: string): boolean {
    try {
      const payload = JSON.parse(atob(token.split('.')[1]));
      return !payload.exp || payload.exp * 1000 <= Date.now();
    } catch {
      return true;
    }
  }

  // Perfil Supervisor (solicita movilidades)
  async isSupervisor(): Promise<boolean> {
    const user = await this.getUser();
    const rol = user?.idrol ?? '';
    return rol.includes('SPTRANS') || rol.includes('ADTRANS');
  }

  // Perfil Coordinador (asigna unidades, une/separa traslados)
  async isCoordinador(): Promise<boolean> {
    const user = await this.getUser();
    const rol = user?.idrol ?? '';
    return rol.includes('COTRANS') || rol.includes('ADTRANS');
  }

  // Perfil Conductor
  async isConductor(): Promise<boolean> {
    const user = await this.getUser();
    const rol = user?.idrol ?? '';
    return rol.includes('CHTRANS') || rol.includes('ADTRANS');
  }

  // Perfil Administrador
  async isAdministrador(): Promise<boolean> {
    const user = await this.getUser();
    const rol = user?.idrol ?? '';
    return rol.includes('ADTRANS');
  }
}
