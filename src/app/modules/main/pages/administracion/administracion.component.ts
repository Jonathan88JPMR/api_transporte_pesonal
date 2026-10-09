import { CommonModule } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { TableModule } from 'primeng/table';
import { TooltipModule } from 'primeng/tooltip';
import { TransporteService } from '../../services/transporte.service';
import { AlertService } from '@/app/shared/alertas/alerts.service';
import { Auditoria } from '@/app/models/transporte.models';

@Component({
  selector: 'app-administracion',
  standalone: true,
  imports: [CommonModule, FormsModule, TableModule, TooltipModule],
  template: `
    <div class="page-header mb-3"><h5>Administración de transporte</h5></div>
    <ul class="nav custom-tabs mb-3" role="tablist">
      <li class="nav-item" role="presentation" *ngFor="let e of entidades">
        <button class="nav-link" [class.active]="entidad === e.valor" type="button" role="tab" (click)="cambiarEntidad(e.valor)">
          <i class="bx {{ e.icon }}"></i>{{ e.etiqueta }}
        </button>
      </li>
    </ul>
    <div class="card mb-3" *ngIf="entidad !== 'AUDITORIA'"><div class="card-body">
      <div class="row g-2">
        <ng-container *ngIf="entidad === 'USUARIO'">
          <div class="col-md-2"><input class="form-control" [(ngModel)]="form.usuario" placeholder="Usuario" [disabled]="!!form.id" /></div>
          <div class="col-md-2"><input class="form-control" [(ngModel)]="form.nombre" placeholder="Nombre" /></div>
          <div class="col-md-2"><select class="form-select" [(ngModel)]="form.idrol"><option value="SPTRANS">Supervisor</option><option value="COTRANS">Coordinador</option><option value="ADTRANS">Administrador</option></select></div>
          <div class="col-md-2"><select class="form-select" [(ngModel)]="form.idArea"><option [ngValue]="null">Sin área</option><option *ngFor="let a of areas" [ngValue]="a.idArea">{{ a.nombre }}</option></select></div>
          <div class="col-md-2"><input type="password" class="form-control" [(ngModel)]="form.clave" placeholder="Clave" /></div>
        </ng-container>
        <ng-container *ngIf="entidad === 'CONDUCTOR'">
          <div class="col-md-2"><input class="form-control" [(ngModel)]="form.usuario" placeholder="Usuario" [disabled]="!!form.id" /></div>
          <div class="col-md-2"><input class="form-control" [(ngModel)]="form.nombre" placeholder="Nombre" /></div>
          <div class="col-md-2"><input class="form-control" [(ngModel)]="form.placa" placeholder="Placa conductor" /></div>
          <div class="col-md-2"><select class="form-select" [(ngModel)]="form.idArea"><option [ngValue]="null">Sin área</option><option *ngFor="let a of areas" [ngValue]="a.idArea">{{ a.nombre }}</option></select></div>
          <div class="col-md-2"><input type="password" class="form-control" [(ngModel)]="form.clave" placeholder="Clave" /></div>
        </ng-container>
        <ng-container *ngIf="entidad === 'UNIDAD'">
          <div class="col-md-4"><input class="form-control" [(ngModel)]="form.placa" placeholder="Placa" /></div>
          <div class="col-md-4"><input type="number" min="1" class="form-control" [(ngModel)]="form.capacidad" placeholder="Capacidad" /></div>
        </ng-container>
        <ng-container *ngIf="entidad === 'PUNTO' || entidad === 'MOTIVO' || entidad === 'AREA'">
          <div [class.col-md-8]="entidad !== 'PUNTO'" [class.col-md-4]="entidad === 'PUNTO'"><input class="form-control" [(ngModel)]="form.nombre" placeholder="Nombre" /></div>
          <ng-container *ngIf="entidad === 'PUNTO'"><div class="col-md-2"><input type="number" step="0.000001" class="form-control" [(ngModel)]="form.latitud" placeholder="Latitud" /></div><div class="col-md-2"><input type="number" step="0.000001" class="form-control" [(ngModel)]="form.longitud" placeholder="Longitud" /></div></ng-container>
        </ng-container>
        <div class="col-md-2"><button class="btn btn-primary w-100" (click)="guardar()">{{ form.id ? 'Actualizar' : 'Crear' }}</button></div>
        <div class="col-md-2" *ngIf="form.id"><button class="btn btn-outline-secondary w-100" (click)="limpiar()">Cancelar</button></div>
      </div>
    </div></div>
    <p-table *ngIf="entidad !== 'AUDITORIA'" [value]="registros" [paginator]="true" [rows]="10" [rowsPerPageOptions]="[5, 10, 20, 50]"
             [rowHover]="true" [showCurrentPageReport]="true"
             currentPageReportTemplate="Mostrando {first} a {last} de {totalRecords} registros"
             styleClass="p-datatable-sm p-datatable-striped table-mobile-cards">
      <ng-template #header>
        <tr><th>ID</th><th *ngFor="let c of columnas()">{{ c.etiqueta }}</th><th>Estado</th><th>Acciones</th></tr>
      </ng-template>
      <ng-template #body let-r>
        <tr>
          <td data-label="ID">{{ idRegistro(r) }}</td>
          <td *ngFor="let c of columnas()" [attr.data-label]="c.etiqueta">{{ c.campo === 'idrol' ? (roles[r.idrol] || r.idrol) : r[c.campo] }}</td>
          <td data-label="Estado">{{ r.activo === false ? 'INACTIVO' : 'ACTIVO' }}</td>
          <td data-label="Acciones"><div class="d-flex gap-1 align-items-center justify-content-center"><button class="btn btn-sm btn-outline-primary" (click)="editar(r)" pTooltip="Editar" tooltipPosition="top"><i class="pi pi-pencil"></i><span class="accion-label">Editar</span></button><button class="btn btn-sm btn-outline-danger" (click)="eliminar(r)" pTooltip="Desactivar" tooltipPosition="top"><i class="pi pi-ban"></i><span class="accion-label">Desactivar</span></button></div></td>
        </tr>
      </ng-template>
      <ng-template #emptymessage>
        <tr><td colspan="20" class="text-center text-muted">Sin registros</td></tr>
      </ng-template>
    </p-table>
    <p-table *ngIf="entidad === 'AUDITORIA'" [value]="auditoria" [paginator]="true" [rows]="10" [rowsPerPageOptions]="[5, 10, 20, 50]"
             [rowHover]="true" [showCurrentPageReport]="true"
             currentPageReportTemplate="Mostrando {first} a {last} de {totalRecords} registros"
             styleClass="p-datatable-sm p-datatable-striped table-mobile-cards">
      <ng-template #header>
        <tr><th>Fecha</th><th>Entidad</th><th>Acción</th><th>Usuario</th><th>Detalle</th></tr>
      </ng-template>
      <ng-template #body let-a>
        <tr>
          <td data-label="Fecha">{{ a.fecha | date:'dd/MM/yyyy HH:mm' }}</td>
          <td data-label="Entidad">{{ a.entidad }}<span *ngIf="a.idEntidad"> #{{ a.idEntidad }}</span></td>
          <td data-label="Acción">{{ a.accion }}</td>
          <td data-label="Usuario">{{ a.usuario }}</td>
          <td data-label="Detalle" class="text-truncate" style="max-width: 280px" [title]="a.detalle">{{ a.detalle }}</td>
        </tr>
      </ng-template>
      <ng-template #emptymessage>
        <tr><td colspan="5" class="text-center text-muted">Sin registros</td></tr>
      </ng-template>
    </p-table>
  `
})
export class AdministracionComponent implements OnInit {
  entidades = [{ valor: 'USUARIO', etiqueta: 'Usuarios', icon: 'bx-user' }, { valor: 'CONDUCTOR', etiqueta: 'Conductores', icon: 'bx-id-card' }, { valor: 'UNIDAD', etiqueta: 'Unidades', icon: 'bx-bus' }, { valor: 'PUNTO', etiqueta: 'Puntos', icon: 'bx-map-pin' }, { valor: 'MOTIVO', etiqueta: 'Motivos', icon: 'bx-list-check' }, { valor: 'AREA', etiqueta: 'Áreas', icon: 'bx-buildings' }, { valor: 'AUDITORIA', etiqueta: 'Auditoría', icon: 'bx-history' }];
  entidad: 'USUARIO' | 'CONDUCTOR' | 'UNIDAD' | 'PUNTO' | 'MOTIVO' | 'AREA' | 'AUDITORIA' = 'USUARIO';
  registros: any[] = [];
  auditoria: Auditoria[] = [];
  areas: { idArea: number; nombre: string }[] = [];
  form: any = {};
  roles: Record<string, string> = { SPTRANS: 'Supervisor', COTRANS: 'Coordinador', CHTRANS: 'Conductor', ADTRANS: 'Administrador' };

  constructor(private service: TransporteService, private alerts: AlertService) {}

  async ngOnInit() { await Promise.all([this.cargar(), this.cargarAreas()]); }
  async cambiarEntidad(entidad: any) { this.entidad = entidad; this.limpiar(); await this.cargar(); }
  entidadApi(): 'USUARIO' | 'UNIDAD' | 'PUNTO' | 'MOTIVO' | 'AREA' { return (this.entidad === 'CONDUCTOR' || this.entidad === 'AUDITORIA') ? 'USUARIO' : this.entidad; }
  async cargarAreas() { this.areas = (await this.service.administrarCatalogo('AREA', 'LISTAR')).filter(a => a.activo !== false); }
  async cargar() {
    if (this.entidad === 'AUDITORIA') { this.auditoria = await this.service.listarAuditoria(); return; }
    const datos = await this.service.administrarCatalogo(this.entidadApi(), 'LISTAR');
    this.registros = this.entidad === 'USUARIO' ? datos.filter(r => r.idrol !== 'CHTRANS')
      : this.entidad === 'CONDUCTOR' ? datos.filter(r => r.idrol === 'CHTRANS') : datos;
  }
  limpiar() { this.form = this.entidad === 'UNIDAD' ? { capacidad: 15 } : this.entidad === 'USUARIO' ? { idrol: 'SPTRANS' } : this.entidad === 'CONDUCTOR' ? { idrol: 'CHTRANS' } : {}; }
  columnas(): { etiqueta: string; campo: string }[] {
    switch (this.entidad) {
      case 'USUARIO': return [{ etiqueta: 'Nombre', campo: 'nombre' }, { etiqueta: 'Usuario', campo: 'usuario' }, { etiqueta: 'Rol', campo: 'idrol' }, { etiqueta: 'Área', campo: 'area' }];
      case 'CONDUCTOR': return [{ etiqueta: 'Nombre', campo: 'nombre' }, { etiqueta: 'Usuario', campo: 'usuario' }, { etiqueta: 'Placa', campo: 'placa' }, { etiqueta: 'Área', campo: 'area' }];
      case 'UNIDAD': return [{ etiqueta: 'Placa', campo: 'placa' }, { etiqueta: 'Capacidad', campo: 'capacidad' }];
      case 'PUNTO': return [{ etiqueta: 'Nombre', campo: 'nombre' }, { etiqueta: 'Latitud', campo: 'latitud' }, { etiqueta: 'Longitud', campo: 'longitud' }];
      default: return [{ etiqueta: 'Nombre', campo: 'nombre' }];
    }
  }
  idRegistro(r: any) { return r.idUsuario ?? r.idUnidad ?? r.idPunto ?? r.idMotivo ?? r.idArea; }
  editar(r: any) { this.form = { ...r, id: this.idRegistro(r), clave: '' }; }
  async guardar() {
    const datos = { ...this.form };
    if (this.entidad === 'CONDUCTOR') datos.idrol = 'CHTRANS';
    try { await this.service.administrarCatalogo(this.entidadApi(), 'GUARDAR', datos); this.limpiar(); await this.cargar(); }
    catch { this.alerts.showAlert('error', 'No se pudo guardar el registro', 'Error'); }
  }
  async eliminar(r: any) {
    if (!await this.alerts.confirm('Desactivar', '¿Desea desactivar este registro?')) return;
    await this.service.administrarCatalogo(this.entidadApi(), 'ELIMINAR', { id: this.idRegistro(r) });
    await this.cargar();
  }
}
