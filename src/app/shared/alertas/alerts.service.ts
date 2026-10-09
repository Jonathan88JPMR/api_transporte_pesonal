import { Injectable } from '@angular/core';
import Swal, { SweetAlertIcon } from 'sweetalert2';

@Injectable({
  providedIn: 'root'
})
export class AlertService {
  showAlert(icon: SweetAlertIcon, mensaje: string, titulo?: string): void {
    Swal.fire({
      icon,
      title: titulo ?? icon,
      text: mensaje,
      confirmButtonColor: '#238664'
    });
  }

  async confirm(titulo: string, mensaje: string): Promise<boolean> {
    const result = await Swal.fire({
      icon: 'question',
      title: titulo,
      text: mensaje,
      showCancelButton: true,
      confirmButtonText: 'Sí',
      cancelButtonText: 'No',
      confirmButtonColor: '#238664'
    });
    return result.isConfirmed;
  }

  // Devuelve el texto ingresado o undefined si se cancela. Si requerido es
  // true, no permite enviar el campo vacío.
  async input(titulo: string, mensaje: string, placeholder = '', requerido = true): Promise<string | undefined> {
    const result = await Swal.fire({
      icon: 'question',
      title: titulo,
      text: mensaje,
      input: 'text',
      inputPlaceholder: placeholder,
      showCancelButton: true,
      confirmButtonText: 'Aceptar',
      cancelButtonText: 'Cancelar',
      confirmButtonColor: '#238664',
      inputValidator: requerido
        ? (v) => (!v?.trim() ? 'Ingrese un valor' : null)
        : undefined
    });
    return result.isConfirmed ? (result.value as string).trim() : undefined;
  }
}
