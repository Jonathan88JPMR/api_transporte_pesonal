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
}
