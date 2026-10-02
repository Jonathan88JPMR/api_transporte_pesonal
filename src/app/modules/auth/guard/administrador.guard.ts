import { Injectable } from '@angular/core';
import { CanActivate } from '@angular/router';
import { AuthService } from '../services/auth.service';

@Injectable({
    providedIn: 'root'
})
export class AdministradorGuard implements CanActivate {

    constructor(private authService: AuthService){}

    async canActivate(): Promise<boolean> {
      return this.authService.isAdministrador();
    }
}
