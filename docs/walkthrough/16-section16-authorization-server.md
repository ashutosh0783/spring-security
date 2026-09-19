# Chapter 16: Section 16, be your own authorization server (`section_16/authserver`, `springsecsection_16`)

**Verified** end to end (Boot 4.0.0, JDK 25, MySQL 8.4): discovery document, client-credentials tokens (JWT and opaque), JWKS, resource-server checks (200/401/403). The interactive authorization-code + PKCE flow and opaque-token introspection through the resource server were **not run** (they need a browser / are commented out).

## 1. The problem
Chapter 15 relied on Keycloak. Sometimes you must **be** the token issuer: embedded in your product, or with custom rules.

## 2. The idea
**Spring Authorization Server** turns a Spring Boot app into an OAuth2 / OpenID Connect provider. Two apps:

| App | Port | Job |
|-----|------|-----|
| `authserver` | 9000 | issues tokens, publishes keys |
| `springsecsection_16` | 8080 | the chapter 15 resource server, pointed at port 9000 |

Grants used here:
* **client_credentials**: machine to machine, no user. The *client* is the identity.
* **authorization_code (+ PKCE)**: a human logs in at the auth server, the app receives a code and swaps it for tokens. **PKCE** proves the app that started the flow is the one finishing it; it replaces the client secret for public clients (SPAs, mobile).

## 3. Code walkthrough: `authserver/config/ProjectSecurityConfig.java`

### 3.1 Two filter chains
```java
1  @Bean @Order(1)
2  public SecurityFilterChain authorizationServerSecurityFilterChain(HttpSecurity http, RegisteredClientRepository registeredClientRepository, AuthorizationServerSettings authorizationServerSettings) throws Exception {
3      OAuth2AuthorizationServerConfigurer authorizationServerConfigurer = new OAuth2AuthorizationServerConfigurer();
4      http.securityMatcher(authorizationServerConfigurer.getEndpointsMatcher())
5          .with(authorizationServerConfigurer, (authorizationServer) -> authorizationServer.oidc(Customizer.withDefaults()))
6          .authorizeHttpRequests((authorize) -> authorize.anyRequest().authenticated())
7          .exceptionHandling((exceptions) -> exceptions.defaultAuthenticationEntryPointFor(
8                  new LoginUrlAuthenticationEntryPoint("/login"), new MediaTypeRequestMatcher(MediaType.TEXT_HTML)))
9          .oauth2ResourceServer((resourceServer) -> resourceServer.jwt(Customizer.withDefaults()));
10     return http.build();
11 }
12 @Bean @Order(2)
13 public SecurityFilterChain defaultSecurityFilterChain(HttpSecurity http) throws Exception {
14     http.authorizeHttpRequests((authorize) -> authorize.anyRequest().authenticated()).formLogin(Customizer.withDefaults());
15     return http.build();
16 }
```
- **Lines 1, 12**: `@Order` matters: chain 1 claims only the OAuth2 endpoints (line 4: `getEndpointsMatcher()`); everything else falls to chain 2.
- **Line 5**: `.oidc(...)` enables OpenID Connect: `/.well-known/openid-configuration`, `/userinfo`, ID tokens.
- **Lines 7–8**: a browser that arrives at `/oauth2/authorize` unauthenticated is redirected to the **login form**; API callers still get 401.
- **Line 9**: the auth server accepts its own access tokens (e.g. for `/userinfo`).
- **Line 14**: chain 2 provides the form login page users see during the authorization-code flow. Users come from the `customer`/`authorities` tables through `EazyBankUserDetailsService` + `EazyBankUsernamePwdAuthenticationProvider`. **This** provider (in the `authserver` project) does check `passwordEncoder.matches` and throws `BadCredentialsException("Invalid password!")`, unlike chapter 06's dev provider.

### 3.2 Registered clients
```java
1  RegisteredClient clientCredClient = RegisteredClient.withId(UUID.randomUUID().toString())
2          .clientId("eazybankapi")
3          .clientSecret("{noop}...")
4          .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_BASIC)
5          .authorizationGrantType(AuthorizationGrantType.CLIENT_CREDENTIALS)
6          .scopes(scopeConfig -> scopeConfig.addAll(List.of(OidcScopes.OPENID, "ADMIN", "USER")))
7          .tokenSettings(TokenSettings.builder().accessTokenTimeToLive(Duration.ofMinutes(10))
8                  .accessTokenFormat(OAuth2TokenFormat.SELF_CONTAINED).build()).build();
```
- **Line 3**: `{noop}` again: secrets stored as plain text (and committed to Git; see traps). **Line 4**: the client sends `client_id:secret` as an HTTP Basic header.
- **Line 6**: the scopes this client may request. **Line 8**: `SELF_CONTAINED` = a **JWT**; `REFERENCE` = opaque.

The four clients:

| Client | Grant | Token | Purpose |
|--------|-------|-------|---------|
| `eazybankapi` | client_credentials | JWT | service-to-service; scopes `openid`, `ADMIN`, `USER` |
| `eazybankintrospect` | client_credentials | **opaque** | the credentials the resource server would use to call `/oauth2/introspect` |
| `eazybankclient` | authorization_code + refresh_token | JWT | confidential web app; secret via POST or Basic; redirect `https://oauth.pstmn.io/v1/callback` (Postman); `reuseRefreshTokens(false)` = **rotating refresh tokens**; refresh lifetime 8 h |
| `eazypublicclient` | authorization_code + refresh_token | JWT | public SPA: `ClientAuthenticationMethod.NONE` and `requireProofKey(true)` (**PKCE mandatory**) |

They are stored in memory (`InMemoryRegisteredClientRepository`): restart and they are recreated; add a JDBC repository for real use.

### 3.3 Signing keys
```java
1  @Bean
2  public JWKSource<SecurityContext> jwkSource() {
3      KeyPair keyPair = generateRsaKey();
4      RSAKey rsaKey = new RSAKey.Builder((RSAPublicKey) keyPair.getPublic()).privateKey((RSAPrivateKey) keyPair.getPrivate()).keyID(UUID.randomUUID().toString()).build();
5      return new ImmutableJWKSet<>(new JWKSet(rsaKey));
6  }
```
An **RSA 2048** key pair is generated **at every startup** (line 3), with a random key id (`kid`, line 4). The public half is served at `/oauth2/jwks`; the resource server uses it to verify tokens. **Restarting the auth server invalidates every token issued before**, and the resource server must re-fetch keys. In production, load a persistent key.

### 3.4 Putting roles into the token
```java
1  @Bean
2  public OAuth2TokenCustomizer<JwtEncodingContext> jwtTokenCustomizer() {
3      return (context) -> {
4          if (context.getTokenType().equals(OAuth2TokenType.ACCESS_TOKEN)) {
5              context.getClaims().claims((claims) -> {
6                  if (context.getAuthorizationGrantType().equals(AuthorizationGrantType.CLIENT_CREDENTIALS)) {
7                      Set<String> roles = context.getClaims().build().getClaim("scope");
8                      claims.put("roles", roles);
9                  } else if (context.getAuthorizationGrantType().equals(AuthorizationGrantType.AUTHORIZATION_CODE)) {
10                     Set<String> roles = AuthorityUtils.authorityListToSet(context.getPrincipal().getAuthorities()).stream()
11                             .map(c -> c.replaceFirst("^ROLE_", "")).collect(Collectors.collectingAndThen(Collectors.toSet(), Collections::unmodifiableSet));
12                     claims.put("roles", roles);
13                 }
14             });
15         }
16     };
17 }
```
- **Line 7–8**: for machine clients, **scopes are copied into `roles`** (asking for `scope=USER` grants "role USER").
- **Lines 10–12**: for a human login, the customer's authorities are used, with `ROLE_` stripped (the resource server re-adds it).
- This is the contract with the resource server: a top-level **`roles`** claim.

### 3.5 The resource-server side
`springsecsection_16` differs from chapter 15 in only three places:
```properties
spring.security.oauth2.resourceserver.jwt.jwk-set-uri=${JWK_SET_URI:http://localhost:9000/oauth2/jwks}
```
```java
1  ArrayList<String> roles = (ArrayList<String>) source.getClaims().get("roles");
2  if (roles == null || roles.isEmpty()) { return new ArrayList<>(); }
3  Collection<GrantedAuthority> returnValue = roles.stream().map(roleName -> "ROLE_" + roleName).map(SimpleGrantedAuthority::new).collect(Collectors.toList());
```
the `KeycloakRoleConverter` reads `roles` instead of `realm_access.roles` (line 1), and `KeycloakOpaqueRoleConverter` reads the introspection `scope` attribute. Note the class is *still named Keycloak…* though no Keycloak is involved.

## 4. Verified results
**Auth server (port 9000)**
| Call | Result |
|------|--------|
| `GET /.well-known/openid-configuration` | JSON with `issuer: http://localhost:9000`, `authorization_endpoint`, `token_endpoint`, … |
| `POST /oauth2/token` (Basic `eazybankapi`, `grant_type=client_credentials`, `scope=openid USER`) | 200 `access_token` (JWT) |
| Token header | `{"kid":"a73f8e4b-…","alg":"RS256"}` |
| Token payload | `{"sub":"eazybankapi","aud":"eazybankapi","nbf":…,"scope":["openid","USER"],"roles":["openid","USER"],"iss":"http://localhost:9000","exp":…,"iat":…,"jti":"…"}` (exp − iat = 600 s) |
| `GET /oauth2/jwks` | `{"keys":[{"kty":"RSA","e":"AQAB","kid":"a73f8e4b-…","n":"…"}]}` |
| Same call as `eazybankintrospect` | 200 `access_token` = a long random string (opaque) |
| Wrong client secret | **401** |

**Resource server (port 8080, `JWK_SET_URI` pointing at the auth server)**
| Call | Result |
|------|--------|
| `GET /notices` | 200 (public) |
| `GET /myAccount?email=happy@example.com` no token | **401** |
| … with the `USER` token: `/myAccount`, `/myBalance`, `/myCards`, `/myLoans` | **200** each, real data |
| … with a token altered by one character | **401** |
| … with a token whose scope was only `openid` (`ROLE_openid`) on `/myAccount` | **403** `{"timestamp": "…", "status": 403, "error": "Forbidden", "message": "Access Denied", "path": "/myAccount"}` |
| … `USER` token asking for `?email=` of a different customer | 200 (empty list for a non-existent email; **no ownership check exists**) |

The tampered-token **401** (vs chapter 11's **500**) shows the payoff of using Spring's built-in resource-server support.

## 5. Traps and senior notes
- **Client secrets are committed** (`{noop}` plain text) in `ProjectSecurityConfig` and the Postman file. Rotate them, hash them (`{bcrypt}`), and inject via config in any real use.
- **Keys regenerate on every restart** → all tokens die; and any resource server caching keys may reject tokens until it refreshes. Persist the key.
- **`jwk-set-uri` skips issuer validation.** Use `issuer-uri: http://localhost:9000` so the resource server checks `iss` (and can auto-discover keys).
- **From inside Docker, `localhost` is wrong.** The resource server needs the auth server's container/host name (my run used `http://as16:9000/oauth2/jwks`). The token's `iss` still says `localhost:9000`, another reason to configure the issuer explicitly.
- **Scopes-as-roles for client credentials** lets any client ask for `ADMIN` if registered for it. Register each client with the **minimum** scopes.
- **Use PKCE for every browser/mobile client** and rotate refresh tokens (`reuseRefreshTokens(false)`, already done here).
- **Keep the resource server's role converter aligned** with the token customizer (`roles`). This is a shared contract with no compiler to enforce it; cover it with a test.
- **In-memory clients/authorizations** do not survive restarts or work across replicas; use the JDBC implementations for anything real.
