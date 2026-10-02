import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { AuthService } from '../services/auth.service';
import { RoleLandingGuard } from './role-landing.guard';

class AuthStub {
  rol = 'SPTRANS';
  async getUser() { return { idrol: this.rol }; }
}

describe('RoleLandingGuard', () => {
  let guard: RoleLandingGuard;
  let auth: AuthStub;
  const router = { parseUrl: (url: string) => ({ toString: () => url }) };

  beforeEach(() => {
    TestBed.configureTestingModule({ providers: [RoleLandingGuard, { provide: AuthService, useClass: AuthStub }, { provide: Router, useValue: router }] });
    guard = TestBed.inject(RoleLandingGuard);
    auth = TestBed.inject(AuthService) as unknown as AuthStub;
  });

  it('redirects supervisors to requests', async () => {
    expect((await guard.canActivate()).toString()).toBe('/main/solicitudes');
  });

  it('redirects drivers to their services', async () => {
    auth.rol = 'CHTRANS';
    expect((await guard.canActivate()).toString()).toBe('/main/conductor');
  });
});
