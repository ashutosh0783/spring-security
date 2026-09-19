# Architecture

## 1. The one idea behind Spring Security

Spring Security is **a chain of servlet filters** sitting in front of your controllers. Every HTTP request walks
through the chain; each filter can let it pass, change it, or stop it.

```
HTTP request
   │
   ▼
FilterChainProxy  (Spring's single entry point, registered as "springSecurityFilterChain")
   │  picks the first SecurityFilterChain whose matcher fits the request
   ▼
[ CorsFilter ] → [ CsrfFilter ] → [ your filters ] → [ BasicAuthenticationFilter / UsernamePasswordAuthenticationFilter / BearerTokenAuthenticationFilter ]
   → [ AuthorizationFilter ]  →  DispatcherServlet → @RestController
```

Two questions are answered along the way:

| Question | Name | Who does it in this repo |
|----------|------|--------------------------|
| *Who are you?* | Authentication | `AuthenticationManager` → `AuthenticationProvider` → `UserDetailsService` + `PasswordEncoder` (sections 1–12); or a JWT decoder (sections 15–16) |
| *What may you do?* | Authorization | `authorizeHttpRequests(...)` rules, then method annotations (section 12) |

The result of authentication is an `Authentication` object stored in the `SecurityContextHolder` for the current request.
Everything after that (URL rules, `@PostAuthorize`, `authentication.getName()` in a controller) reads it from there.

## 2. The EazyBank application

One Spring Boot app (`eazybankbackend`, port **8080**), one MySQL schema (`eazybank`):

| Table | Entity | Used by |
|-------|--------|---------|
| `customer` | `Customer` | login, `/register`, `/user` |
| `authorities` | `Authority` | roles/authorities per customer (from section 9) |
| `accounts` | `Accounts` | `/myAccount` |
| `account_transactions` | `AccountTransactions` | `/myBalance` |
| `loans` | `Loans` | `/myLoans` |
| `cards` | `Cards` | `/myCards` |
| `notice_details` | `Notice` | `/notices` (public) |
| `contact_messages` | `Contact` | `/contact` (public) |

Controllers are thin: they call a Spring Data `CrudRepository` and return entities as JSON.
All the interesting behaviour is in `config/ProjectSecurityConfig.java` and the classes it wires in.

## 3. How authentication evolves

| Sections | Credential the client sends | Server remembers you by | Where users live |
|----------|----------------------------|-------------------------|------------------|
| 1–3 | HTTP Basic or form login | `JSESSIONID` session cookie | one configured user / in-memory |
| 4–10 | Basic / form login | `JSESSIONID` (`SessionCreationPolicy.ALWAYS` from s8) | MySQL `customer` |
| 11–12 | Basic once (to `/user`), then a **JWT** in the `Authorization` header; or `POST /apiLogin` | nothing: the JWT carries identity (stateless) | MySQL `customer` |
| 15 | `Authorization: Bearer <JWT from Keycloak>` | nothing (stateless) | Keycloak |
| 16 | `Authorization: Bearer <JWT from Spring Authorization Server>` | nothing (stateless) | `authserver` (own MySQL lookup) |

## 4. Final architecture (section 16)

```
                  ┌──────────────────────────────┐
  client ───────► │ authserver  :9000            │  POST /oauth2/token   (client_credentials, authorization_code+PKCE)
  (Postman/UI)    │ Spring Authorization Server  │  GET  /oauth2/jwks    (public signing key)
                  └───────────────┬──────────────┘  POST /oauth2/introspect (opaque tokens)
        access token (JWT)        │ MySQL: customer + authorities (for login)
                  ▼               │
                  ┌──────────────────────────────┐
  client ───────► │ springsecsection_16  :8080   │  validates JWT signature via  jwk-set-uri
  Bearer <jwt>    │ resource server              │  maps "roles" claim → ROLE_xxx → hasRole(...)
                  └───────────────┬──────────────┘
                                  ▼
                              MySQL eazybank
```

The resource server never talks to the auth server per request. It fetches the public key once from
`/oauth2/jwks` and verifies each token's signature locally. This is why JWTs scale.

Section 15 is the same picture with **Keycloak** (`:8180`, realm `eazybankdev`) instead of `authserver`.

## 5. Cross-cutting behaviours to know

* **Profiles.** `application.properties` imports `application_prod.properties` and keeps `spring.profiles.active=default`.
  Classes annotated `@Profile("!prod")` are the dev setup; `@Profile("prod")` classes are the hardened one (HTTPS required,
  password actually checked, quieter logs). See the security caveats in [chapter 06](walkthrough/06-section6-profiles-providers.md).
* **Logging.** `logging.level.org.springframework.security=TRACE` (dev default) prints every filter a request passes through. Turn it on when debugging.
* **Env-var configuration.** Every property looks like `${ENV_NAME:default}` (e.g. `DATABASE_HOST`, `JWT_SECRET`, `JWK_SET_URI`),
  so the same jar runs locally and in Docker without edits.
