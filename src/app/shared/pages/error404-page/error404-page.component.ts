import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

@Component({
  selector: 'app-error404-page',
  standalone: true,
  imports: [RouterLink],
  template: `
    <div class="d-flex flex-column align-items-center justify-content-center vh-100">
      <h1>404</h1>
      <p>Página no encontrada</p>
      <a routerLink="/auth/login">Volver al inicio</a>
    </div>
  `
})
export class Error404PageComponent {}
