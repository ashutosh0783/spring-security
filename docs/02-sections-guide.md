# Sections guide

Each section folder is a complete, runnable Maven project (Spring Boot **4.0.0**, **Java 25**).
"New" means what this section adds compared with the previous one. The last column is the file to open first.

| Section | New in this section | Open first |
|---------|--------------------|------------|
| `section1` | `spring-boot-starter-security` on the classpath secures **everything** with a default login. User/password come from `spring.security.user.*` (`eazybytes` / `12345`). `GET /welcome` | `application.properties` |
| `section2` | First `SecurityFilterChain` bean: `/myAccount`, `/myBalance`, `/myLoans`, `/myCards` need login; `/notices`, `/contact`, `/error` are public. Form login + HTTP Basic | `config/ProjectSecurityConfig.java` |
| `section3` | `InMemoryUserDetailsManager` with `user` (`{noop}`) and `admin` (`{bcrypt}`), `DelegatingPasswordEncoder`, `HaveIBeenPwnedRestApiPasswordChecker` | `config/ProjectSecurityConfig.java` |
| `section4` | Users in MySQL. `Customer` entity, `CustomerRepository`, `EazyBankUserDetailsService`, `POST /register` (hashes the password). CSRF disabled | `config/EazyBankUserDetailsService.java`, `sql/scripts.sql` |
| `section5` | **No code change** from section 4 (theory: encoding vs encryption vs hashing) | (same) |
| `section6` | `@Profile` split (`ProjectSecurityConfig` = `!prod`, `ProjectSecurityProdConfig` = `prod`). Custom `AuthenticationProvider` in two flavours | `config/EazyBank*AuthenticationProvider.java` |
| `section7` | `sessionManagement` (invalid-session URL, max 3 sessions), custom 401 (`CustomBasicAuthenticationEntryPoint`) and 403 (`CustomAccessDeniedHandler`) JSON bodies, `AuthenticationEvents`, session timeout. Also **`eazyschool-start` → `eazyschool-end`**: a Thymeleaf site that gains a custom login page and success/failure handlers | `exceptionhandling/`, `events/` |
| `section8` | **CORS** for `http://localhost:4200`, **CSRF** with a cookie repository + `CsrfCookieFilter`, full schema and JPA entities, real controllers, `GET /user` | `config/ProjectSecurityConfig.java`, `filter/CsrfCookieFilter.java` |
| `section9` | `authorities` table and `Authority` entity; `hasAuthority` rules replaced by `hasRole("USER")` / `hasAnyRole(...)`; `AuthorizationEvents` | `model/Authority.java`, `sql/scripts.sql` |
| `section_10` | Three custom filters: `RequestValidationBeforeFilter`, `AuthoritiesLoggingAtFilter`, `AuthoritiesLoggingAfterFilter`. `@EnableWebSecurity(debug = true)` | `filter/` |
| `section_11` | **JWT.** `STATELESS` sessions, `JWTTokenGeneratorFilter`, `JWTTokenValidatorFilter`, `POST /apiLogin`, `ApplicationConstants` (secret, header name), `AuthenticationManager` bean | `filter/JWT*.java`, `controller/UserController.java` |
| `section_12` | Method security: `@EnableMethodSecurity`, `@PostAuthorize` on `/myLoans`, `@PostFilter` on `/contact` (which now takes a JSON **array**) | `controller/LoansController.java`, `ContactController.java` |
| `section_14` | `springsecOAUTH2`: `oauth2Login()` with GitHub and Facebook, `/secure` page (Thymeleaf-less static HTML) | `config/ProjectSecurityConfig.java`, `application.properties` |
| `section_15` | The bank becomes an **OAuth2 resource server**: `oauth2ResourceServer(jwt)`, `KeycloakRoleConverter` (reads `realm_access.roles`), opaque-token variant commented out. No more `/register`, `/apiLogin`, JWT filters, custom providers. Endpoints take `?email=` | `config/ProjectSecurityConfig.java`, `config/KeycloakRoleConverter.java` |
| `section_16` | **`authserver`**: Spring Authorization Server with 4 registered clients (client-credentials JWT, client-credentials opaque, authorization-code, PKCE public client), RSA key, token customizer that adds a `roles` claim. `springsecsection_16` = section 15 with `KeycloakRoleConverter` reading `roles` and `jwk-set-uri` → `:9000` | `authserver/config/ProjectSecurityConfig.java` |

## Reading tips

* Compare two neighbouring sections with `git diff --no-index section9/springsecsection9/src section_10/springsecsection_10/src`.
  The diff is usually short; that is the whole lesson of the section.
* `section8` is the first section with the full database. **Start MySQL and load `sql/scripts.sql` from the newest section you plan to run.**
  The scripts from section 8 onward start with three `drop table` lines (`authorities`, `users`, `customer`) that fail on an empty database, so skip them on first load (the Docker helper does this). See [04-running-with-docker.md](04-running-with-docker.md).
* Sections 4–6 use the small `customer(id,email,pwd,role)` table; from section 8 on, `customer` has `customer_id`, `name`, `mobile_number`, `create_dt` and more.
  Using the wrong script for a section is the most common startup failure.
