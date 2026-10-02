import { AfterViewInit, Component, ElementRef, Input, OnChanges, OnDestroy, ViewChild } from '@angular/core';
import { CommonModule } from '@angular/common';
import * as L from 'leaflet';

export interface PuntoMapa {
  latitud: number;
  longitud: number;
  etiqueta?: string;
}

@Component({
  selector: 'app-mapa',
  standalone: true,
  imports: [CommonModule],
  template: '<div #contenedor class="mapa-contenedor"></div>',
  styles: [`
    .mapa-contenedor {
      height: 320px;
      width: 100%;
      border-radius: 8px;
      border: 1px solid #ddd;
      z-index: 0;
    }
  `]
})
export class MapaComponent implements AfterViewInit, OnChanges, OnDestroy {

  @ViewChild('contenedor', { static: true }) contenedor!: ElementRef<HTMLDivElement>;
  @Input() puntos: PuntoMapa[] = [];
  @Input() origen?: PuntoMapa;
  @Input() trazarRuta = true;

  private mapa?: L.Map;
  private capa?: L.LayerGroup;
  private observador?: ResizeObserver;

  ngAfterViewInit() {
    this.mapa = L.map(this.contenedor.nativeElement);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap',
      maxZoom: 19
    }).addTo(this.mapa);

    this.observador = new ResizeObserver(() => {
      this.mapa?.invalidateSize();
      this.encuadrar();
    });
    this.observador.observe(this.contenedor.nativeElement);
    setTimeout(() => this.mapa?.invalidateSize(), 100);
    void this.render();
  }

  ngOnChanges() { void this.render(); }

  ngOnDestroy() {
    this.observador?.disconnect();
    this.mapa?.remove();
  }

  private encuadre?: L.LatLngBounds;
  private renderSeq = 0;

  private encuadrar() {
    if (this.mapa && this.encuadre) this.mapa.fitBounds(this.encuadre.pad(0.15));
  }

  private async render() {
    if (!this.mapa) return;
    // Token de render: si llega uno nuevo mientras esperamos la ruta OSRM,
    // esta capa queda obsoleta y se descarta (evita que se "pegue" el mapa anterior)
    const seq = ++this.renderSeq;
    this.capa?.remove();
    const capa = L.layerGroup().addTo(this.mapa);
    this.capa = capa;

    const paradas = this.puntos.filter(p => p.latitud != null && p.longitud != null);
    const bounds: L.LatLngExpression[] = [];

    if (this.origen) {
      L.circleMarker([this.origen.latitud, this.origen.longitud], {
        radius: 8, color: '#1565c0', fillColor: '#1565c0', fillOpacity: 0.9
      }).bindTooltip(this.origen.etiqueta ?? 'Ubicación actual').addTo(capa);
      bounds.push([this.origen.latitud, this.origen.longitud]);
    }

    paradas.forEach((p, i) => {
      L.circleMarker([p.latitud, p.longitud], {
        radius: 7, color: '#238664', fillColor: '#238664', fillOpacity: 0.9
      }).bindTooltip(`${i + 1}. ${p.etiqueta ?? 'Parada'}`).addTo(capa);
      bounds.push([p.latitud, p.longitud]);
    });

    const secuencia = [...(this.origen ? [this.origen] : []), ...paradas];
    const coords = (this.trazarRuta && secuencia.length >= 2)
      ? await this.rutaOsrm(secuencia)
      : [];

    if (seq !== this.renderSeq) { capa.remove(); return; }

    if (coords.length) {
      L.polyline(coords, { color: '#238664', weight: 4, opacity: 0.7 }).addTo(capa);
    }

    if (bounds.length) {
      this.encuadre = L.latLngBounds(bounds);
      this.mapa.fitBounds(this.encuadre.pad(0.15));
    } else {
      this.mapa.setView([-8.5410, -78.6580], 15);
    }
  }

  private async rutaOsrm(secuencia: PuntoMapa[]): Promise<L.LatLngExpression[]> {
    try {
      const coords = secuencia.map(p => `${p.longitud},${p.latitud}`).join(';');
      const respuesta = await fetch(`https://router.project-osrm.org/route/v1/driving/${coords}?overview=full&geometries=geojson`);
      const datos = await respuesta.json();
      const geometria = datos?.routes?.[0]?.geometry?.coordinates as [number, number][] | undefined;
      if (geometria?.length) return geometria.map(([lon, lat]) => [lat, lon]);
    } catch { }
    return secuencia.map(p => [p.latitud, p.longitud] as L.LatLngExpression);
  }
}
