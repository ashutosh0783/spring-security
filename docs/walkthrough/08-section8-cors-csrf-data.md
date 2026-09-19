# Chapter 08: Section 8, CORS, CSRF and the full data model (`section8/`)

*Read from code only; the CSRF exemptions were confirmed on section 12 (same config).*

## 1. The problem
The Angular front end runs on `http://localhost:4200` and calls the API on `:8080`. Browsers block that by default (CORS), and once a session cookie is used, the API becomes vulnerable to CSRF. The app also needs the real bank data.

## 2. The idea
| Threat / rule | What it is | Defence |
|---------------|-----------|---------|
| **Same-origin policy / CORS** | A browser page may only call APIs of its own origin unless the API sends `Access-Control-Allow-*` headers | configure a `CorsConfiguration` naming the trusted origin |
| **CSRF** | Another site makes your browser send a state-changing request **with your session cookie** | require a secret token that other sites cannot read |

CSRF protection only matters for **cookie-based** authentication. The token is sent in a cookie (`XSRF-TOKEN`) and must be echoed in a header (`X-XSRF-TOKEN`); a foreign site cannot read your cookie, so it cannot copy it into the header.

## 3. Code walkthrough

### 3.1 The security chain
`config/ProjectSecurityConfig.java`
```java
1  CsrfTokenRequestAttributeHandler csrfTokenRequestAttributeHandler = new CsrfTokenRequestAttributeHandler();
2  http.securityContext(contextConfig -> contextConfig.requireExplicitSave(false))
3      .sessionManagement(sessionConfig -> sessionConfig.sessionCreationPolicy(SessionCreationPolicy.ALWAYS))
4      .cors(corsConfig -> corsConfig.configurationSource(new CorsConfigurationSource() {
5          public CorsConfiguration getCorsConfiguration(HttpServletRequest request) {
6              CorsConfiguration config = new CorsConfiguration();
7              config.setAllowedOrigins(Collections.singletonList("http://localhost:4200"));
8              config.setAllowedMethods(Collections.singletonList("*"));
9              config.setAllowCredentials(true);
10             config.setAllowedHeaders(Collections.singletonList("*"));
11             config.setMaxAge(3600L);
12             return config;
13         }
14     }))
15     .csrf(csrfConfig -> csrfConfig.csrfTokenRequestHandler(csrfTokenRequestAttributeHandler)
16             .ignoringRequestMatchers("/contact", "/register")
17             .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse()))
18     .addFilterAfter(new CsrfCookieFilter(), BasicAuthenticationFilter.class)
19     .redirectToHttps((https) -> https.disable())
20     .authorizeHttpRequests((requests) -> requests
21             .requestMatchers("/myAccount", "/myBalance", "/myLoans", "/myCards", "/user").authenticated()
22             .requestMatchers("/notices", "/contact", "/error", "/register", "/invalidSession").permitAll());
```
- **Line 2**: `requireExplicitSave(false)` makes Spring save the `SecurityContext` into the session automatically (the old behaviour). **Line 3**: `ALWAYS` creates a session even if not needed, so the Angular app always has a `JSESSIONID`.
- **Line 7**: only this origin is trusted; never `"*"` together with credentials. **Line 9**: `allowCredentials(true)` lets the browser send cookies/`Authorization` cross-origin. **Line 11**: browsers may cache the preflight answer for an hour.
- **Line 15**: `CsrfTokenRequestAttributeHandler` is the plain (non-BREACH-masked) handler, which is what a JavaScript client that copies the cookie value needs.
- **Line 16**: `/contact` and `/register` are public forms with no session yet, so they are exempt from CSRF.
- **Line 17**: `withHttpOnlyFalse()`: the cookie is readable by JavaScript (the SPA must read it to build the header). Trade-off: XSS could read it too.
- **Line 18** + `CsrfCookieFilter`:
```java
1  public class CsrfCookieFilter extends OncePerRequestFilter {
2      protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
3          CsrfToken csrfToken = (CsrfToken) request.getAttribute(CsrfToken.class.getName());
4          csrfToken.getToken();
5          filterChain.doFilter(request, response);
6      }
7  }
```
  Since Spring Security 6 the token is **lazy**: it is only generated when something reads it. **Line 4** forces that read so the cookie is written on the first response after login.

### 3.2 The data model and JPA
Seven tables (`customer`, `accounts`, `account_transactions`, `loans`, `cards`, `notice_details`, `contact_messages`) each with an entity + repository. Example:
```java
1  @Entity @Getter @Setter
2  public class Customer {
3      @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
4      @Column(name = "customer_id") private long id;
5      private String name;
6      private String email;
7      @Column(name = "mobile_number") private String mobileNumber;
8      @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) private String pwd;
9      private String role;
10     @Column(name = "create_dt") @JsonIgnore private Date createDt;
11 }
```
- **Line 8**: `WRITE_ONLY` = the JSON may **carry** `pwd` in a request but it is **never** written in a response.
- **Line 10**: `@JsonIgnore` hides the timestamp from clients entirely.
- Repositories use derived queries such as `findByCustomerIdOrderByTransactionDtDesc(long customerId)`.

### 3.3 Controllers
```java
1  @GetMapping("/myAccount")
2  public Accounts getAccountDetails(@RequestParam long id) {
3      Accounts accounts = accountsRepository.findByCustomerId(id);
4      if (accounts != null) { return accounts; } else { return null; }
5  }
```
And `/user` in `UserController` returns the logged-in `Customer` via `customerRepository.findByEmail(authentication.getName())`; Spring injects the current `Authentication` for you.
`/contact` creates a request number `"SR" + random` and stores the message.

## 4. Traps and senior notes
- **Broken object-level authorization.** `/myAccount?id=` trusts the `id` parameter: any logged-in user can pass someone else's id. The right way is to derive the customer from `authentication.getName()`, not from a request parameter. (Section 15/16 use `?email=`, with the same flaw. Section 16's run showed any `USER` token can pass any email.)
- **Exposing entities directly** couples your API to your schema. Prefer DTOs.
- **Cookie-based CSRF is not needed for a pure-JWT API** (chapter 11), but it is required here because sessions are used.
- `@Column(name = "create_dt") Date` uses `java.sql.Date`, which drops the time of day.
