# EazyBank Spring Security: Project Documentation

This repo is the companion code for the course *Spring Security Zero to Master along with JWT, OAuth2*.
It builds **one application (EazyBank)** over and over, and each `sectionN` folder is a **snapshot of the same
project at a later stage**. You read the sections in order, and each one adds one security concept.

| Doc | What it covers |
|-----|----------------|
| [01-architecture.md](01-architecture.md) | How a request travels through Spring Security, and what the final architecture looks like |
| [02-sections-guide.md](02-sections-guide.md) | Section-by-section: what each folder adds and which files to read |
| [03-services-reference.md](03-services-reference.md) | Endpoints, users, roles, tokens, ports and config properties |
| [04-running-with-docker.md](04-running-with-docker.md) | Run any section with Docker only (no local JDK 25 needed), sample calls, troubleshooting |
| [walkthrough/](walkthrough/00-start-here.md) | **Teaching walkthrough:** every section explained from scratch with the code walked through line by line |

## The 30-second version

```
Client ──► Spring Security filter chain ──► Controller ──► Repository ──► MySQL (eazybank)
              │   authenticate: Basic / form / JWT / OAuth2 token
              │   authorize:    URL rules, then method rules (@PostAuthorize ...)
              └── (sections 15/16) tokens come from an external Authorization Server:
                      Keycloak (:8180)  or  Spring Authorization Server (:9000)
```

## Repo layout

| Folder | Topic (course section) |
|--------|------------------------|
| `section1` | A blank Spring Boot app: the default security you get for free |
| `section2` | Your own `SecurityFilterChain`: which URLs are public and which are protected |
| `section3` | In-memory users, `PasswordEncoder`, compromised-password check |
| `section4` | Users in MySQL: a custom `UserDetailsService`, `/register` |
| `section5` | Same code as section 4 (the section is theory: encoding, hashing, encryption) |
| `section6` | Custom `AuthenticationProvider`, profiles (`prod` vs default) |
| `section7` | Sessions, custom 401/403 responses, auth events. Also `eazyschool-start/end` (a form-login web app) |
| `section8` | CORS, CSRF, JPA entities for the whole bank schema (`/user`, `/myAccount` ...) |
| `section9` | Authorization: authorities → **roles**, `hasRole` rules |
| `section_10` | Custom servlet filters (before / at / after `BasicAuthenticationFilter`) |
| `section_11` | **JWT**: stateless sessions, token generator and validator filters, `/apiLogin` |
| `section_12` | Method security: `@PreAuthorize`, `@PostAuthorize`, `@PostFilter` |
| `section_14` | OAuth2 **social login** (GitHub, Facebook) |
| `section_15` | **Resource server** validating Keycloak JWTs (`bank-app-ui` is the Angular front end) |
| `section_16` | **Spring Authorization Server** (`authserver`) + the same resource server pointed at it |

There is no section 13 (theory only). Sections 1–5 share almost all code; the real changes start at section 6.

Other files in the root: `SpringSecurity.postman_collection.json` (ready-made API calls per section) and the
course `README.md` (links).

## Verified vs. read-only

The walkthrough marks what was **actually run** for this documentation (Boot 4.0.0, JDK 25 in a container, MySQL 8.4):
sections 3, 12 and 16 (auth server and resource server). Everything else was **read from code**. Chapters say which is which.
