import { Component, OnDestroy, OnInit } from '@angular/core';
import { Router, RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '@/app/modules/auth/services/auth.service';
import { Usuario } from '@/app/models/transporte.models';
import { TransporteService } from '../../services/transporte.service';
import { PushService } from '../../services/push.service';
import { DexieService } from '@/app/shared/dixiedb/dexie-db.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';
import { environment } from '@/environments/environment';
import { ComunicadoModalComponent } from '@/app/shared/comunicado-modal/comunicado-modal.component';

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
  imports: [CommonModule, FormsModule, RouterOutlet, RouterLink, RouterLinkActive, ComunicadoModalComponent],
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
  // Comunicados "sin servicio": si hay uno vigente al ingresar (o se publica
  // mientras la app está abierta) el modal rojo bloquea la pantalla
  comunicados: any[] = [];
  mostrarComunicado = false;
  operacionesPendientes = 0;
  mostrarClave = false;
  claveActual = '';
  claveNueva = '';
  claveConfirmar = '';
  private actualizador?: ReturnType<typeof setInterval>;
  private idsNotificados = new Set<number>();
  private asignacionesAvisadas = new Set<number>();
  private primeraCargaNotificaciones = true;
  private permisoPedido = false;
  private onOnline = () => { this.isOnline = true; };
  private onOffline = () => { this.isOnline = false; };
  private audioCtx?: AudioContext;
  // Los navegadores móviles bloquean el audio sin un gesto previo del
  // usuario: el primer clic (login, menú, etc.) crea/reanuda el contexto.
  private desbloquearAudio = () => {
    try {
      this.audioCtx ??= new AudioContext();
      if (this.audioCtx.state === 'suspended') void this.audioCtx.resume();
    } catch { }
  };

  constructor(
    private router: Router,
    private authService: AuthService,
    private transporteService: TransporteService,
    private pushService: PushService,
    private dexie: DexieService,
    private alertService: AlertService
  ) { }

  async ngOnInit() {
    this.usuario = await this.authService.getUser();
    const rol = this.usuario?.idrol ?? '';
    void this.pushService.activar(this.usuario?.idUsuario);

    const esSupervisor = rol === 'SPTRANS' || rol === 'ADTRANS';
    const esCoordinador = rol === 'COTRANS' || rol === 'ADTRANS';
    const esConductor = rol === 'CHTRANS' || rol === 'ADTRANS';
    const esAdmin = rol === 'ADTRANS' || rol === 'COTRANS';

    this.isOnline = navigator.onLine;
    window.addEventListener('online', this.onOnline);
    window.addEventListener('offline', this.onOffline);
    document.addEventListener('click', this.desbloquearAudio);

    await this.actualizarEstado();
    this.actualizador = setInterval(() => void this.actualizarEstado(), 30000);

    this.menu = [
      { label: 'Solicitudes', icon: 'bx-list-ul', route: '/main/solicitudes', seccion: 'Procesos', visible: esSupervisor },
      { label: 'Coordinación', icon: 'bx-git-branch', route: '/main/coordinador', seccion: 'Procesos', visible: esCoordinador },
      // Órdenes de servicio: oculto mientras la flota sea 100% propia
      // (las OS solo aplican a unidades de terceros). El módulo completo
      // (componente, servicio, SP y endpoints) se conserva para reactivarlo.
      // { label: 'Órdenes de servicio', icon: 'bx-file', route: '/main/ordenes-servicio', seccion: 'Procesos', visible: esCoordinador },
      { label: 'Mis servicios', icon: 'bxs-truck', route: '/main/conductor', seccion: 'Procesos', visible: esConductor },
      { label: 'Dashboard', icon: 'bxs-dashboard', route: '/main/dashboard', seccion: 'Reportes', visible: esAdmin },
      { label: 'Reportes', icon: 'bx-bar-chart', route: '/main/reportes', seccion: 'Reportes', visible: esAdmin },
      { label: 'Administración', icon: 'bx-cog', route: '/main/administracion', seccion: 'Configuración', visible: esAdmin }
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
      void this.avisarAsignaciones(lista);
    } catch { }
    await this.revisarComunicadoVigente();
  }

  // El primer comunicado cuyo rango horario está vigente ahora mismo
  get comunicadoVigente(): any | undefined {
    return this.comunicados.find(c => c.vigente === 1 || c.vigente === true);
  }

  // Ni bien ingresa (y en cada ciclo de 30 s) se consulta si hay un comunicado
  // vigente: si aparece uno nuevo, el modal bloqueante se abre una sola vez
  // por comunicado y por sesión
  private async revisarComunicadoVigente() {
    try { this.comunicados = await this.transporteService.comunicadosActivos(); }
    catch { return; }
    const c = this.comunicadoVigente;
    if (!c) { this.mostrarComunicado = false; return; }
    if (sessionStorage.getItem('comunicadoVisto') !== String(c.idComunicado)) {
      this.mostrarComunicado = true;
      sessionStorage.setItem('comunicadoVisto', String(c.idComunicado));
    }
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
      const alertable = n.tipo !== 'ASIGNACION' || this.esDeHoy(n.fechaServicio);
      if (!n.leida && !this.idsNotificados.has(n.idNotificacion) && !this.primeraCargaNotificaciones && alertable) {
        new Notification(n.titulo, { body: n.mensaje, icon: 'favicon.svg' });
      }
      this.idsNotificados.add(n.idNotificacion);
    }
    this.primeraCargaNotificaciones = false;
  }

  // Alerta al conductor solo cuando el servicio asignado es del día:
  // fechaServicio la graba el SP al asignar (NULL = notificación vieja).
  private async avisarAsignaciones(lista: any[]) {
    if (this.usuario?.idrol !== 'CHTRANS') return;
    const nuevas = lista.filter(n => n.tipo === 'ASIGNACION' && !n.leida
      && !this.asignacionesAvisadas.has(n.idNotificacion) && this.esDeHoy(n.fechaServicio));
    lista.forEach(n => this.asignacionesAvisadas.add(n.idNotificacion));
    if (!nuevas.length) return;
    this.sonarAsignacion();
    navigator.vibrate?.([300, 120, 300]);
    this.transporteService.nuevasAsignaciones$.next();
    const ir = await this.alertService.confirm(
      nuevas.length === 1 ? 'Te han asignado un viaje' : 'Te han asignado nuevos viajes',
      nuevas.map(n => n.mensaje).join('\n\n'));
    if (ir) void this.router.navigate(['/main/conductor']);
  }

  private esDeHoy(fecha?: string): boolean {
    if (!fecha) return false;
    const hoy = new Date();
    const p = (n: number) => String(n).padStart(2, '0');
    return fecha.substring(0, 10) === `${hoy.getFullYear()}-${p(hoy.getMonth() + 1)}-${p(hoy.getDate())}`;
  }

  // Triple beep con WebAudio (sin archivos de audio)
  private sonarAsignacion() {
    try {
      this.desbloquearAudio();
      const ctx = this.audioCtx;
      if (!ctx || ctx.state !== 'running') return;
      const t0 = ctx.currentTime;
      [0, 0.22, 0.44].forEach((inicio, i) => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.type = 'sine';
        osc.frequency.value = i === 2 ? 1175 : 880;
        gain.gain.setValueAtTime(0.0001, t0 + inicio);
        gain.gain.exponentialRampToValueAtTime(0.4, t0 + inicio + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.0001, t0 + inicio + 0.18);
        osc.connect(gain).connect(ctx.destination);
        osc.start(t0 + inicio);
        osc.stop(t0 + inicio + 0.2);
      });
    } catch { }
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
    document.removeEventListener('click', this.desbloquearAudio);
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
    await this.pushService.desactivar();
    await this.authService.logout();
  }
}
