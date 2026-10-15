import { CommonModule } from '@angular/common';
import { Component, EventEmitter, Input, Output } from '@angular/core';
import { DialogModule } from 'primeng/dialog';

/**
 * Modal rojo de comunicado "horas sin servicio".
 * Bloqueante: no se cierra con clic fuera ni con la X — solo con los botones.
 * Se usa en el layout (alerta al ingresar) y en Solicitudes (re-aparece si
 * el supervisor intenta crear durante el rango bloqueado).
 */
@Component({
  selector: 'app-comunicado-modal',
  standalone: true,
  imports: [CommonModule, DialogModule],
  template: `
    <p-dialog [(visible)]="visible" (visibleChange)="visibleChange.emit($event)"
              [modal]="true" [draggable]="false" [dismissableMask]="false" [closable]="false"
              [style]="{ width: '440px' }">
      <ng-template #header>
        <span class="text-danger fw-bold"><i class="bx bx-error-circle me-1"></i>AVISO — SIN SERVICIO</span>
      </ng-template>
      <div *ngIf="comunicado" class="alert alert-danger mb-0">
        <h6 class="fw-bold mb-2">{{ comunicado.titulo }}</h6>
        <p class="mb-2">
          Hoy {{ comunicado.fecha | date:'dd/MM/yyyy' }} de <b>{{ comunicado.horaInicio }}</b> a <b>{{ comunicado.horaFin }}</b>
          no habrá servicio de movilidad.
        </p>
        <p class="mb-2">{{ comunicado.mensaje }}</p>
        <p class="mb-2" *ngIf="comunicado.unidades">
          Unidades ocupadas: <b>{{ comunicado.unidades }}</b><span *ngIf="comunicado.motivoActividad"> — {{ comunicado.motivoActividad }}</span>
        </p>
        <hr class="my-2">
        <small>Durante este horario no se podrán crear solicitudes. Solo se admiten <b>emergencias médicas</b>.</small>
      </div>
      <ng-template #footer>
        <button *ngIf="permiteEmergencia" type="button" class="btn btn-outline-danger" (click)="emergencia.emit()">
          Es emergencia médica
        </button>
        <button type="button" class="btn btn-danger" (click)="cerrar()">Entendido</button>
      </ng-template>
    </p-dialog>
  `
})
export class ComunicadoModalComponent {
  @Input() comunicado: any;
  @Input() visible = false;
  // true en Solicitudes: habilita el botón de emergencia médica dentro del modal
  @Input() permiteEmergencia = false;
  @Output() visibleChange = new EventEmitter<boolean>();
  @Output() emergencia = new EventEmitter<void>();

  cerrar() {
    this.visible = false;
    this.visibleChange.emit(false);
  }
}
