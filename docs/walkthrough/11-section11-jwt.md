# Chapter 11: Section 11, JWT and stateless security (`section_11/`, same code in `section_12/`)

**Verified** on section 12 (Boot 4.0.0, JDK 25, MySQL 8.4): login, token contents, token use, tampering, wrong password.

## 1. The problem
Sessions live in server memory: hard to scale across servers, and useless for mobile/API clients. We want the server to **remember nothing** and still know who is calling.

## 2. The idea
Issue the client a **JWT** (JSON Web Token) after login. The client sends it on each request; the server checks the signature and trusts the claims inside.

`header.payload.signature`, each part Base64URL-encoded:
```
header    {"alg":"HS256"}
payload   {"iss":"Eazy Bank","sub":"JWT Token","username":"happy@example.com","authorities":"ROLE_ADMIN,ROLE_USER","iat":1789815534,"exp":1789845534}
signature HMAC-SHA256(header.payload, secret)
```
The payload is **encoded, not encrypted**: anyone can read it (I decoded a real token with `base64 -d`). The signature only proves it was not altered. Never put secrets in a JWT.

Analogy: a wristband at a festival. Staff do not look you up; they check the wristband is genuine and unexpired.

## 3. Code walkthrough

### 3.1 Go stateless
`config/ProjectSecurityConfig.java`
```java
1  http.sessionManagement(sessionConfig -> sessionConfig.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
2      .cors(... config.setExposedHeaders(Arrays.asList("Authorization")) ...)
3      .csrf(csrfConfig -> csrfConfig.csrfTokenRequestHandler(csrfTokenRequestAttributeHandler)
4              .ignoringRequestMatchers("/contact", "/register", "/apiLogin")
5              .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse()))
6      .addFilterAfter(new JWTTokenGeneratorFilter(), BasicAuthenticationFilter.class)
7      .addFilterBefore(new JWTTokenValidatorFilter(), BasicAuthenticationFilter.class)
```
- **Line 1**: `STATELESS` means Spring never creates or uses an `HttpSession`. Every request must prove itself.
- **Line 2**: `exposedHeaders("Authorization")` lets browser JavaScript **read** the token header from a cross-origin response.
- **Line 4**: `/apiLogin` joins the CSRF-exempt list.
- **Lines 6–7**: the generator runs after Basic auth has succeeded; the validator runs before it, so a valid token is turned into an `Authentication` first.

### 3.2 Generating the token
`filter/JWTTokenGeneratorFilter.java`
```java
1  protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
2      Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
3      if (null != authentication) {
4          Environment env = getEnvironment();
5          if (null != env) {
6              String secret = env.getProperty(ApplicationConstants.JWT_SECRET_KEY, ApplicationConstants.JWT_SECRET_DEFAULT_VALUE);
7              SecretKey secretKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
8              String jwt = Jwts.builder().issuer("Eazy Bank").subject("JWT Token")
9                      .claim("username", authentication.getName())
10                     .claim("authorities", authentication.getAuthorities().stream().map(GrantedAuthority::getAuthority).collect(Collectors.joining(",")))
11                     .issuedAt(new Date())
12                     .expiration(new Date((new Date()).getTime() + 30000000))
13                     .signWith(secretKey).compact();
14             response.setHeader(ApplicationConstants.JWT_HEADER, jwt);
15         }
16     }
17     filterChain.doFilter(request, response);
18 }
19 @Override
20 protected boolean shouldNotFilter(HttpServletRequest request) { return !request.getServletPath().equals("/user"); }
```
- **Line 2**: after Basic login the `Authentication` is in the context. **Line 6**: the secret comes from env `JWT_SECRET`, falling back to a hard-coded default. **Line 7**: `hmacShaKeyFor` needs at least 32 bytes for HS256.
- **Lines 9–10**: two custom claims: `username` and the authorities as one comma-separated string.
- **Line 12**: `30000000` **milliseconds = 30,000 s ≈ 8 h 20 min** (I decoded `exp - iat = 30000`).
- **Line 14**: the token is returned in the `Authorization` response header of `GET /user`.
- **Line 20**: the filter runs **only for `/user`**: that is the "login" URL for the Basic-auth flow.

### 3.3 Validating the token
`filter/JWTTokenValidatorFilter.java`
```java
1  String jwt = request.getHeader(ApplicationConstants.JWT_HEADER);
2  if (null != jwt) {
3      try {
4          ... SecretKey secretKey = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
5          Claims claims = Jwts.parser().verifyWith(secretKey).build().parseSignedClaims(jwt).getPayload();
6          String username = String.valueOf(claims.get("username"));
7          String authorities = String.valueOf(claims.get("authorities"));
8          Authentication authentication = new UsernamePasswordAuthenticationToken(username, null, AuthorityUtils.commaSeparatedStringToAuthorityList(authorities));
9          SecurityContextHolder.getContext().setAuthentication(authentication);
10     } catch (Exception exception) {
11         throw new BadCredentialsException("Invalid Token received!");
12     }
13 }
14 filterChain.doFilter(request, response);
15 // shouldNotFilter: return request.getServletPath().equals("/user");
```
- **Line 5**: `parseSignedClaims` checks the signature **and** the expiry. It throws if either is wrong.
- **Line 8**: rebuild the `Authentication` from claims: no database call. **Line 9**: placing it in the context is what makes later `hasRole(...)` rules work.
- **Line 11**: any failure becomes `BadCredentialsException`.
- **Line 15**: validation is skipped for `/user` (that is where Basic auth happens instead).
- The token goes in the `Authorization` header **without a `Bearer ` prefix**.

### 3.4 A JSON login for API clients
`UserController.apiLogin`
```java
1  @PostMapping("/apiLogin")
2  public ResponseEntity<LoginResponseDTO> apiLogin(@RequestBody LoginRequestDTO loginRequest) {
3      Authentication authentication = UsernamePasswordAuthenticationToken.unauthenticated(loginRequest.username(), loginRequest.password());
4      Authentication authenticationResponse = authenticationManager.authenticate(authentication);
5      if (null != authenticationResponse && authenticationResponse.isAuthenticated()) { ... build the same JWT ... }
6      return ResponseEntity.status(HttpStatus.OK).header(ApplicationConstants.JWT_HEADER, jwt).body(new LoginResponseDTO(HttpStatus.OK.getReasonPhrase(), jwt));
7  }
```
- **Line 3**: `unauthenticated(...)` = "credentials to check", not yet trusted. **Line 4**: the `AuthenticationManager` bean (declared in the config) delegates to the provider from chapter 06.
- The manager bean calls `setEraseCredentialsAfterAuthentication(false)` so the password stays available to the provider.
- The DTOs are Java records: `LoginRequestDTO(String username, String password)`, `LoginResponseDTO(String status, String jwtToken)`.
- The token-building code is **copy-pasted** from the filter. Extract a `JwtService`.

## 4. Verified results (section 12, default profile)
| # | Request | Result |
|---|---------|--------|
| 1 | `POST /apiLogin` correct password | 200 `{"status":"OK","jwtToken":"eyJhbGciOiJIUzI1NiJ9…"}` |
| 2 | decoded payload | `{"iss":"Eazy Bank","sub":"JWT Token","username":"happy@example.com","authorities":"ROLE_ADMIN,ROLE_USER","iat":…,"exp":…}` |
| 3 | `GET /myAccount?id=1` with `Authorization: <jwt>` | 200 account JSON |
| 4 | same with the token altered (`…x`) | **500** with a stack trace containing `BadCredentialsException: Invalid Token received!` |
| 5 | `GET /user` with Basic, header check | 200, response carries `Authorization: eyJhbGci…` |
| 6 | `POST /apiLogin` with a **wrong** password | **200 and a valid token** (chapter 06's missing check) |
| 7 | `GET /user` with Basic and a **wrong** password | **200** (same cause) |

## 5. Traps and senior notes
- **#6/#7 are a full authentication bypass in the default profile.** Anyone who knows a valid email gets a token.
- **#4: a bad token yields a 500 with a stack trace**, because the exception is thrown from a filter that runs before the exception translator. Return 401 directly from the filter, or use Spring's built-in resource-server support (chapters 15–16).
- **Hard-coded default secret** (`jxgEQeXHuPq8VdbyYFNkANdudQ53YUn4`): anyone with the repo can forge tokens for any user and role. Always inject `JWT_SECRET`, and fail startup if it is absent.
- **Long-lived, non-revocable tokens.** 8+ hours and no server-side kill switch. Prefer short access tokens plus refresh tokens.
- **Symmetric signing (HS256)**: every service that verifies tokens also holds the key that can *create* them. Chapter 16's RS256 splits that: only the auth server holds the private key.
- **Hand-rolled JWT filters are how security bugs happen.** They work for learning; production code should use Spring's resource-server support.
- Do not add the `Bearer ` prefix here: this validator reads the raw header value.
