# Reference: endpoints, users, roles, tokens, config

## Applications and ports

| App | Folder | Port | Needs |
|-----|--------|------|-------|
| EazyBank backend | `section1`–`section_12`, `section_15`, `section_16/springsecsection_16` | 8080 | MySQL from section 4 on (`localhost:3306`, db `eazybank`, `root`/`root`) |
| OAuth2 social-login demo | `section_14/springsecOAUTH2` | 8080 | GitHub / Facebook OAuth apps |
| Authorization server | `section_16/authserver` | 9000 | MySQL (`eazybank`) |
| Keycloak (section 15) | external | 8180 | realm `eazybankdev` |
| Angular UI | `section_11|12|15/bank-app-ui` | 4200 | the matching backend on 8080 (CORS allows only `http://localhost:4200`) |

## Endpoints of the EazyBank backend

"Section" = first section where the rule looks like this. Later sections change the rule where noted.

| Method & path | Access (s12) | Access (s15/16) | Returns |
|---------------|--------------|-----------------|---------|
| `GET /notices` | public | public | active notices |
| `POST /contact` | public, CSRF-exempt | public, CSRF-exempt | s8–11: one `Contact`; **s12+: takes and returns a JSON array**; `@PostFilter` drops `contactName == "Test"` |
| `POST /register` | public, CSRF-exempt | *removed* | 201 "…successfully registered". Body: `name,email,mobileNumber,pwd,role` |
| `GET /user` | authenticated | authenticated | the `Customer` (no `pwd`). In s11–12 the response also carries the JWT in the `Authorization` header |
| `POST /apiLogin` | public (s11+) | *removed* | `{"status":"OK","jwtToken":"…"}` |
| `GET /myAccount?id=` | `ROLE_USER` | `ROLE_USER`, `?email=` | the account |
| `GET /myBalance?id=` | `ROLE_USER` or `ROLE_ADMIN` | same, `?email=` | transactions, newest first |
| `GET /myLoans?id=` | any authenticated user, then `@PostAuthorize hasRole('USER')` | authenticated, `?email=` | loans, newest first |
| `GET /myCards?id=` | `ROLE_USER` | `ROLE_USER`, `?email=` | cards |

Public-by-config list (s12): `/notices`, `/contact`, `/error`, `/register`, `/invalidSession`, `/apiLogin`.
A path that matches **no** rule is denied by `authorizeHttpRequests` (the Spring Security 6+ default). This was not exercised here, but it means a new controller stays unreachable until you add a rule for it.

## Users and passwords in the seed data

| Where | Username | Password | Notes |
|-------|----------|----------|-------|
| s1, s2 | `eazybytes` | `12345` | from `spring.security.user.*` |
| s3, s7 eazyschool | `user` | `EazyBytes@12345` | stored `{noop}` (plain text) |
| s3, s7 eazyschool | `admin` | `EazyBytes@54321` | stored as `{bcrypt}$2a$12$88.f6u…` (cost 12). **Checked:** the hash matches `EazyBytes@54321`, not `@12345` |
| s4–s6 DB | `happy@example.com` | `EazyBytes@12345` | `{noop}`; role `read` |
| s4–s6 DB | `admin@example.com` | `EazyBytes@54321` | `{bcrypt}`; role `admin` |
| s8+ DB | `happy@example.com` | `EazyBytes@54321` | bcrypt, **same hash as `admin`**. Roles `ROLE_USER`, `ROLE_ADMIN` in `authorities` |

> The Postman collection uses `EazyBytes@12345` for `happy@example.com`. In the default (non-`prod`) profile that works only because that profile's
> provider **never checks the password** (chapter 06). Use `EazyBytes@54321` if you want the correct password.

## Roles and authorities

* Authorities are plain strings on the `authorities` table (`name` column).
* `hasRole("USER")` checks for the authority **`ROLE_USER`**. `hasAuthority("USER")` would not match it. The `ROLE_` prefix is added by `hasRole`, and must be in the DB (s9+).
* Keycloak (s15): roles come from the JWT claim `realm_access.roles`; `KeycloakRoleConverter` prefixes each with `ROLE_`.
* Authorization server (s16): roles come from the top-level `roles` claim; `KeycloakRoleConverter` (same class name, different body) prefixes each with `ROLE_`.
  For `client_credentials`, **scopes become roles** (request `scope=openid USER` → `ROLE_openid`, `ROLE_USER`).

## JWT details

**Section 11/12 (self-issued, HS256)**

| Item | Value |
|------|-------|
| Header name | `Authorization` (raw token, **no** `Bearer ` prefix) |
| Signing key | env `JWT_SECRET`, default `jxgEQeXHuPq8VdbyYFNkANdudQ53YUn4` (hard-coded in `ApplicationConstants`) |
| Claims | `iss=Eazy Bank`, `sub=JWT Token`, `username`, `authorities` (comma-separated), `iat`, `exp` |
| Lifetime | 30 000 000 ms = **30 000 s ≈ 8 h 20 min** |
| Issued by | `JWTTokenGeneratorFilter` on `GET /user` (Basic login), or `POST /apiLogin` |

**Section 16 (Spring Authorization Server, RS256)**

| Item | Value |
|------|-------|
| Header | `Authorization: Bearer <token>` |
| Signing key | RSA 2048, **regenerated at every auth-server start** (`kid` changes) |
| Claims | `sub`, `aud`, `scope`, `roles`, `iss=http://localhost:9000`, `iat`, `nbf`, `exp`, `jti` |
| Lifetime | 10 minutes (access), 8 hours (refresh, auth-code clients) |

### Registered clients on the authorization server

| `client_id` | Secret | Grant | Token format | Notes |
|-------------|--------|-------|--------------|-------|
| `eazybankapi` | in `ProjectSecurityConfig` | `client_credentials` | JWT (self-contained) | scopes `openid`, `ADMIN`, `USER` |
| `eazybankintrospect` | in `ProjectSecurityConfig` | `client_credentials` | **opaque** (reference) | used to call `/oauth2/introspect` |
| `eazybankclient` | in `ProjectSecurityConfig` | `authorization_code`, `refresh_token` | JWT | redirect `https://oauth.pstmn.io/v1/callback` |
| `eazypublicclient` | none (`NONE`) | `authorization_code` + **PKCE required**, `refresh_token` | JWT | for SPAs |

Auth-server endpoints (default paths): `/.well-known/openid-configuration`, `/oauth2/authorize`, `/oauth2/token`,
`/oauth2/jwks`, `/oauth2/introspect`, `/userinfo`. Login page for the authorization-code flow: `/login` (users come from the `customer` table).

## Configuration properties

| Property (env var) | Default | Used by |
|--------------------|---------|---------|
| `SPRING_SECURITY_LOG_LEVEL` | `TRACE` (`ERROR` in `application_prod`) | s1+ |
| `DATABASE_HOST` / `PORT` / `NAME` / `USERNAME` / `PASSWORD` | `localhost` / `3306` / `eazybank` / `root` / `root` | s4+ |
| `JPA_SHOW_SQL`, `HIBERNATE_FORMAT_SQL` | `true` (`false` in prod file) | s4+ |
| `SESSION_TIMEOUT` | `20m` | s7+ |
| `JWT_SECRET` | see above | s11–12 |
| `JWK_SET_URI` | s15 `http://localhost:8180/realms/eazybankdev/protocol/openid-connect/certs`; s16 `http://localhost:9000/oauth2/jwks` | s15, s16 |
| `INTROSPECT_URI`, `INTROSPECT_ID`, `INTROSPECT_SECRET` | commented out in properties | opaque-token variant |
| `AS_SERVER_PORT`, `AS_NAME` | `9000`, `authserver` | authserver |
| `SECURITY_USERNAME` / `SECURITY_PASSWORD` | `eazybytes` / `12345` | s1, s2, s14 |
| `GITHUB_CLIENT_ID/SECRET`, `FACEBOOK_CLIENT_ID/SECRET` | committed defaults (see chapter 14) | s14 |
