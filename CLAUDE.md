# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Companion code for the course *Spring Security Zero to Master along with JWT, OAuth2*. There is **no root build**: every `sectionN` folder is an independent Maven project (Spring Boot **4.0.0**, **Java 25**) that is a *snapshot of the same EazyBank app at a later stage*. Each section adds one concept on top of the previous one, so **do not "fix" or refactor across sections**; the differences between neighbouring sections are the lesson.

Docs live in `docs/` (start at `docs/README.md`): architecture, per-section guide, endpoint/user/token reference, Docker run guide, and a line-by-line teaching walkthrough in `docs/walkthrough/`. Keep them in sync if section code changes.

## Commands

Each project has its own `mvnw`; run from inside the project folder (e.g. `section_12/springsecsection_12`):

```bash
./mvnw spring-boot:run
./mvnw test
./mvnw test -Dtest=EazyBankBackendApplicationTests
```

- The local machine may have only JDK 21. Use the Docker helper instead of installing JDK 25: `docs/scripts/run-section.sh <project-dir>` (starts MySQL 8.4 and runs the app in a `maven:3.9-eclipse-temurin-25` container). `APP_NAME=` renames the app container; `KEEP_DB=1` reuses the running MySQL. Section 16 needs two apps, see `docs/04-running-with-docker.md`.
- There is no lint config. Tests are only the generated `*ApplicationTests` context-load stubs.
- MySQL is required from `section4` on (`localhost:3306`, db `eazybank`, `root`/`root`, overridable via `DATABASE_*` env vars). Load **that section's** `src/main/resources/sql/scripts.sql`. Scripts from section 8 on start with three `drop table` lines that fail on an empty DB, so skip them on first load. Sections 4–6 use a small `customer` table; 8+ use the full schema, so mixing scripts breaks startup.
- Git Bash on Windows: set `MSYS_NO_PATHCONV=1` when passing `/app`-style paths to `docker run`.

## Architecture: what spans multiple files

- **Section map.** s1–3 default/in-memory security; s4–5 DB users (s5 code is identical to s4); s6 profiles + custom provider; s7 sessions/JSON errors/events (+ `eazyschool-*` Thymeleaf app); s8 CORS/CSRF/full schema; s9 roles; s10 custom filters; s11 self-issued JWT; s12 method security; s14 OAuth2 social login (`springsecOAUTH2`); s15 resource server for Keycloak; s16 `authserver` (Spring Authorization Server, port 9000) + a resource server pointed at it. No section 13.
- **All security wiring is in `config/ProjectSecurityConfig.java`** of each project (a `SecurityFilterChain` bean). Controllers are thin (repository in, entity JSON out). Read that file first, then diff against the neighbouring section: `git diff --no-index section9/springsecsection9/src section_10/springsecsection_10/src`.
- **Profiles.** `application.properties` imports `application_prod.properties` and sets `spring.profiles.active=default`. `@Profile("!prod")` classes are the dev setup, `@Profile("prod")` classes the strict one (forces HTTPS redirect, so `prod` does not work over plain HTTP).
- **Auth evolution.** Sessions + cookie (s1–10, CSRF cookie repo + `CsrfCookieFilter` from s8) → self-issued HS256 JWT in the raw `Authorization` header, no `Bearer ` prefix (s11–12: `JWTTokenGeneratorFilter` on `/user`, `JWTTokenValidatorFilter`, `POST /apiLogin`) → Bearer JWTs verified via `jwk-set-uri` (s15 Keycloak, s16 own auth server).
- **Roles.** `hasRole("USER")` matches authority `ROLE_USER`, stored verbatim in the `authorities` table (s9+). In s15 roles come from the `realm_access.roles` claim; in s16 from a top-level `roles` claim (added by the auth server's token customizer; for client_credentials, scopes become roles). The converter class is named `KeycloakRoleConverter` in both, with different bodies. The claim name is a contract between the auth server and the resource server.
- **Config is env-driven**: properties look like `${ENV_NAME:default}` (`DATABASE_HOST`, `JWT_SECRET`, `JWK_SET_URI`, `SPRING_SECURITY_LOG_LEVEL` ...). Inside Docker, `localhost` is the container itself, so pass the other container's name (e.g. `JWK_SET_URI=http://as16:9000/oauth2/jwks`).
- Angular front ends (`bank-app-ui`) exist in `section_11`, `_12`, `_15`; CORS only allows `http://localhost:4200`.

## Known gotchas (verified by running sections 3, 12, 16)

- The `!prod` `EazyBankUsernamePwdAuthenticationProvider` **never checks the password**: any password works for an existing user (also on `POST /apiLogin`). Only the `prod` provider and the `authserver` provider call `passwordEncoder.matches`.
- Seed data: the bcrypt hash used for `admin` / `happy@example.com` is for **`EazyBytes@54321`**; the `{noop}` `user` password is `EazyBytes@12345` (the Postman collection uses `@12345`, which only works because of the bug above).
- A bad/tampered JWT in s11–12 returns a **500** (exception thrown from a filter); s15/16 return a proper 401.
- Endpoints take `?id=` (s8–12) or `?email=` (s15–16) with no ownership check (any authenticated user can read others' data). Section 12's `/contact` takes and returns a JSON **array**.
- The auth server regenerates its RSA key on every start, which invalidates all tokens. Client secrets there and the GitHub/Facebook secrets in `section_14` are committed in the repo.
- Postman collection: `SpringSecurity.postman_collection.json` (folders per section).

## Working agreement

- Do not `git commit` or `git push` without the user's explicit approval; leave changes uncommitted and ask.
