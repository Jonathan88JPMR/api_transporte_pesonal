import { Component, OnDestroy, OnInit } from '@angular/core';
import { Router, RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '@/app/modules/auth/services/auth.service';
import { Usuario } from '@/app/models/transporte.models';
import { TransporteService } from '../../services/transporte.service';
import { DexieService } from '@/app/shared/dixiedb/dexie-db.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';
import { environment } from '@/environments/environment';

interface MenuItem {
  label: string;
  icon: string;
  route: string;
  seccion: string;
  visible: boolean;
}

@Component({
  selector: 'app-layout',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterOutlet, RouterLink, RouterLinkActive],
  templateUrl: './layout.component.html',
  styleUrl: './layout.component.scss'
})
export class LayoutComponent implements OnInit, OnDestroy {

  usuario?: Usuario;
  menu: MenuItem[] = [];
  version = environment.appVersion;
  fechaHoy = new Date();
  currentPath = '';
  isOnline = true;
  notificaciones: any[] = [];
  mostrarNotificaciones = false;
  operacionesPendientes = 0;
  mostrarClave = false;
  claveActual = '';
  claveNueva = '';
  claveConfirmar = '';
  private actualizador?: ReturnType<typeof setInterval>;
  private idsNotificados = new Set<number>();
  private primeraCargaNotificaciones = true;
  private permisoPedido = false;
  private onOnline = () => { this.isOnline = true; };
  private onOffline = () => { this.isOnline = false; };

  constructor(
    private router: Router,
    private authService: AuthService,
    private transporteService: TransporteService,
    private dexie: DexieService,
    private alertService: AlertService
  ) { }

  async ngOnInit() {
    this.usuario = await this.authService.getUser();
    const rol = this.usuario?.idrol ?? '';

    const esSupervisor = rol === 'SPTRANS' || rol === 'ADTRANS';
    const esCoordinador = rol === 'COTRANS' || rol === 'ADTRANS';
    const esConductor = rol === 'CHTRANS' || rol === 'ADTRANS';
    const esAdmin = rol === 'ADTRANS' || rol === 'COTRANS';

    this.isOnline = navigator.onLine;
    window.addEventListener('online', this.onOnline);
    window.addEventListener('offline', this.onOffline);

    await this.actualizarEstado();
    this.actualizador = setInterval(() => void this.actualizarEstado(), 30000);

    this.menu = [
      { label: 'Solicitudes', icon: 'bx-list-ul', route: '/main/solicitudes', seccion: 'Procesos', visible: esSupervisor },
      { label: 'Coordinación', icon: 'bx-git-branch', route: '/main/coordinador', seccion: 'Procesos', visible: esCoordinador },
      { label: 'Mis servicios', icon: 'bxs-truck', route: '/main/conductor', seccion: 'Procesos', visible: esConductor },
      { label: 'Reportes', icon: 'bx-bar-chart', route: '/main/reportes', seccion: 'Reportes', visible: esAdmin },
      { label: 'Administración', icon: 'bx-cog', route: '/main/administracion', seccion: 'Configuración', visible: rol === 'ADTRANS' }
    ].filter(item => item.visible);

    this.updateCurrentPath();
    this.router.events.subscribe(() => this.updateCurrentPath());
  }

  get noLeidas(): number { return this.notificaciones.filter(n => !n.leida).length; }

  async actualizarEstado() {
    this.operacionesPendientes = await this.dexie.totalOperacionesPendientes();
    if (!this.usuario || !navigator.onLine) return;
    try {
      const lista = await this.transporteService.listarNotificaciones(this.usuario.idUsuario);
      this.notificarPush(lista);
      this.notificaciones = lista;
    } catch { }
  }

  // RF-037: notificación push del navegador cuando llega un aviso nuevo
  private notificarPush(lista: any[]) {
    if (!('Notification' in window)) return;
    if (Notification.permission === 'default') {
      if (!this.permisoPedido) {
        this.permisoPedido = true;
        void Notification.requestPermission();
      }
      lista.forEach(n => this.idsNotificados.add(n.idNotificacion));
      this.primeraCargaNotificaciones = false;
      return;
    }
    if (Notification.permission !== 'granted') return;
    for (const n of lista) {
      if (!n.leida && !this.idsNotificados.has(n.idNotificacion) && !this.primeraCargaNotificaciones) {
        new Notification(n.titulo, { body: n.mensaje, icon: 'favicon.svg' });
      }
      this.idsNotificados.add(n.idNotificacion);
    }
    this.primeraCargaNotificaciones = false;
  }

  async leerNotificacion(notificacion: any) {
    if (!this.usuario || notificacion.leida) return;
    await this.transporteService.marcarNotificacion(this.usuario.idUsuario, notificacion.idNotificacion);
    notificacion.leida = true;
  }

  async cambiarClave() {
    if (!this.usuario) return;
    if (this.claveNueva.length < 6 || this.claveNueva !== this.claveConfirmar) {
      this.alertService.showAlert('warning', 'La nueva clave debe tener al menos 6 caracteres y coincidir con la confirmación', 'Atención');
      return;
    }
    try {
      await this.transporteService.cambiarClave(this.usuario.usuario, this.claveActual, this.claveNueva);
      this.alertService.showAlert('success', 'Clave actualizada correctamente', 'Éxito');
      this.mostrarClave = false;
      this.claveActual = this.claveNueva = this.claveConfirmar = '';
    } catch {
      this.alertService.showAlert('error', 'No se pudo cambiar la clave. Verifique la clave actual', 'Error');
    }
  }

  ngOnDestroy() {
    if (this.actualizador) clearInterval(this.actualizador);
    window.removeEventListener('online', this.onOnline);
    window.removeEventListener('offline', this.onOffline);
  }

  toggleSidebar() {
    const mainWrapper = document.getElementById('main-wrapper');
    if (window.matchMedia('(max-width: 1200px)').matches) {
      if (mainWrapper) {
        if (mainWrapper.classList.contains('show-sidebar')) {
          mainWrapper.setAttribute('data-sidebartype', 'mini-sidebar');
          mainWrapper.classList.remove('show-sidebar');
        } else {
          mainWrapper.setAttribute('data-sidebartype', 'full');
          mainWrapper.classList.toggle('show-sidebar');
        }
      }
    } else {
      if (mainWrapper) {
        mainWrapper.setAttribute('data-sidebartype', 'full');
        mainWrapper.classList.remove('show-sidebar');
      }
    }
  }

  updateCurrentPath() {
    const segmentos = this.router.url.split('/').filter(Boolean);
    const pathMap: { [key: string]: string } = {
      solicitudes: 'Solicitudes de movilidad',
      coordinador: 'Coordinación',
      conductor: 'Mis servicios',
      reportes: 'Reportes',
      administracion: 'Administración'
    };
    this.currentPath = pathMap[segmentos[segmentos.length - 1]] || 'Transporte de Personal';
  }

  formatNombre(nombre?: string): string {
    if (!nombre) return '';
    const partes = nombre.split(' ');
    if (partes.length < 2) return nombre;
    return (
      partes[0].charAt(0).toUpperCase() + partes[0].slice(1).toLowerCase() +
      ' ' +
      partes[1].charAt(0).toUpperCase() + partes[1].slice(1).toLowerCase()
    );
  }

  async logout(): Promise<void> {
    await this.authService.logout();
  }
}
