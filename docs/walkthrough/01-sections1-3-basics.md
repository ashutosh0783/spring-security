# Chapter 01: Sections 1–3, the basics (`section1/`, `section2/`, `section3/`)

## 1. The problem
You have a REST API. Anyone who can reach it can call anything. You want login, and you want some URLs public and others private.

## 2. The idea
Add **one dependency**, `spring-boot-starter-security`, and Spring Boot builds a **filter chain** in front of every controller.
With zero code, *every* URL requires login. Then you replace the default with your own rules.

## 3. Code walkthrough

### 3.1 Section 1: security with no code
`section1/.../application.properties`
```properties
1  spring.application.name=${SPRING_APP_NAME:springsecsection1}
2  spring.security.user.name=${SECURITY_USERNAME:eazybytes}
3  spring.security.user.password=${SECURITY_PASSWORD:12345}
4  logging.level.org.springframework.security=${SPRING_SECURITY_LOG_LEVEL:TRACE}
```
- **Lines 2–3**: the single default user. Without them Spring generates a random password at startup and prints it in the log.
- **Line 4**: `TRACE` prints every filter a request passes through. Noisy, but the best teacher.
- `${NAME:default}` means "environment variable `NAME`, else the default". Used for every property in the repo.

`WelcomeController.java`
```java
1  @RestController
2  public class WelcomeController {
3      @GetMapping("/welcome")
4      public String sayWelcome() { return "Welcome to Spring Application with security"; }
5  }
```
Nothing about security here. Yet `GET /welcome` returns 401 (or a login page in a browser) until you log in as `eazybytes`.

### 3.2 Section 2: your own rules
`section2/.../config/ProjectSecurityConfig.java`
```java
1  @Configuration
2  public class ProjectSecurityConfig {
3      @Bean
4      SecurityFilterChain defaultSecurityFilterChain(HttpSecurity http) throws Exception {
5          http.authorizeHttpRequests((requests) -> requests
6                  .requestMatchers("/myAccount", "/myBalance", "/myLoans", "/myCards").authenticated()
7                  .requestMatchers("/notices", "/contact", "/error").permitAll());
8          http.formLogin(withDefaults());
9          http.httpBasic(withDefaults());
10         return http.build();
11     }
12 }
```
- **Line 4**: declaring a `SecurityFilterChain` bean switches off Boot's default one. Now *you* own the rules.
- **Line 6**: these four need a logged-in user. **Line 7**: these are open (`/error` must be open, or error pages themselves become 401s).
- **Line 8** `formLogin`: browser login page and session cookie. **Line 9** `httpBasic`: `Authorization: Basic base64(user:pass)` header, ideal for Postman and scripts.
- Commented-out lines in the file show the two extremes: `anyRequest().permitAll()` (open everything) and `denyAll()` (close everything).

### 3.3 Section 3: real users and password storage
`section3/.../config/ProjectSecurityConfig.java` adds three beans:
```java
1  @Bean
2  public UserDetailsService userDetailsService() {
3      UserDetails user = User.withUsername("user").password("{noop}EazyBytes@12345").authorities("read").build();
4      UserDetails admin = User.withUsername("admin")
5              .password("{bcrypt}$2a$12$88.f6upbBvy0okEa7OfHFuorV29qeK.sVbB9VQ6J6dWM1bW6Qef8m")
6              .authorities("admin").build();
7      return new InMemoryUserDetailsManager(user, admin);
8  }
9  @Bean
10 public PasswordEncoder passwordEncoder() { return PasswordEncoderFactories.createDelegatingPasswordEncoder(); }
11 @Bean
12 public CompromisedPasswordChecker compromisedPasswordChecker() { return new HaveIBeenPwnedRestApiPasswordChecker(); }
```
- **Lines 3, 5**: the **`{id}` prefix** tells `DelegatingPasswordEncoder` which algorithm produced the stored value. `{noop}` = plain text (demo only), `{bcrypt}` = bcrypt hash. This lets you migrate algorithms without breaking old users.
- **Line 5**: bcrypt output `$2a$12$…`: `2a` = version, `12` = cost (2¹² rounds), then salt + hash. Two hashes of the same password differ because of the random salt.
- **Line 7**: users live in memory, and are gone at restart. Fine for learning, never for production.
- **Line 12**: checks passwords against the Have I Been Pwned breach database over the network (from Spring Security 6.3; the default login provider consults it when this bean exists). A compromised password is rejected at login, so an offline machine or a breached demo password can change the behaviour you see. In my Docker run, `user:EazyBytes@12345` still logged in fine.

## 4. Verified results (section 3, run in Docker)
| Request | Result |
|---------|--------|
| `GET /notices` | 200 |
| `GET /myAccount` (no login) | 401 |
| `GET /myAccount` with `user:EazyBytes@12345` | 200 |
| `GET /myAccount` with `admin:EazyBytes@12345` | **401** |
| `GET /myAccount` with `user:bad` | 401 |
| `GET /login` | 200 (generated form page) |
| Response headers on a protected call | `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Cache-Control: no-cache, no-store…` |

The `admin` failure is instructive: the seeded bcrypt hash is for **`EazyBytes@54321`**. `@12345` belongs to the `{noop}` user. I confirmed it by checking the hash offline.
Also note the free **security headers**: Spring Security adds them by default.

## 5. Traps and senior notes
- **Forgetting `/error` in the public list** turns every failure into a confusing 401.
- **`{noop}` in real data is a vulnerability.** It exists so tutorials can show a password you can read.
- **A `SecurityFilterChain` bean replaces the default entirely**; you must re-declare `formLogin`/`httpBasic` yourself.
- **Order of matchers matters**: first match wins. Put specific rules before general ones.
