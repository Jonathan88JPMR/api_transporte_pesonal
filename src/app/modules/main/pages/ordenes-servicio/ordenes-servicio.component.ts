import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { TableModule } from 'primeng/table';
import { TagModule } from 'primeng/tag';
import { TooltipModule } from 'primeng/tooltip';
import { TransporteService } from '../../services/transporte.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';

@Component({
  selector: 'app-ordenes-servicio',
  standalone: true,
  imports: [CommonModule, FormsModule, TableModule, TagModule, TooltipModule],
  templateUrl: './ordenes-servicio.component.html',
  styleUrl: './ordenes-servicio.component.scss'
})
/* Flujo de la Orden de Servicio (OS) de transporte:
   1. El conductor marca sus servicios como REALIZADO (traslados ejecutados).
   2. Previsualizar OS: el servidor agrupa los traslados realizados del período
      por transportista, les aplica tarifa y propone la distribución del costo
      (TAREO del ERP por supervisor, o por área con ceco elegible).
   3. Confirmar y generar: persiste TP_ORDENES_SERVICIO + detalle + traslados
      incluidos. Obligatorio: ceco+cuenta+proyecto en cada fila y un DNI
      firmante (el supervisor que hizo las solicitudes).
   4. Migrar: el API envía el payloadEnvio a logística (ingresar-transporte),
      que luego sincroniza a SPRING con su propio flujo de aprobación.
   5. Estado SPRING: consulta a logística el numeroOrdenSpring de cada OS
      migrada y lo muestra en la columna "N° SPRING". */
export class OrdenesServicioComponent implements OnInit {
  desde?: string;
  hasta?: string;
  ordenes: any[] = [];
  // Traslados que no entrarán a la OS: sin transportista en la unidad o sin tarifa
  excluidos: any[] = [];
  expandidas = new Set<number>();
  generando = false;
  migrando = false;
  consultandoSpring = false;
  // Previa: lo que se generaría, con el ceco elegible por fila antes de confirmar
  previaOrdenes: any[] | null = null;
  // Catálogo TP_CECOS para el select de las filas en modo AREA
  cecos: any[] = [];

  constructor(private service: TransporteService, private alerts: AlertService) { }

  async ngOnInit() {
    const hoy = new Date();
    this.desde = this.toIso(new Date(hoy.getFullYear(), hoy.getMonth(), 1));
    this.hasta = this.toIso(hoy);
    await Promise.all([this.cargar(), this.cargarCecos()]);
  }

  toIso(d: Date) { return d.toISOString().slice(0, 10); }

  // Lista las OS ya persistidas en el rango (GENERADA / MIGRADA / ERROR)
  async cargar() {
    try {
      this.ordenes = await this.service.listarOS({ desde: this.desde, hasta: this.hasta });
    } catch (e) {
      this.alerts.showAlert('error', this.mensajeError(e, 'No se pudo listar las órdenes de servicio'), 'Error');
    }
  }

  async cargarCecos() {
    try { this.cecos = (await this.service.administrarCatalogo('CECO', 'LISTAR')).filter(c => c.activo !== false); } catch { }
  }

  // PASO 1 — Previa: llama al SP con previa=1 (calcula sin grabar).
  // Devuelve una OS por transportista con modoCeco:
  //   TAREO → detalle ya completo desde el tareo del ERP (solo lectura)
  //   AREA  → detalle por área donde el coordinador elige el ceco (obligatorio)
  async previsualizar() {
    if (!this.desde || !this.hasta) {
      this.alerts.showAlert('warning', 'Seleccione el rango de fechas', 'Aviso');
      return;
    }
    this.generando = true;
    try {
      const resp = await this.service.generarOS(this.desde, this.hasta, undefined, true);
      const ordenes = resp?.ordenes ?? [];
      this.excluidos = resp?.excluidos ?? [];
      if (ordenes.length === 0) {
        this.previaOrdenes = null;
        this.alerts.showAlert('info', 'No hay traslados realizados pendientes de facturar en el período', 'Sin datos');
        return;
      }
      // cada fila del detalle arranca con el ceco que resolvió el servidor (el del área);
      // en modo TAREO idCecoSel queda null porque no hay select, el dato ya viene del ERP
      for (const o of ordenes) for (const d of (o.detalle ?? [])) d.idCecoSel = d.idCeco ?? null;
      this.previaOrdenes = ordenes;
    } catch (e) {
      this.alerts.showAlert('error', this.mensajeError(e, 'No se pudo generar la previa'), 'Error');
    } finally {
      this.generando = false;
    }
  }

  cancelarPrevia() { this.previaOrdenes = null; }

  // Toda fila debe tener un ceco que además traiga cuenta y proyecto.
  // Las filas TAREO ya vienen completas del ERP; solo las de AREA son seleccionables.
  filasIncompletas(): { transportista: string; area: string }[] {
    if (!this.previaOrdenes) return [];
    return this.previaOrdenes.flatMap(o => (o.detalle ?? [])
      .filter((d: any) => {
        if (d.origen === 'TAREO') return !(d.ceco && d.cuenta && d.idproyecto);
        const c = this.cecoDe(d.idCecoSel);
        return !d.idCecoSel || !c?.cuenta || !c?.idproyecto;
      })
      .map((d: any) => ({ transportista: o.nombreTransportista, area: d.area ?? 'Sin área' })));
  }

  // PASO 2 — Generar: confirma la previa. Envía los cecos elegidos (modo AREA)
  // como overrides; el SP valida de nuevo que ninguna fila quede sin
  // ceco/cuenta/proyecto y que exista un DNI firmante, luego graba todo.
  async generar() {
    if (!this.desde || !this.hasta) {
      this.alerts.showAlert('warning', 'Seleccione el rango de fechas', 'Aviso');
      return;
    }
    const faltantes = this.filasIncompletas();
    if (faltantes.length > 0) {
      this.alerts.showAlert('warning',
        'Toda fila debe tener centro de costo, cuenta y proyecto. Revise: ' +
        faltantes.map(f => `${f.area} (${f.transportista})`).join(', '), 'Datos incompletos');
      return;
    }
    if (!await this.alerts.confirm('Generar órdenes de servicio',
      `Se crearán ${this.previaOrdenes?.length ?? 0} orden(es) con los centros de costo elegidos. ¿Continuar?`)) return;
    this.generando = true;
    try {
      // cecos elegidos en la previa → overrides por (transportista, área)
      const detalle = this.previaOrdenes
        ? this.previaOrdenes.flatMap(o => (o.detalle ?? [])
            .filter((d: any) => d.idCecoSel)
            .map((d: any) => ({ idTransportista: o.idTransportista, idArea: d.idArea, idCeco: d.idCecoSel })))
        : undefined;
      const resp = await this.service.generarOS(this.desde, this.hasta, detalle);
      const creadas = resp?.ordenes ?? [];
      this.excluidos = resp?.excluidos ?? [];
      this.previaOrdenes = null;
      if (creadas.length === 0) {
        this.alerts.showAlert('info', 'No se encontraron traslados realizados pendientes de facturar en el período', 'Sin datos');
      } else {
        this.alerts.showAlert('success', `Se generaron ${creadas.length} orden(es) de servicio`, 'OS generadas');
      }
      await this.cargar();
    } catch (e) {
      this.alerts.showAlert('error', this.mensajeError(e, 'No se pudieron generar las órdenes'), 'Error');
    } finally {
      this.generando = false;
    }
  }

  cecoDe(idCeco: number | null) { return this.cecos.find(c => c.idCeco === idCeco); }

  // PASO 3 — Migrar: envía el payloadEnvio de cada OS a logística
  // (orden-servicio/ingresar-transporte). Con os va una sola (reintento si
  // está en ERROR); sin os van todas las GENERADA/ERROR. "MIGRADA" significa
  // que ya está en logística — la migración a SPRING es responsabilidad de allá.
  async migrar(os?: any) {
    const texto = os
      ? `¿Migrar la OS #${os.idOS} de ${os.nombreTransportista} a logística?`
      : '¿Migrar todas las OS pendientes (GENERADA/ERROR) a logística?';
    if (!await this.alerts.confirm('Migrar a logística', texto)) return;
    this.migrando = true;
    try {
      const resp = await this.service.migrarOS(os?.idOS);
      const resultados = resp?.resultados ?? [];
      const ok = resultados.filter((r: any) => r.ok).length;
      const fallidas = resultados.filter((r: any) => !r.ok);
      if (ok > 0 && fallidas.length === 0) {
        this.alerts.showAlert('success', `${ok} orden(es) migradas correctamente`, 'Migradas');
      } else if (ok === 0 && resultados.length === 0) {
        this.alerts.showAlert('info', resp?.mensaje ?? 'No hay OS pendientes', 'Aviso');
      } else {
        this.alerts.showAlert('warning',
          `${ok} migrada(s), ${fallidas.length} fallida(s).\n${fallidas.map((f: any) => `OS #${f.idOS}: ${f.error}`).join('\n')}`,
          'Resultado parcial');
      }
      await this.cargar();
    } catch (e) {
      this.alerts.showAlert('error', this.mensajeError(e, 'No se pudo migrar'), 'Error');
    } finally {
      this.migrando = false;
    }
  }

  // PASO 4 — Estado SPRING: consulta a logística (orden-servicio/obtener-por-id)
  // por el numeroOSExterno de cada OS migrada y guarda numeroOSSpring +
  // estadoLogistica. Se puede repetir hasta que la OS quede sincronizada.
  async consultarSpring(os?: any) {
    const texto = os
      ? `¿Consultar en logística el estado de la OS #${os.idOS} (${os.numeroOSExterno})?`
      : '¿Consultar en logística el estado de todas las OS migradas?';
    if (!await this.alerts.confirm('Estado en logística/SPRING', texto)) return;
    this.consultandoSpring = true;
    try {
      const resp = await this.service.consultarEstadoSpring(os?.idOS);
      const resultados = resp?.resultados ?? [];
      const enSpring = resultados.filter((r: any) => r.numeroOSSpring);
      const conError = resultados.filter((r: any) => r.error);
      if (resultados.length === 0) {
        this.alerts.showAlert('info', resp?.mensaje ?? 'No hay OS migradas para consultar', 'Aviso');
      } else {
        const lineas = resultados.map((r: any) =>
          `OS #${r.idOS} (${r.numeroOS}): ${r.numeroOSSpring ? `SPRING ${r.numeroOSSpring}` : r.estadoLogistica ?? 'sin estado'}${r.error ? ` — ${r.error}` : ''}`);
        this.alerts.showAlert(enSpring.length ? 'success' : 'info',
          `${enSpring.length}/${resultados.length} ya en SPRING.\n${lineas.join('\n')}${conError.length ? `\n${conError.length} con error de consulta` : ''}`,
          'Estado consultado');
      }
      await this.cargar();
    } catch (e) {
      this.alerts.showAlert('error', this.mensajeError(e, 'No se pudo consultar el estado'), 'Error');
    } finally {
      this.consultandoSpring = false;
    }
  }

  toggle(idOS: number) {
    this.expandidas.has(idOS) ? this.expandidas.delete(idOS) : this.expandidas.add(idOS);
  }

  estadoTag(estado: string): { texto: string; sev: 'success' | 'warn' | 'danger' | 'secondary' } {
    switch (estado) {
      case 'MIGRADA': return { texto: 'MIGRADA', sev: 'success' };
      case 'ERROR': return { texto: 'ERROR', sev: 'danger' };
      default: return { texto: estado ?? 'GENERADA', sev: 'warn' };
    }
  }

  get pendientes(): number {
    return this.ordenes.filter(o => o.estado === 'GENERADA' || o.estado === 'ERROR').length;
  }

  get migradas(): number {
    return this.ordenes.filter(o => o.estado === 'MIGRADA' && o.numeroOSExterno).length;
  }

  private mensajeError(e: any, fallback: string): string {
    return e?.error?.mensaje ?? e?.mensaje ?? fallback;
  }
}
