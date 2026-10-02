import { HttpInterceptorFn, HttpRequest, HttpHandlerFn, HttpEvent } from '@angular/common/http';
import { Observable } from 'rxjs';

export const authInterceptor: HttpInterceptorFn = (
  request: HttpRequest<unknown>,
  next: HttpHandlerFn
): Observable<HttpEvent<unknown>> => {
  // Solo procesar URLs de la API
  if (!request.url.includes('/api/')) {
    return next(request);
  }

  const raw = localStorage.getItem('usuario');
  if (!raw) {
    return next(request);
  }

  try {
    const usuario = JSON.parse(raw);
    const backendRole = usuario.idrol || 'USUARIO';

    request = request.clone({
      setHeaders: {
        'X-User-Role': backendRole,
        'X-User-Id': String(usuario.idUsuario ?? ''),
        'X-User-Name': usuario.usuario ?? '',
        ...(usuario.token ? { Authorization: `Bearer ${usuario.token}` } : {})
      }
    });
  } catch {
    // usuario en localStorage corrupto: continuar sin headers
  }

  return next(request);
};
