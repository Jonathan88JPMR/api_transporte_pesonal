import { Routes } from '@angular/router';
import { LoginComponent } from './modules/auth/pages/login/login.component';
import { LayoutComponent } from './modules/main/pages/layout/layout.component';
import { SolicitudesComponent } from './modules/main/pages/solicitudes/solicitudes.component';
import { CoordinadorComponent } from './modules/main/pages/coordinador/coordinador.component';
import { ConductorComponent } from './modules/main/pages/conductor/conductor.component';
import { ReportesComponent } from './modules/main/pages/reportes/reportes.component';
import { AdministracionComponent } from './modules/main/pages/administracion/administracion.component';
import { AdministradorGuard } from './modules/auth/guard/administrador.guard';
import { Error404PageComponent } from './shared/pages/error404-page/error404-page.component';
import { AuthGuard } from './modules/auth/guard/auth.guard';
import { SupervisorGuard } from './modules/auth/guard/supervisor.guard';
import { CoordinadorGuard } from './modules/auth/guard/coordinador.guard';
import { ConductorGuard } from './modules/auth/guard/conductor.guard';
import { RoleLandingGuard } from './modules/auth/guard/role-landing.guard';

export const routes: Routes = [
  {
    path: 'auth',
    children: [
      { path: 'login', component: LoginComponent },
      { path: '', redirectTo: 'login', pathMatch: 'full' }
    ]
  },
  {
    path: 'main',
    component: LayoutComponent,
    canActivate: [AuthGuard],
    children: [
      { path: 'solicitudes', component: SolicitudesComponent, canActivate: [SupervisorGuard] },
      { path: 'coordinador', component: CoordinadorComponent, canActivate: [CoordinadorGuard] },
      { path: 'conductor', component: ConductorComponent, canActivate: [ConductorGuard] },
      { path: 'reportes', component: ReportesComponent, canActivate: [CoordinadorGuard] },
      { path: 'administracion', component: AdministracionComponent, canActivate: [AdministradorGuard] },
      { path: '', canActivate: [RoleLandingGuard], children: [] }
    ]
  },
  { path: '404', component: Error404PageComponent },
  // { path: '', redirectTo: 'auth/login', pathMatch: 'full' },
  { path: '', redirectTo: 'main', pathMatch: 'full' },
  { path: '**', redirectTo: '404' }
];
