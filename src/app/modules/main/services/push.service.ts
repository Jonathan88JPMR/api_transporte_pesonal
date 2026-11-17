import { Injectable } from '@angular/core';
import { SwPush } from '@angular/service-worker';
import { TransporteService } from './transporte.service';

const CLAVE_ENDPOINT = 'pushEndpoint';
const CLAVE_NEGADO = 'pushNegado';

// Suscripción Web Push del dispositivo (Nivel 2): llega la notificación del
// sistema aunque la app esté cerrada. Sin service worker (ng serve) es no-op.
@Injectable({ providedIn: 'root' })
export class PushService {
  constructor(private swPush: SwPush, private transporte: TransporteService) { }

  // Tras el login: pide permiso (una vez), suscribe con la clave VAPID del
  // API y registra el endpoint del dispositivo en la BD.
  async activar(idUsuario?: number) {
    if (!idUsuario || !this.swPush.isEnabled) return;
    if (localStorage.getItem(CLAVE_NEGADO) === '1') return;
    try {
      const vapid = await this.transporte.vapidPublica();
      if (!vapid?.publicKey) return;
      const sub = await this.swPush.requestSubscription({ serverPublicKey: vapid.publicKey });
      await this.transporte.suscribirPush(idUsuario, sub.toJSON());
      localStorage.setItem(CLAVE_ENDPOINT, sub.endpoint);
    } catch {
      // Permiso denegado o navegador sin soporte: no volver a insistir
      localStorage.setItem(CLAVE_NEGADO, '1');
    }
  }

  // Al cerrar sesión: baja el endpoint en el API y desuscribe el navegador
  async desactivar() {
    const endpoint = localStorage.getItem(CLAVE_ENDPOINT);
    localStorage.removeItem(CLAVE_ENDPOINT);
    localStorage.removeItem(CLAVE_NEGADO);
    try {
      if (endpoint) await this.transporte.bajaPush(endpoint);
      if (this.swPush.isEnabled) await this.swPush.unsubscribe();
    } catch { }
  }
}
