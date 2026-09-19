# Chapter 10: Section 10, custom filters (`section_10/`)

Verified on section 12 (contains the same filters, wiring and behaviour): the "test" email rejection returned **400**.

## 1. The problem
You need a rule that is not "who are you / what may you do": validate a header, log something, stamp a response. That belongs in a **filter**.

## 2. The idea
A filter sees every request before the controller. In Spring Security the filters form an **ordered chain**; you can insert yours *before*, *after* or *at the position of* a built-in one.

```
... CorsFilter → CsrfFilter → [RequestValidationBeforeFilter] → BasicAuthenticationFilter(+ AuthoritiesLoggingAtFilter) → [AuthoritiesLoggingAfterFilter, CsrfCookieFilter] → AuthorizationFilter → controller
```

`addFilterBefore(f, X)` runs `f` just before `X`, `addFilterAfter(f, X)` just after, `addFilterAt(f, X)` **at the same position**. It does *not replace* X; both run, in unspecified order relative to each other.

## 3. Code walkthrough

### 3.1 Registering
```java
1  .addFilterAfter(new CsrfCookieFilter(), BasicAuthenticationFilter.class)
2  .addFilterBefore(new RequestValidationBeforeFilter(), BasicAuthenticationFilter.class)
3  .addFilterAfter(new AuthoritiesLoggingAfterFilter(), BasicAuthenticationFilter.class)
4  .addFilterAt(new AuthoritiesLoggingAtFilter(), BasicAuthenticationFilter.class)
```
plus `@EnableWebSecurity(debug = true)` on the application class: it prints the full list of filters for each request. **Debug mode is for development only** (Spring warns about it loudly at startup).

### 3.2 A "before" filter that rejects requests
`filter/RequestValidationBeforeFilter.java`
```java
1  public class RequestValidationBeforeFilter implements Filter {
2      public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) throws IOException, ServletException {
3          HttpServletRequest req = (HttpServletRequest) request;
4          HttpServletResponse res = (HttpServletResponse) response;
5          String header = req.getHeader(HttpHeaders.AUTHORIZATION);
6          if (null != header) {
7              header = header.trim();
8              if (StringUtils.startsWithIgnoreCase(header, "Basic ")) {
9                  byte[] base64Token = header.substring(6).getBytes(StandardCharsets.UTF_8);
10                 byte[] decoded;
11                 try {
12                     decoded = Base64.getDecoder().decode(base64Token);
13                     String token = new String(decoded, StandardCharsets.UTF_8);   // un:pwd
14                     int delim = token.indexOf(":");
15                     if (delim == -1) { throw new BadCredentialsException("Invalid basic authentication token"); }
16                     String email = token.substring(0, delim);
17                     if (email.toLowerCase().contains("test")) {
18                         res.setStatus(HttpServletResponse.SC_BAD_REQUEST);
19                         return;
20                     }
21                 } catch (IllegalArgumentException exception) {
22                     throw new BadCredentialsException("Failed to decode basic authentication token");
23                 }
24             }
25         }
26         chain.doFilter(request, response);
27     }
28 }
```
- **Lines 5–9**: only Basic credentials are inspected. **Lines 12–16**: decode `base64(user:pass)` and cut at the first `:`.
- **Lines 17–19**: business rule "no usernames containing *test*". It sets **400** and **returns without calling `chain.doFilter`**: the request stops here. That `return` is the whole power of a filter.
- **Line 26**: for everyone else, hand the request on. **Forgetting this line makes every request hang or return an empty 200.**
- **Line 22 / 15**: throwing `BadCredentialsException` from a plain filter is *not* translated into a tidy 401 (the exception-translation filter sits later in the chain), so treat these lines with care.

### 3.3 "At" and "after" filters
```java
1  @Slf4j
2  public class AuthoritiesLoggingAtFilter implements Filter {
3      public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain) throws IOException, ServletException {
4          log.info("Authentication Validation is in progress");
5          chain.doFilter(request, response);
6      }
7  }
```
```java
1  // AuthoritiesLoggingAfterFilter.doFilter
2  Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
3  if (null != authentication) {
4      log.info("User " + authentication.getName() + " is successfully authenticated and has the authorities " + authentication.getAuthorities().toString());
5  }
6  chain.doFilter(request, response);
```
The "after" filter can read the `Authentication` because `BasicAuthenticationFilter` has already run and stored it in the `SecurityContextHolder`. A "before" filter could not.

### 3.4 `OncePerRequestFilter`
`CsrfCookieFilter` (chapter 08) extends `OncePerRequestFilter` instead of implementing `Filter`. Prefer it: it guarantees one execution per request even if the request is forwarded internally, and gives typed `HttpServletRequest/Response`. It also has `shouldNotFilter(request)` to skip paths (chapter 11 uses that).

## 4. Verified behaviour (section 12)
| Request | Result |
|---------|--------|
| `GET /user` with Basic `test@example.com:x` | **400**, empty body |

## 5. Traps and senior notes
- **Always call `chain.doFilter`** unless you deliberately end the request.
- **A filter that reads the request body consumes it.** Wrap the request if later code needs it.
- **Do not create filters as `@Component` beans** if you also `addFilter…` them: Boot registers `@Component` filters in the servlet chain **again**, so they run twice. This repo uses `new`, which avoids it.
- Blocking usernames by substring ("test") is a demo rule; real validation belongs in the auth provider or service.
