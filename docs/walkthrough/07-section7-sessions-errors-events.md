# Chapter 07: Section 7, sessions, error responses and events (`section7/springsecsection7`, `eazyschool-*`)

*Read from code only; not run (the JSON 401 body was seen in the section 12 run, which reuses this class).*

## 1. The problem
* Logged-in users hold a server-side session. How many? For how long? What if it expires?
* Default 401/403 responses are unhelpful for API clients.
* You want a record of who logged in or failed.

## 2. The idea
Spring Security exposes a hook for each: `sessionManagement`, `AuthenticationEntryPoint` (what to send when *not authenticated*), `AccessDeniedHandler` (what to send when *authenticated but forbidden*), and application **events** published on every login result.

## 3. Code walkthrough

### 3.1 The config
```java
1  http.sessionManagement(smc -> smc.invalidSessionUrl("/invalidSession").maximumSessions(3).maxSessionsPreventsLogin(true))
2      .redirectToHttps((https) -> https.disable())
3      .csrf(csrfConfig -> csrfConfig.disable())
4      .authorizeHttpRequests(... .requestMatchers("/notices", "/contact", "/error", "/register", "/invalidSession").permitAll());
5  http.formLogin(withDefaults());
6  http.httpBasic(hbc -> hbc.authenticationEntryPoint(new CustomBasicAuthenticationEntryPoint()));
7  http.exceptionHandling(ehc -> ehc.accessDeniedHandler(new CustomAccessDeniedHandler()));
```
- **Line 1**: an expired/unknown session cookie redirects to `/invalidSession` (public: line 4). `maximumSessions(3)` allows 3 concurrent logins per user; `maxSessionsPreventsLogin(true)` means the **4th login is refused** (`false` would expire the oldest instead).
- **Line 2**: this is the `!prod` chain, so plain HTTP is allowed (the prod chain leaves the HTTPS redirect on).
- **Line 6**: replaces the default Basic challenge with our JSON for failed Basic logins.
- **Line 7**: JSON for 403.
- `application.properties` adds `server.servlet.session.timeout=${SESSION_TIMEOUT:20m}`: idle sessions expire after 20 minutes.

### 3.2 A JSON 401
`exceptionhandling/CustomBasicAuthenticationEntryPoint.java`
```java
1  public void commence(HttpServletRequest request, HttpServletResponse response, AuthenticationException authException) throws IOException {
2      LocalDateTime currentTimeStamp = LocalDateTime.now();
3      String message = (authException != null && authException.getMessage() != null) ? authException.getMessage() : "Unauthorized";
4      String path = request.getRequestURI();
5      response.setHeader("eazybank-error-reason", "Authentication failed");
6      response.setStatus(HttpStatus.UNAUTHORIZED.value());
7      response.setContentType("application/json;charset=UTF-8");
8      String jsonResponse = String.format("{\"timestamp\": \"%s\", \"status\": %d, ...}", currentTimeStamp, 401, ..., message, path);
9      response.getWriter().write(jsonResponse);
10 }
```
`CustomAccessDeniedHandler` has the same shape with status 403 and header `eazybank-denied-reason`.
Observed body (section 12 run): `{"timestamp": "2026-09-19T10:58:53", "status": 401, "error": "Unauthorized", "message": "Full authentication is required to access this resource", "path": "/myAccount"}`.
An observed 403 (section 16, where the same handler is wired) reads `"message": "Access Denied"`.

### 3.3 Events
`events/AuthenticationEvents.java`
```java
1  @Component @Slf4j
2  public class AuthenticationEvents {
3      @EventListener
4      public void onSuccess(AuthenticationSuccessEvent successEvent) {
5          log.info("Login successful for the user : {}", successEvent.getAuthentication().getName());
6      }
7      @EventListener
8      public void onFailure(AbstractAuthenticationFailureEvent failureEvent) {
9          log.error("Login failed for the user : {} due to : {}", failureEvent.getAuthentication().getName(), failureEvent.getException().getMessage());
10     }
11 }
```
**Lines 3, 7**: Spring publishes these events; you only subscribe. Ideal for audit logs, lockout counters or alerts, with no change to the login code.

### 3.4 `eazyschool-start` → `eazyschool-end`
A separate Thymeleaf website (no database). The end version's config:
```java
1  .formLogin(flc -> flc.loginPage("/login").usernameParameter("userid").passwordParameter("secretPwd")
2          .defaultSuccessUrl("/dashboard").failureUrl("/login?error=true")
3          .successHandler(authenticationSuccessHandler).failureHandler(authenticationFailureHandler))
4  .logout(loc -> loc.logoutSuccessUrl("/login?logout=true").invalidateHttpSession(true).clearAuthentication(true).deleteCookies("JSESSIONID"))
```
- **Line 1**: your own login page and your own form field names. **Line 3**: handlers that log and redirect (`CustomAuthenticationSuccessHandler` → `/dashboard`, the failure handler → `/login?error=true`).
- **Line 4**: full logout: destroy the session, clear authentication, delete the cookie.
- The start version has `/dashboard` public; the end version makes it `authenticated()` and adds `/login/**` to the public list.

## 4. Traps and senior notes
- **`maxSessionsPreventsLogin(true)` can lock users out** after a browser crash, until the old sessions expire.
- **Session settings mean nothing once you go stateless** (chapter 11).
- **Hand-built JSON via `String.format`** breaks if a message contains a quote. Use Jackson's `ObjectMapper`.
- **Log failures carefully.** Log the username, never the password, and beware log injection through usernames.
- In `eazyschool-end`, `successHandler` (line 3) **overrides** `defaultSuccessUrl` (line 2), so only the handler's redirect takes effect.
