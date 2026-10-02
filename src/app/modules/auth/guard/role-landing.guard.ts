import { Injectable } from '@angular/core';
import { CanActivate, Router, UrlTree } from '@angular/router';
import { AuthService } from '../services/auth.service';

@Injectable({ providedIn: 'root' })
export class RoleLandingGuard implements CanActivate {
  constructor(private authService: AuthService, private router: Router) {}

  async canActivate(): Promise<UrlTree> {
    const user = await this.authService.getUser();
    switch (user?.idrol) {
      case 'COTRANS':
      case 'ADTRANS':
        return this.router.parseUrl('/main/coordinador');
      case 'CHTRANS':
        return this.router.parseUrl('/main/conductor');
      case 'SPTRANS':
        return this.router.parseUrl('/main/solicitudes');
      default:
        return this.router.parseUrl('/auth/login');
    }
  }
}
