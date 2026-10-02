import { Injectable } from '@angular/core';
import Dexie, { Table } from 'dexie';
import { Usuario } from '@/app/models/transporte.models';

export interface OperacionPendiente {
  id?: number;
  ruta: string;
  cuerpo: unknown;
  fecha: string;
  intentos: number;
}

export interface CacheConsulta {
  clave: string;
  datos: unknown;
  fecha: string;
}

class TransporteDB extends Dexie {
  usuario!: Table<Usuario, number>;
  operaciones!: Table<OperacionPendiente, number>;
  cache!: Table<CacheConsulta, string>;

  constructor() {
    super('transporte_personal_db');
    this.version(1).stores({
      usuario: 'idUsuario, usuario, idrol'
    });
    this.version(2).stores({
      usuario: 'idUsuario, usuario, idrol',
      operaciones: '++id, ruta, fecha, intentos'
    });
    this.version(3).stores({
      usuario: 'idUsuario, usuario, idrol',
      operaciones: '++id, ruta, fecha, intentos',
      cache: 'clave'
    });
  }
}

@Injectable({
  providedIn: 'root'
})
export class DexieService {
  private db = new TransporteDB();

  async saveUsuario(usuario: Usuario): Promise<void> {
    await this.db.usuario.clear();
    await this.db.usuario.add(usuario);
    localStorage.setItem('usuario', JSON.stringify(usuario));
  }

  async showUsuario(): Promise<Usuario | undefined> {
    return await this.db.usuario.toCollection().first();
  }

  async getUsuarioLogueado(): Promise<Usuario | undefined> {
    return await this.showUsuario();
  }

  async clearUsuario(): Promise<void> {
    await this.db.usuario.clear();
    localStorage.removeItem('usuario');
  }

  async encolarOperacion(ruta: string, cuerpo: unknown): Promise<void> {
    await this.db.operaciones.add({ ruta, cuerpo, fecha: new Date().toISOString(), intentos: 0 });
  }

  async operacionesPendientes(): Promise<OperacionPendiente[]> {
    return this.db.operaciones.orderBy('fecha').toArray();
  }

  async totalOperacionesPendientes(): Promise<number> {
    return this.db.operaciones.count();
  }

  async eliminarOperacion(id: number): Promise<void> {
    await this.db.operaciones.delete(id);
  }

  async incrementarIntento(operacion: OperacionPendiente): Promise<void> {
    if (operacion.id) await this.db.operaciones.update(operacion.id, { intentos: operacion.intentos + 1 });
  }

  async guardarCache(clave: string, datos: unknown): Promise<void> {
    await this.db.cache.put({ clave, datos, fecha: new Date().toISOString() });
  }

  async leerCache(clave: string): Promise<unknown | undefined> {
    return (await this.db.cache.get(clave))?.datos;
  }
}
