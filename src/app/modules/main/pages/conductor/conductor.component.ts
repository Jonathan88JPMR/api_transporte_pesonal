import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TableModule } from 'primeng/table';
import { TagModule } from 'primeng/tag';
import { ButtonModule } from 'primeng/button';
import { TooltipModule } from 'primeng/tooltip';
import { TransporteService } from '../../services/transporte.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';
import { AuthService } from '@/app/modules/auth/services/auth.service';
import { Parada, Punto, Solicitud, Unidad, Usuario } from '@/app/models/transporte.models';
import { MapaComponent, PuntoMapa } from '@/app/shared/mapa/mapa.component';

@Component({
  selector: 'app-conductor',
  standalone: true,
  imports: [CommonModule, FormsModule, TableModule, TagModule, ButtonModule, TooltipModule, MapaComponent],
  templateUrl: './conductor.component.html',
  styleUrl: './conductor.component.scss'
})
export class ConductorComponent implements OnInit {

  servicios: Solicitud[] = [];
  usuario?: Usuario;
  puntos: Punto[] = [];
  unidades: Unidad[] = [];
  ubicacionActual?: { latitud: number; longitud: number };
  servicioMapa?: Solicitud;
  puntosMapaSel: PuntoMapa[] = [];
  origenMapa?: PuntoMapa;
  servicioPasajeros?: Solicitud;
  pasajerosExtra = 1;
  cargando = false;

  constructor(
    private transporteService: TransporteService,
    private alertService: AlertService,
    private authService: AuthService
  ) { }

  async ngOnInit() {
    this.usuario = await this.authService.getUser();
    try {
      [this.puntos, this.unidades] = await Promise.all([
        this.transporteService.listarPuntos(),
        this.transporteService.listarUnidades()
      ]);
    } catch { this.puntos = []; this.unidades = []; }
    this.obtenerUbicacion();
    await this.cargar();
  }

  async cargar() {
    if (!this.usuario?.placa) {
      this.alertService.showAlert('warning', 'Este usuario no tiene una unidad asignada', 'Atención');
      return;
    }
    this.cargando = true;
    try {
      this.servicios = await this.transporteService.serviciosConductor(this.usuario.placa);
    } catch {
      this.alertService.showAlert('error', 'No se pudieron cargar los servicios', 'Error');
    } finally {
      this.cargando = false;
    }
  }

  async cambiarEstado(s: Solicitud, estado: 'ASIGNADO' | 'EN_RUTA' | 'REALIZADO') {
    try {
      await this.transporteService.cambiarEstado(s.idSolicitud, estado, s.idSolicitudUnidad, this.usuario?.usuario);
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No se pudo actualizar el servicio', 'Error');
    }
  }

  obtenerUbicacion() {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(pos => {
      this.ubicacionActual = { latitud: pos.coords.latitude, longitud: pos.coords.longitude };
      this.origenMapa = { ...this.ubicacionActual, etiqueta: 'Mi ubicación' };
    });
  }

  verMapa(s: Solicitud) {
    const puntos = this.puntosMapaServicio(s);
    if (!puntos.length) {
      this.alertService.showAlert('warning', 'La ruta no tiene puntos con coordenadas registradas', 'Atención');
      return;
    }
    if (this.servicioMapa?.idSolicitud === s.idSolicitud) {
      this.servicioMapa = undefined;
      this.puntosMapaSel = [];
      return;
    }
    this.puntosMapaSel = puntos;
    this.servicioMapa = s;
  }

  get paradasMapa(): Parada[] {
    return this.servicioMapa?.paradas ?? [];
  }

  puntosMapaServicio(s: Solicitud): PuntoMapa[] {
    // RF-023: si el traslado tiene paradas definidas, el mapa sigue ese orden
    const nombres = s.paradas?.length ? s.paradas.map(p => p.punto) : [s.puntoPartida, s.puntoLlegada];
    return nombres
      .map(n => this.puntos.find(p => p.nombre === n))
      .filter(p => p?.latitud != null && p?.longitud != null)
      .map(p => ({ latitud: p!.latitud!, longitud: p!.longitud!, etiqueta: p!.nombre }));
  }

  // Cupo del viaje: ocupación de la unidad en los servicios activos del día
  cupoServicio(s: Solicitud): { ocupada: number; libre: number; capacidad: number } | null {
    const unidad = this.unidades.find(u => u.placa === this.usuario?.placa);
    if (!unidad) return null;
    const ocupada = this.servicios
      .filter(x => x.fechaProgramada === s.fechaProgramada && (x.estado === 'ASIGNADO' || x.estado === 'EN_RUTA'))
      .reduce((a, x) => a + (x.cantidad ?? 0), 0);
    return { ocupada, libre: unidad.capacidad - ocupada, capacidad: unidad.capacidad };
  }

  severidadCupo(s: Solicitud): 'success' | 'warn' | 'danger' {
    const c = this.cupoServicio(s);
    if (!c) return 'success';
    return c.libre <= 0 ? 'danger' : c.libre <= c.capacidad * 0.25 ? 'warn' : 'success';
  }

  // RF-024: el conductor registra pasajeros extra de emergencia si hay cupo
  abrirPasajeros(s: Solicitud) {
    this.servicioPasajeros = s;
    this.pasajerosExtra = 1;
  }

  async guardarPasajeros() {
    const s = this.servicioPasajeros;
    if (!s || this.pasajerosExtra < 1) return;
    const cupo = this.cupoServicio(s);
    if (cupo && this.pasajerosExtra > cupo.libre) {
      this.alertService.showAlert('warning', `La unidad solo tiene ${cupo.libre} asientos libres`, 'Sin cupo');
      return;
    }
    try {
      await this.transporteService.agregarPasajeros(s.idSolicitud, this.pasajerosExtra, s.idSolicitudUnidad);
      this.servicioPasajeros = undefined;
      await this.cargar();
    } catch {
      this.alertService.showAlert('error', 'No hay cupo suficiente en la unidad', 'Error');
    }
  }

  mapaUrl(s: Solicitud): string | null {
    const destino = this.puntos.find(p => p.nombre === s.puntoLlegada && p.latitud != null && p.longitud != null);
    if (!destino) return null;
    const origen = this.ubicacionActual;
    if (origen) return `https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=${origen.latitud},${origen.longitud};${destino.latitud},${destino.longitud}`;
    return `https://www.openstreetmap.org/?mlat=${destino.latitud}&mlon=${destino.longitud}#map=16/${destino.latitud}/${destino.longitud}`;
  }

  // Ruta del día: secuencia de puntos partida + última llegada
  get rutaDelDia(): string {
    if (!this.servicios.length) return '';
    const puntos = this.servicios
      .filter(s => !s.realizado && s.estado !== 'ANULADO')
      .map(s => s.puntoPartida);
    const ultimaLlegada = this.servicios[this.servicios.length - 1]?.puntoLlegada;
    if (ultimaLlegada) puntos.push(ultimaLlegada);
    return puntos.join(' > ');
  }
}
