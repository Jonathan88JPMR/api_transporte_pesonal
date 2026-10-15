import { CommonModule } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TableModule } from 'primeng/table';
import { TagModule } from 'primeng/tag';
import { TooltipModule } from 'primeng/tooltip';
import { TransporteService } from '../../services/transporte.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';
import { Auditoria } from '@/app/models/transporte.models';

@Component({
  selector: 'app-administracion',
  standalone: true,
  imports: [CommonModule, FormsModule, TableModule, TagModule, TooltipModule],
  templateUrl: './administracion.component.html',
  styleUrl: './administracion.component.scss'
})

export class AdministracionComponent implements OnInit {
  // Tabs ocultos por ahora (flota 100% propia): TRANSPORTISTA, TARIFA y CECO
  // son catálogos del flujo de OS con terceros. El código del mantenedor se
  // conserva (formulario, columnas y SP) por si vuelven unidades de terceros.
  private todasLasEntidades = [{ valor: 'USUARIO', etiqueta: 'Usuarios', icon: 'bx-user' }, { valor: 'CONDUCTOR', etiqueta: 'Conductores', icon: 'bx-id-card' }, { valor: 'UNIDAD', etiqueta: 'Unidades', icon: 'bx-bus' }, { valor: 'TIPO_VEHICULO', etiqueta: 'Tipos vehículo', icon: 'bx-car' }, { valor: 'PUNTO', etiqueta: 'Puntos', icon: 'bx-map-pin' }, { valor: 'MOTIVO', etiqueta: 'Motivos', icon: 'bx-list-check' }, { valor: 'AREA', etiqueta: 'Áreas', icon: 'bx-buildings' }, /*{ valor: 'TRANSPORTISTA', etiqueta: 'Transportistas', icon: 'bx-briefcase' }, { valor: 'TARIFA', etiqueta: 'Tarifas', icon: 'bx-dollar-circle' }, { valor: 'CECO', etiqueta: 'Centros de costo', icon: 'bx-target-lock' },*/ { valor: 'COMUNICADO', etiqueta: 'Comunicados', icon: 'bx-megaphone' }, { valor: 'AUDITORIA', etiqueta: 'Auditoría', icon: 'bx-history' }];
  entidades: { valor: string; etiqueta: string; icon: string }[] = [];
  entidad: 'USUARIO' | 'CONDUCTOR' | 'UNIDAD' | 'PUNTO' | 'MOTIVO' | 'AREA' | 'TRANSPORTISTA' | 'TARIFA' | 'CECO' | 'COMUNICADO' | 'AUDITORIA' | 'TIPO_VEHICULO' = 'USUARIO';
  registros: any[] = [];
  registrosTodos: any[] = [];
  auditoria: Auditoria[] = [];
  areas: { idArea: number; nombre: string }[] = [];
  transportistas: { idTransportista: number; razonSocial: string; ruc: string }[] = [];
  conductores: { idUsuario: number; nombre: string }[] = [];
  unidades: { placa: string }[] = [];
  tiposVehiculo: { idTipoVehiculo: number; nombre: string }[] = [];
  form: any = {};
  verEliminados = false;
  rolActual = '';
  roles: Record<string, string> = { SPTRANS: 'Supervisor', COTRANS: 'Coordinador', CHTRANS: 'Conductor', ADTRANS: 'Administrador' };
  estadoOp: Record<string, string> = { OPERATIVA: 'Operativa', MANTENIMIENTO: 'Mantenimiento', FUERA_SERVICIO: 'Fuera de servicio' };
  rolesForm: { valor: string; etiqueta: string }[] = [];

  constructor(private service: TransporteService, private alerts: AlertService) {}

  get esCoordinador(): boolean { return this.rolActual === 'COTRANS'; }

  async ngOnInit() {
    try { this.rolActual = JSON.parse(localStorage.getItem('usuario') ?? '{}').idrol ?? ''; } catch { }
    // el coordinador mantiene usuarios, conductores, áreas, unidades (incluye
    // asignar el conductor de cada unidad), puntos de ruta y comunicados
    this.entidades = this.esCoordinador
      ? this.todasLasEntidades.filter(e => ['USUARIO', 'CONDUCTOR', 'AREA', 'UNIDAD', 'TIPO_VEHICULO', 'PUNTO', 'COMUNICADO'].includes(e.valor))
      : this.todasLasEntidades;
    this.rolesForm = this.esCoordinador
      ? [{ valor: 'SPTRANS', etiqueta: 'Supervisor' }]
      : [{ valor: 'SPTRANS', etiqueta: 'Supervisor' }, { valor: 'COTRANS', etiqueta: 'Coordinador' }, { valor: 'ADTRANS', etiqueta: 'Administrador' }];
    await Promise.all([this.cargar(), this.cargarAreas(), this.cargarTransportistas(), this.cargarConductores(), this.cargarUnidades(), this.cargarTiposVehiculo()]);
  }
  async cambiarEntidad(entidad: any) { this.entidad = entidad; this.limpiar(); await this.cargar(); }
  entidadApi(): 'USUARIO' | 'UNIDAD' | 'PUNTO' | 'MOTIVO' | 'AREA' | 'TRANSPORTISTA' | 'TARIFA' | 'CECO' | 'TIPO_VEHICULO' { return (this.entidad === 'CONDUCTOR' || this.entidad === 'AUDITORIA' || this.entidad === 'COMUNICADO') ? 'USUARIO' : this.entidad; }
  esUsuario(): boolean { return this.entidad === 'USUARIO' || this.entidad === 'CONDUCTOR'; }
  // el coordinador solo puede tocar conductores y supervisores (el SP también lo valida)
  puedeGestionar(r: any): boolean { return !this.esCoordinador || r.idrol === 'CHTRANS' || r.idrol === 'SPTRANS' || r.idrol === undefined; }
  estadoRegistro(r: any): { texto: string; severidad: 'success' | 'warn' | 'danger' | 'secondary' } {
    if (r.eliminado) return { texto: 'ELIMINADO', severidad: 'danger' };
    return r.activo === false ? { texto: 'INACTIVO', severidad: 'secondary' } : { texto: 'ACTIVO', severidad: 'success' };
  }
  async cargarAreas() { try { this.areas = (await this.service.administrarCatalogo('AREA', 'LISTAR')).filter(a => a.activo !== false); } catch { } }
  async cargarTransportistas() { try { this.transportistas = (await this.service.administrarCatalogo('TRANSPORTISTA', 'LISTAR')).filter(t => t.activo !== false); } catch { } }
  async cargarConductores() { try { this.conductores = (await this.service.administrarCatalogo('USUARIO', 'LISTAR')).filter(u => u.idrol === 'CHTRANS' && u.activo !== false && !u.eliminado); } catch { } }
  async cargarUnidades() { try { this.unidades = (await this.service.administrarCatalogo('UNIDAD', 'LISTAR')).filter(u => u.activo !== false); } catch { } }
  // catálogo que alimenta el select "Tipo de vehículo" del mantenedor de unidades
  async cargarTiposVehiculo() { try { this.tiposVehiculo = (await this.service.administrarCatalogo('TIPO_VEHICULO', 'LISTAR')).filter(t => t.activo !== false); } catch { } }
  async cargar() {
    if (this.entidad === 'AUDITORIA') { this.auditoria = await this.service.listarAuditoria(); return; }
    if (this.entidad === 'COMUNICADO') { this.registrosTodos = await this.service.listarComunicados(); this.aplicarFiltros(); return; }
    const datos = await this.service.administrarCatalogo(this.entidadApi(), 'LISTAR');
    this.registrosTodos = this.entidad === 'USUARIO' ? datos.filter(r => r.idrol !== 'CHTRANS')
      : this.entidad === 'CONDUCTOR' ? datos.filter(r => r.idrol === 'CHTRANS') : datos;
    this.aplicarFiltros();
  }
  aplicarFiltros() {
    this.registros = this.verEliminados ? this.registrosTodos : this.registrosTodos.filter(r => !r.eliminado);
  }
  limpiar() {
    this.form = this.entidad === 'UNIDAD' ? { capacidad: 15, tipoPropiedad: 'PROPIA', estadoOperativo: 'OPERATIVA' }
      : this.entidad === 'COMUNICADO' ? { fecha: new Date().toISOString().slice(0, 10) }
      : this.entidad === 'USUARIO' ? { idrol: 'SPTRANS' }
      : this.entidad === 'CONDUCTOR' ? { idrol: 'CHTRANS' } : {};
  }
  columnas(): { etiqueta: string; campo: string }[] {
    switch (this.entidad) {
      case 'USUARIO': return [{ etiqueta: 'Nombre', campo: 'nombre' }, { etiqueta: 'Usuario', campo: 'usuario' }, { etiqueta: 'DNI', campo: 'dni' }, { etiqueta: 'Rol', campo: 'idrol' }, { etiqueta: 'Área', campo: 'area' }];
      case 'CONDUCTOR': return [{ etiqueta: 'Nombre', campo: 'nombre' }, { etiqueta: 'Usuario', campo: 'usuario' }, { etiqueta: 'DNI', campo: 'dni' }, { etiqueta: 'Placa', campo: 'placa' }, { etiqueta: 'Área', campo: 'area' }];
      case 'UNIDAD': return [{ etiqueta: 'Placa', campo: 'placa' }, { etiqueta: 'Propiedad', campo: 'tipoPropiedad' }, { etiqueta: 'Vehículo', campo: 'tipoVehiculo' }, { etiqueta: 'Capacidad', campo: 'capacidad' }, { etiqueta: 'Conductor', campo: 'conductor' }, { etiqueta: 'Estado', campo: 'estadoOperativo' }/*, { etiqueta: 'Transportista', campo: 'transportista' }*/];
      case 'COMUNICADO': return [{ etiqueta: 'Título', campo: 'titulo' }, { etiqueta: 'Fecha', campo: 'fecha' }, { etiqueta: 'Horario', campo: 'horario' }, { etiqueta: 'Unidades', campo: 'unidades' }, { etiqueta: 'Actividad', campo: 'motivoActividad' }, { etiqueta: 'Vigente', campo: 'vigente' }];
      case 'PUNTO': return [{ etiqueta: 'Nombre', campo: 'nombre' }, { etiqueta: 'Latitud', campo: 'latitud' }, { etiqueta: 'Longitud', campo: 'longitud' }];
      // al coordinador el tab Áreas le muestra solo Nombre + Estado; las
      // columnas contables (ceco/cuenta/proyecto) son exclusivas del admin
      case 'AREA': return this.esCoordinador
        ? [{ etiqueta: 'Nombre', campo: 'nombre' }]
        : [{ etiqueta: 'Nombre', campo: 'nombre' }, { etiqueta: 'CeCo', campo: 'ceco' }, { etiqueta: 'Cuenta', campo: 'cuenta' }, { etiqueta: 'Proyecto', campo: 'idproyecto' }];
      case 'TRANSPORTISTA': return [{ etiqueta: 'RUC', campo: 'ruc' }, { etiqueta: 'Razón social', campo: 'razonSocial' }, { etiqueta: 'Teléfono', campo: 'telefono' }, { etiqueta: 'Email', campo: 'email' }];
      case 'TARIFA': return [{ etiqueta: 'Transportista', campo: 'transportista' }, { etiqueta: 'Origen', campo: 'puntoOrigen' }, { etiqueta: 'Destino', campo: 'puntoDestino' }, { etiqueta: 'Monto', campo: 'monto' }, { etiqueta: 'Tipo', campo: 'porPasajero' }];
      case 'CECO': return [{ etiqueta: 'CeCo', campo: 'ceco' }, { etiqueta: 'Cuenta', campo: 'cuenta' }, { etiqueta: 'Proyecto', campo: 'idproyecto' }, { etiqueta: 'Fundo', campo: 'codfundo' }, { etiqueta: 'Cultivo', campo: 'idcultivo' }, { etiqueta: 'Labor', campo: 'idlabor' }, { etiqueta: 'Descripción', campo: 'descripcion' }];
      default: return [{ etiqueta: 'Nombre', campo: 'nombre' }];
    }
  }
  idRegistro(r: any) { return r.idUsuario ?? r.idUnidad ?? r.idPunto ?? r.idMotivo ?? r.idArea ?? r.idTransportista ?? r.idTarifa ?? r.idCeco ?? r.idComunicado ?? r.idTipoVehiculo; }
  editar(r: any) { this.form = { ...r, id: this.idRegistro(r), clave: '' }; }
  async guardar() {
    const datos = { ...this.form };
    if (this.entidad === 'CONDUCTOR') datos.idrol = 'CHTRANS';
    try {
      if (this.entidad === 'COMUNICADO') await this.service.guardarComunicado(datos);
      else await this.service.administrarCatalogo(this.entidadApi(), 'GUARDAR', datos);
      this.limpiar(); await this.cargar();
    }
    catch (e) { this.alerts.showAlert('warning', this.mensajeError(e, 'No se pudo guardar el registro'), 'Aviso'); }
  }
  async alternarActivo(r: any) {
    const activar = r.activo === false;
    const accion = activar ? 'activar' : 'desactivar';
    if (!await this.alerts.confirm(activar ? 'Activar' : 'Desactivar', `¿Desea ${accion} a ${r.nombre}? ${activar ? 'Podrá iniciar sesión.' : 'No podrá iniciar sesión.'}`)) return;
    try {
      await this.service.administrarCatalogo(this.entidadApi(), 'GUARDAR', { ...r, id: this.idRegistro(r), activo: activar ? 1 : 0 });
      await this.cargar();
    } catch (e) { this.alerts.showAlert('warning', this.mensajeError(e, 'No se pudo cambiar el estado'), 'Aviso'); }
  }
  async eliminar(r: any) {
    const esUsuario = this.esUsuario();
    const texto = esUsuario
      ? `¿Desea eliminar a ${r.nombre}? Es un borrado lógico: no podrá iniciar sesión pero su historial se conserva.`
      : this.entidad === 'COMUNICADO'
        ? `¿Desea desactivar el comunicado "${r.titulo}"? Las solicitudes volverán a admitirse en su rango.`
        : '¿Desea desactivar este registro?';
    if (!await this.alerts.confirm(esUsuario ? 'Eliminar usuario' : 'Desactivar', texto)) return;
    try {
      if (this.entidad === 'COMUNICADO') await this.service.eliminarComunicado(this.idRegistro(r));
      else await this.service.administrarCatalogo(this.entidadApi(), 'ELIMINAR', { id: this.idRegistro(r) });
      await this.cargar();
    } catch (e) { this.alerts.showAlert('warning', this.mensajeError(e, 'No se pudo eliminar'), 'Aviso'); }
  }
  private mensajeError(e: any, fallback: string): string {
    return e?.error?.mensaje ?? e?.mensaje ?? fallback;
  }
}
