# Chapter 04: Sections 4–5, users in a database (`section4/`, `section5/`)

Section 5's code is **identical** to section 4 (I diffed every file). It is a theory section about *encoding vs encryption vs hashing*; the code you read here covers both.
*Read from code only; not run.*

## 1. The problem
Users hard-coded in memory vanish on restart and cannot grow. Real users live in a database, and their passwords must never be stored readably.

## 2. The idea
Spring Security only needs one thing from you: **"given a username, give me a `UserDetails`"**. That contract is `UserDetailsService`.
Implement it against your own table and the rest of the login machinery (password check, session) works unchanged.

| Technique | Reversible? | Use for |
|-----------|-------------|---------|
| Encoding (Base64) | yes, no key | data formats, never secrets |
| Encryption (AES) | yes, with a key | data you must read back later |
| **Hashing** (bcrypt) | **no** | passwords: store the hash, compare hashes on login |

## 3. Code walkthrough

### 3.1 The table and entity
`sql/scripts.sql` (customer part) and `model/Customer.java`
```java
1  @Entity @Table(name = "customer") @Getter @Setter
2  public class Customer {
3      @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
4      private long id;
5      private String email;
6      private String pwd;
7      @Column(name = "role")
8      private String role;
9  }
```
- **Line 3**: `IDENTITY` lets MySQL's `AUTO_INCREMENT` generate the id.
- The seed rows: `happy@example.com` with `{noop}EazyBytes@12345` (role `read`) and `admin@example.com` with a `{bcrypt}` hash (role `admin`).
- The same script also creates the old `users` / `authorities` tables used by `JdbcUserDetailsManager` (see the commented-out bean in the config). We do not use them.

### 3.2 The repository
```java
1  @Repository
2  public interface CustomerRepository extends CrudRepository<Customer, Long> {
3      Optional<Customer> findByEmail(String email);
4  }
```
**Line 3**: Spring Data derives `SELECT ... WHERE email = ?` from the method name. No SQL written.

### 3.3 The bridge to Spring Security
`config/EazyBankUserDetailsService.java`
```java
1  @Service @RequiredArgsConstructor
2  public class EazyBankUserDetailsService implements UserDetailsService {
3      private final CustomerRepository customerRepository;
4      @Override
5      public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
6          Customer customer = customerRepository.findByEmail(username).orElseThrow(() ->
7                  new UsernameNotFoundException("User details not found for the user: " + username));
8          List<GrantedAuthority> authorities = List.of(new SimpleGrantedAuthority(customer.getRole()));
9          return new User(customer.getEmail(), customer.getPwd(), authorities);
10     }
11 }
```
- **Line 5**: called by Spring Security during login. `username` is whatever the client typed; here we treat it as the **email**.
- **Lines 6–7**: no such user → throw the specific exception. The framework turns it into a generic "bad credentials" so attackers cannot tell whether the email exists.
- **Line 8**: the role column becomes one authority.
- **Line 9**: return Spring's own `User` (implements `UserDetails`) holding the **stored (encoded) password**. The framework compares it with what the client sent using the `PasswordEncoder`; you never compare passwords yourself here.

Because this class is a `@Service` bean of type `UserDetailsService`, Boot's default `DaoAuthenticationProvider` picks it up automatically.

### 3.4 Registration
`controller/UserController.java`
```java
1  @PostMapping("/register")
2  public ResponseEntity<String> registerUser(@RequestBody Customer customer) {
3      try {
4          String hashPwd = passwordEncoder.encode(customer.getPwd());
5          customer.setPwd(hashPwd);
6          Customer savedCustomer = customerRepository.save(customer);
7          if (savedCustomer.getId() > 0) { return ResponseEntity.status(HttpStatus.CREATED).body("Given user details are successfully registered"); }
8          else { return ResponseEntity.status(HttpStatus.BAD_REQUEST).body("User registration failed"); }
9      } catch (Exception ex) {
10         return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("An exception occurred: " + ex.getMessage());
11     }
12 }
```
- **Line 4**: `DelegatingPasswordEncoder` encodes with the default algorithm and **adds `{bcrypt}`**. That prefix is what lets login find the right algorithm later.
- **Line 6**: the entity is deserialized straight from the request body, so a caller can also set `role`. See traps.

### 3.5 The config
```java
1  http.csrf(csrfConfig -> csrfConfig.disable())
2      .authorizeHttpRequests((requests) -> requests
3          .requestMatchers("/myAccount", "/myBalance", "/myLoans", "/myCards").authenticated()
4          .requestMatchers("/notices", "/contact", "/error", "/register").permitAll());
```
- **Line 1**: CSRF is switched **off** so a plain `POST /register` from Postman works. Chapter 08 turns it back on properly.
- **Line 4**: `/register` must be public (nobody can log in before registering).

## 4. Traps and senior notes
- **Mass assignment on `/register`.** Binding `@RequestBody Customer` lets a client post `"role":"admin"`. Use a dedicated request DTO and set the role on the server. (Section 12's run confirmed `/register` accepts a client-supplied `role`.)
- **`{noop}` seed users** are plaintext; a demo convenience only.
- **Do not log or return `pwd`.** From section 8 the entity marks `pwd` `@JsonProperty(access = WRITE_ONLY)` for this reason.
- **Catching `Exception` and returning its message** (lines 9–10) leaks internals to clients.
