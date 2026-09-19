# Chapter 14: Section 14, OAuth2 social login (`section_14/springsecOAUTH2`)

*Read from code only; not run (needs real GitHub/Facebook OAuth apps and a browser).*

## 1. The problem
You do not want to manage passwords at all. "Sign in with GitHub" lets a provider you trust prove who the user is.

## 2. The idea
OAuth2's **authorization code flow**, with your app as the **client**:

```
1 browser → your app: "log in with GitHub"
2 your app → browser: redirect to github.com/login/oauth/authorize?client_id=…&redirect_uri=…&state=…
3 user logs in at GitHub and approves
4 GitHub → browser → your app: redirect back with ?code=abc&state=…
5 your app → GitHub (server to server): code + client_secret  →  access token
6 your app → GitHub: fetch the user's profile with the token
7 your app: creates the session for that user
```
The password never touches your app; the **code** is useless without your client secret; `state` blocks forged redirects.

| Role | Here |
|------|------|
| Resource owner | the person logging in |
| Client | this Spring app |
| Authorization/resource server | GitHub, Facebook |

## 3. Code walkthrough

### 3.1 The config
`config/ProjectSecurityConfig.java`
```java
1  @Bean
2  SecurityFilterChain defaultSecurityFilterChain(HttpSecurity httpSecurity) throws Exception {
3      httpSecurity.authorizeHttpRequests((requests) -> requests.requestMatchers("/secure").authenticated()
4                      .anyRequest().permitAll())
5              .formLogin(Customizer.withDefaults())
6              .oauth2Login(Customizer.withDefaults());
7      return httpSecurity.build();
8  }
```
- **Line 3–4**: only `/secure` needs login; `anyRequest().permitAll()` is the catch-all (contrast with the closed-by-default chains earlier).
- **Line 5**: the classic username/password form still works (`eazybytes` / `12345` from properties).
- **Line 6**: `oauth2Login` adds the whole redirect dance above and a generated login page (at `/login`) listing every configured provider.

### 3.2 Configuring providers: properties, not code
`application.properties`
```properties
1  spring.security.oauth2.client.registration.github.client-id=${GITHUB_CLIENT_ID:...}
2  spring.security.oauth2.client.registration.github.client-secret=${GITHUB_CLIENT_SECRET:...}
3  spring.security.oauth2.client.registration.facebook.client-id=${FACEBOOK_CLIENT_ID:...}
4  spring.security.oauth2.client.registration.facebook.client-secret=${FACEBOOK_CLIENT_SECRET:...}
```
GitHub and Facebook are on Spring's built-in list (`CommonOAuth2Provider`), so **only id and secret** are needed: endpoints, scopes and the callback URL pattern (`/login/oauth2/code/{registrationId}`) are known. The commented-out `ClientRegistrationRepository` bean in the config shows the same thing in Java.

### 3.3 The protected page
`controller/SecureController.java`
```java
1  @Controller
2  public class SecureController {
3      @GetMapping("/secure")
4      public String securePage(Authentication authentication) {
5          if (authentication instanceof UsernamePasswordAuthenticationToken usernamePasswordAuthenticationToken) {
6              System.out.println(usernamePasswordAuthenticationToken);
7          } else if (authentication instanceof OAuth2AuthenticationToken oAuth2AuthenticationToken) {
8              System.out.println(oAuth2AuthenticationToken);
9          }
10         return "secure.html";
11     }
12 }
```
- **Line 4**: Spring injects the current `Authentication`. Its **type tells you how the user logged in**: `UsernamePasswordAuthenticationToken` (form) or `OAuth2AuthenticationToken` (social).
- **Line 10**: returns the static page `static/secure.html`.

## 4. Traps and senior notes
- **Real OAuth client secrets are committed in this repo** as property defaults (and in a commented block in the config). Treat them as leaked: **revoke and regenerate them at GitHub and Facebook**, then supply them only through `GITHUB_CLIENT_ID/SECRET` and `FACEBOOK_CLIENT_ID/SECRET` environment variables (remove the defaults). Never commit secrets, even for demos.
- **Register the callback exactly** (`http://localhost:8080/login/oauth2/code/github`) in each provider's console; a mismatch is the usual first failure.
- **Social login proves identity, not your app's roles.** After login you still need your own user record and role mapping.
- **`System.out.println` of an authentication** can leak tokens/attributes into logs.
- `anyRequest().permitAll()` is easy to forget when adding new pages: add new protected URLs explicitly, or flip the default to `anyRequest().authenticated()`.
