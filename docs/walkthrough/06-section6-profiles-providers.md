# Chapter 06: Section 6, profiles and custom authentication providers (`section6/`)

Runtime note: the behaviour of the non-`prod` provider was **verified on section 12**, which contains the same class. The `prod` provider was read from code only (running `prod` needs HTTPS).

## 1. The problem
You want different security behaviour in development (relaxed, verbose) and production (strict, quiet), and you want to control *how* credentials are checked.

## 2. The idea
* **Profiles**: `@Profile("prod")` / `@Profile("!prod")` on a class means "only create this bean in that mode".
* **`AuthenticationProvider`**: the strategy that decides "are these credentials valid?". Spring's default is `DaoAuthenticationProvider` (loads the user, compares password hashes). You can write your own.

```
login request → AuthenticationManager (ProviderManager) → asks each AuthenticationProvider:
                    supports(this token type)?  → authenticate(...) → Authentication or exception
```

## 3. Code walkthrough

### 3.1 Two config classes
`ProjectSecurityConfig` has `@Profile("!prod")`; `ProjectSecurityProdConfig` has `@Profile("prod")`. Each declares a `SecurityFilterChain` bean, but only one is ever active.
In section 6 both have the same rules. From section 7 the dev one disables the HTTPS redirect (`redirectToHttps(https -> https.disable())`) and the prod one **requires HTTPS**.

### 3.2 Profile activation
`application.properties`
```properties
1  spring.config.import = application_prod.properties
2  spring.profiles.active = default
```
`application_prod.properties`
```properties
1  spring.config.activate.on-profile= prod
2  logging.level.org.springframework.security=${SPRING_SECURITY_LOG_LEVEL:ERROR}
3  spring.jpa.show-sql=${JPA_SHOW_SQL:false}
```
- **Line 1 (first file)**: pulls the prod file in. Its first line says "apply me only when profile `prod` is active".
- The prod file lowers the log level to `ERROR` and turns off SQL logging. Start prod with `SPRING_PROFILES_ACTIVE=prod` (env vars beat the file).

### 3.3 The two providers
`EazyBankUsernamePwdAuthenticationProvider` (`@Profile("!prod")`)
```java
1  @Override
2  public Authentication authenticate(Authentication authentication) throws AuthenticationException {
3      String username = authentication.getName();
4      String pwd = authentication.getCredentials().toString();
5      UserDetails userDetails = userDetailsService.loadUserByUsername(username);
6      return new UsernamePasswordAuthenticationToken(username, pwd, userDetails.getAuthorities());
7  }
8  @Override
9  public boolean supports(Class<?> authentication) {
10     return UsernamePasswordAuthenticationToken.class.isAssignableFrom(authentication);
11 }
```
`EazyBankProdUsernamePwdAuthenticationProvider` (`@Profile("prod")`)
```java
1  UserDetails userDetails = userDetailsService.loadUserByUsername(username);
2  if (passwordEncoder.matches(pwd, userDetails.getPassword())) {
3      return new UsernamePasswordAuthenticationToken(username, pwd, userDetails.getAuthorities());
4  } else {
5      throw new BadCredentialsException("Invalid password!");
6  }
```
- **Dev provider, line 6**: it builds a successful token **without ever comparing the password**. Any password is accepted for any existing user.
- **Prod provider, lines 2–5**: correct: compare the raw password with the stored hash via `passwordEncoder.matches`.
- `supports` (dev lines 9–10): "I handle username/password tokens only". `ProviderManager` skips providers that say no.

## 4. Verified result (section 12, default profile)
| Request | Result |
|---------|--------|
| `GET /user` with `happy@example.com:wrong` | **200** and the customer JSON |
| `POST /apiLogin` with a wrong password | **200** and a valid JWT |

Both come from the dev provider's missing password check, the most important thing to know about this repo.
Starting with `prod` on plain HTTP returned `IllegalStateException: HTTP Port '8081' does not have a corresponding HTTPS Port`: the prod chain forces an HTTPS redirect.

## 5. Traps and senior notes
- **Never ship `!prod` semantics by accident.** The "default" profile is the insecure one; a deployment that forgets `SPRING_PROFILES_ACTIVE=prod` runs with **no password check**. Safer design: make the strict provider the default and the relaxed one opt-in.
- **You rarely need a custom provider.** A `UserDetailsService` + `PasswordEncoder` already does what the prod provider does. Write a provider only for extra rules (age check, MFA, an external directory), as the comment in the prod file hints.
- **Do not build a "success" token for unverified credentials.** Only return an authenticated token after the check.
- Spring logs a startup warning: "UserDetailsService beans will not be used … Consider removing the AuthenticationProvider bean". Defining an `AuthenticationProvider` bean replaces the automatic `DaoAuthenticationProvider`.
