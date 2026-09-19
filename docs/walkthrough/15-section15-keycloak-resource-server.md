# Chapter 15: Section 15, a resource server that trusts Keycloak (`section_15/springsecsection_15`)

*Read from code only; not run (needs a Keycloak with realm `eazybankdev`). The identical resource-server design was **verified in chapter 16**, where only the token source and role claim differ.*

## 1. The problem
Chapter 11's home-made JWT has problems: the API both **issues** and **validates** tokens, shares one symmetric secret and re-implements what standards already provide. Better: let a dedicated **authorization server** issue tokens, and let the API only **validate** them.

## 2. The idea
Split the roles:

| Role | Who | Job |
|------|-----|-----|
| Authorization server | **Keycloak** (`:8180`, realm `eazybankdev`) | authenticates users/clients, issues signed JWTs |
| Resource server | the EazyBank backend (`:8080`) | verifies tokens, enforces roles |

Keycloak signs with a **private** key; the backend downloads the matching **public** keys from Keycloak's JWKS endpoint and verifies signatures locally. The backend cannot forge a token, and needs no shared secret.

## 3. Code walkthrough

### 3.1 What was deleted
Compared with section 12, this section **removes** `/register`, `/apiLogin`, the JWT generator/validator filters, the logging filters, both custom `AuthenticationProvider`s and `EazyBankUserDetailsService`. Users and passwords now live in Keycloak; the backend has no login at all. Only `/user` and the data endpoints remain.

### 3.2 Tell Spring where the keys are
`application.properties`
```properties
1  spring.security.oauth2.resourceserver.jwt.jwk-set-uri=${JWK_SET_URI:http://localhost:8180/realms/eazybankdev/protocol/openid-connect/certs}
2  #spring.security.oauth2.resourceserver.opaque.introspection-uri=...
3  #spring.security.oauth2.resourceserver.opaque.introspection-client-id=eazybankintrospect
```
Line 1 is all the configuration needed for validation. Lines 2–3 are the alternative for **opaque tokens** (below).

### 3.3 The chain
`config/ProjectSecurityConfig.java`
```java
1  JwtAuthenticationConverter jwtAuthenticationConverter = new JwtAuthenticationConverter();
2  jwtAuthenticationConverter.setJwtGrantedAuthoritiesConverter(new KeycloakRoleConverter());
3  ...
4  http.sessionManagement(sessionConfig -> sessionConfig.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
5  ...
6      .authorizeHttpRequests((requests) -> requests
7              .requestMatchers("/myAccount").hasRole("USER")
8              .requestMatchers("/myBalance").hasAnyRole("USER", "ADMIN")
9              .requestMatchers("/myLoans").authenticated()
10             .requestMatchers("/myCards").hasRole("USER")
11             .requestMatchers("/user").authenticated()
12             .requestMatchers("/notices", "/contact", "/error", "/register").permitAll());
13 http.oauth2ResourceServer(rsc -> rsc.jwt(jwtConfigurer -> jwtConfigurer.jwtAuthenticationConverter(jwtAuthenticationConverter)));
14 http.exceptionHandling(ehc -> ehc.accessDeniedHandler(new CustomAccessDeniedHandler()));
```
- **Line 13**: one line adds `BearerTokenAuthenticationFilter`: read `Authorization: Bearer …`, decode, verify signature/expiry with the JWKS keys, build an authentication. It replaces ~100 lines of chapter 11's hand-written filters and answers **401** properly when the token is bad.
- **Lines 1–2 and 13**: how do JWT claims become Spring *authorities*? By default from the `scope` claim (as `SCOPE_x`). Keycloak puts roles elsewhere, so we plug in our own converter.

### 3.4 Mapping Keycloak roles
`config/KeycloakRoleConverter.java`
```java
1  public class KeycloakRoleConverter implements Converter<Jwt, Collection<GrantedAuthority>> {
2      @Override
3      public Collection<GrantedAuthority> convert(Jwt source) {
4          Map<String, Object> realmAccess = (Map<String, Object>) source.getClaims().get("realm_access");
5          if (realmAccess == null || realmAccess.isEmpty()) { return new ArrayList<>(); }
6          Collection<GrantedAuthority> returnValue = ((List<String>) realmAccess.get("roles"))
7                  .stream().map(roleName -> "ROLE_" + roleName)
8                  .map(SimpleGrantedAuthority::new)
9                  .collect(Collectors.toList());
10         return returnValue;
11     }
12 }
```
- **Line 4**: Keycloak's token contains `"realm_access": {"roles": ["USER", "ADMIN", …]}`.
- **Line 7**: adds the `ROLE_` prefix so `hasRole("USER")` matches. **Line 5**: no roles → no authorities → 403 on protected URLs.
- The unchecked casts (lines 4, 6) throw `ClassCastException` if the claim has another shape.

### 3.5 Controllers now take `?email=`
`LoansController`, `CardsController` etc.:
```java
1  @GetMapping("/myCards")
2  public List<Cards> getCardDetails(@RequestParam String email) {
3      Optional<Customer> optionalCustomer = customerRepository.findByEmail(email);
4      if (optionalCustomer.isPresent()) { return cardsRepository.findByCustomerId(optionalCustomer.get().getId()); } else { return null; }
5  }
```
The tokens carry no numeric customer id, so the lookup is by email.

### 3.6 The opaque-token variant (commented out)
```java
1  http.oauth2ResourceServer(rsc -> rsc.opaqueToken(otc -> otc.authenticationConverter(new KeycloakOpaqueRoleConverter())
2          .introspectionUri(this.introspectionUri).introspectionClientCredentials(this.clientId, this.clientSecret)));
```
An **opaque** token is a random string with no contents. The API must call the auth server's **introspection endpoint** on every request ("is this token active, who is it, which roles?"). It can be **revoked instantly**, at the cost of a network call per request. `KeycloakOpaqueRoleConverter` builds the authentication from the introspection response (username from `preferred_username`, roles from `realm_access.roles`).

## 4. JWT vs opaque
| | JWT (self-contained) | Opaque (reference) |
|---|----------------------|--------------------|
| Validation | local, signature check | remote introspection call |
| Revocation | hard (wait for expiry) | immediate |
| Contents visible to client | yes | no |
| Load on auth server | low | one call per API request |

## 5. Traps and senior notes
- **`jwk-set-uri` alone does not check the issuer or audience.** Anyone else's Keycloak that signs with a key you also trust would pass. Use `issuer-uri` (or add validators) in production.
- **Role mapping is your contract with the auth server.** If Keycloak stops emitting `realm_access`, every user silently loses all roles.
- **Section 15's `CustomAccessDeniedHandler` only covers 403.** For 401 the resource server uses its default Bearer entry point.
- **`?email=` is user-controlled**: any authenticated USER can read another customer's data by changing it. Compare to the token's own subject.
