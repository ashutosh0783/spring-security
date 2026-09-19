# Running the sections

Every project needs **Java 25** (`<java.version>25</java.version>`, Spring Boot 4.0.0) and, from section 4 on, **MySQL 8**.
If you only have an older JDK, run through Docker with the helper script; nothing else has to be installed.

## Quick start with the helper script

```bash
# from the repo root (Git Bash / WSL / macOS / Linux)
docs/scripts/run-section.sh section_12/springsecsection_12
docker logs -f secapp          # wait for "Started EazyBankBackendApplication"
```

What the script does: starts `mysql:8.4` (db `eazybank`, `root`/`root`, port 3306), loads the section's `sql/scripts.sql`
(skipping the leading `drop table` lines), then runs `mvn spring-boot:run` in a `maven:3.9-eclipse-temurin-25` container with
the source folder mounted. The first start downloads dependencies (about 2 minutes); later starts take about 25 seconds.
Cleanup: `docker rm -f secapp secmysql && docker network rm secnet` (plus `as16`/`app16` if you used them).

**Only one section at a time.** Each one uses port 8080 (the auth server uses 9000) and re-creates the database.

## Two-app setup (section 16)

```bash
APP_NAME=as16  docs/scripts/run-section.sh section_16/authserver                  # port 9000, loads the DB
APP_NAME=app16 KEEP_DB=1 APP_ENV="-e JWK_SET_URI=http://as16:9000/oauth2/jwks" \
               docs/scripts/run-section.sh section_16/springsecsection_16         # port 8080, reuses the DB
```
The resource server must reach the auth server by a **container name on the same Docker network**
(`JWK_SET_URI=http://as16:9000/oauth2/jwks`); `localhost` inside a container means the container itself.
Both apps use the same `eazybank` database, so the second call passes `KEEP_DB=1` instead of recreating it.

## Running without Docker

1. Install JDK 25 and MySQL 8. Create the database: `CREATE DATABASE eazybank;`
2. Load `src/main/resources/sql/scripts.sql` of the section (skip the `drop table` lines on an empty DB).
3. `cd section_12/springsecsection_12 && ./mvnw spring-boot:run` (or run the `*Application` class from your IDE).
4. Everything is overridable by env vars (`DATABASE_HOST`, `DATABASE_USERNAME`, `JWT_SECRET`, …). See [03-services-reference.md](03-services-reference.md).

## Sample calls (verified on section 12, `localhost:8080`)

```bash
B=http://localhost:8080

# public
curl $B/notices                                             # 200 [...notices...]

# protected, no credentials
curl -i "$B/myAccount?id=1"                                 # 401 JSON body from CustomBasicAuthenticationEntryPoint

# obtain a JWT
curl -s -X POST $B/apiLogin -H 'Content-Type: application/json' \
     -d '{"username":"happy@example.com","password":"EazyBytes@54321"}'
# {"status":"OK","jwtToken":"eyJhbGciOiJIUzI1NiJ9...."}

# use it (raw token, NO "Bearer " in sections 11-12)
curl -H "Authorization: $JWT" "$B/myAccount?id=1"           # 200 {"accountNumber":1865764534,...}

# a request whose Basic username contains "test" is rejected by RequestValidationBeforeFilter
curl -i -u test@example.com:x $B/user                       # 400

# @PostFilter: the entry named "Test" is removed from the response
curl -X POST $B/contact -H 'Content-Type: application/json' \
     -d '[{"contactName":"Test","contactEmail":"a@b.c","subject":"s","message":"m"}]'      # 200 []
```

Section 16 (auth server on 9000, resource server on 8080):

```bash
TOKEN=$(curl -s -u eazybankapi:<secret-from-ProjectSecurityConfig> \
        -d grant_type=client_credentials -d "scope=openid USER" \
        http://localhost:9000/oauth2/token | sed 's/.*"access_token":"\([^"]*\)".*/\1/')
curl -H "Authorization: Bearer $TOKEN" "http://localhost:8080/myAccount?email=happy@example.com"   # 200
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Communications link failure` at startup | MySQL not up yet, or `DATABASE_HOST` wrong | wait for `mysqladmin ping`; in Docker use `DATABASE_HOST=secmysql` |
| `Table 'eazybank.customer' doesn't exist` | SQL script not loaded | load the script of **that section** |
| `Unknown column 'customer_id'` / `'id'` | script from a different section (sections 4–6 use a small `customer` table, 8+ a large one) | reload with the right script |
| `IllegalStateException: HTTP Port '808x' does not have a corresponding HTTPS Port` | the `prod` profile forces HTTPS redirect (`ProjectSecurityProdConfig`) | run without `prod`, or add TLS (`server.ssl.*`) |
| `500` with `BadCredentialsException: Invalid Token received!` (s11–12) | wrong/expired/tampered JWT; the exception escapes as a 500, not a 401 | send a fresh token |
| `401` on every call in s16 with a valid token | resource server cannot reach `JWK_SET_URI` | check the URL from **inside** the container |
| `403` in s16 with a valid token | the token has no `USER` scope/role | request `scope=openid USER` |
| `403` on POST with a session/cookie login | CSRF token missing (s8+) | send `X-XSRF-TOKEN` from the `XSRF-TOKEN` cookie; `/register` and `/contact` are exempt |
| Startup fails on the Boot 4 / Java 25 parent | JDK older than 25 | use the Docker route |
| `Filename too long` / path errors on Windows | deep paths | `git config --global core.longpaths true` |
