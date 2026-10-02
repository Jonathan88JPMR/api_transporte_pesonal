import { Component } from '@angular/core';
import { Router } from '@angular/router';
import { FormBuilder, FormGroup, ReactiveFormsModule, Validators } from '@angular/forms';
import { CommonModule } from '@angular/common';
import { AuthService } from '@/app/modules/auth/services/auth.service';
import { DexieService } from '@/app/shared/dixiedb/dexie-db.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './login.component.html',
  styleUrl: './login.component.scss'
})
export class LoginComponent {

  mostrarClave = false;
  mensajeLogin: string = '';
  isCharge = false;
  loginForm: FormGroup;

  constructor(
    private router: Router,
    private fb: FormBuilder,
    private dexieService: DexieService,
    private alertService: AlertService,
    private authService: AuthService
  ) {
    this.loginForm = this.fb.group({
      usuario: ['', [Validators.required]],
      clave: ['', Validators.required]
    });
  }

  async ngOnInit() {
    const usuario = await this.dexieService.showUsuario();
    if (usuario) {
      this.redireccionarPorRol(usuario.idrol);
    }
  }

  toggleClave(): void {
    this.mostrarClave = !this.mostrarClave;
  }

  // Redirección centralizada por rol
  private redireccionarPorRol(rol: string) {
    switch (rol) {
      case 'COTRANS':
        this.router.navigate(['/main/coordinador']);
        break;
      case 'CHTRANS':
        this.router.navigate(['/main/conductor']);
        break;
      case 'ADTRANS':
        this.router.navigate(['/main/coordinador']);
        break;
      case 'SPTRANS':
      default:
        this.router.navigate(['/main/solicitudes']);
        break;
    }
  }

  async onSubmit() {
    if (!this.loginForm.valid) return;

    this.isCharge = true;
    const loginData = this.loginForm.value;
    try {
      const resp = await this.authService.login(loginData.usuario, loginData.clave);
      if (resp && resp.length > 0) {
        await this.dexieService.saveUsuario(resp[0]);
        this.redireccionarPorRol(resp[0].idrol);
      } else {
        this.mensajeLogin = 'El usuario no se encuentra registrado.';
      }
    } catch (error) {
      this.mensajeLogin = 'Hubo un error en el login, por favor intente nuevamente.';
      this.alertService.showAlert('error', this.mensajeLogin, 'Error');
    } finally {
      this.isCharge = false;
    }
  }
}
