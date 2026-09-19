# Chapter 09: Section 9, authorities and roles (`section9/`)

*Read from code; role behaviour confirmed on section 12/16 runs.*

## 1. The problem
"Logged in" is not enough. Some URLs are for customers only, some for admins. Section 8 stored one `role` string on the customer; that cannot express "this user has several permissions".

## 2. The idea
* **Authority**: a fine-grained permission string, e.g. `VIEWACCOUNT`.
* **Role**: a coarse group, by convention an authority that starts with **`ROLE_`**, e.g. `ROLE_USER`.
* `hasAuthority("X")` checks the exact string; `hasRole("X")` checks **`ROLE_X`**.

One customer has many authorities: a **one-to-many** table.

## 3. Code walkthrough

### 3.1 The new table and entity
```sql
CREATE TABLE `authorities` (
  `id` int NOT NULL AUTO_INCREMENT,
  `customer_id` int NOT NULL,
  `name` varchar(50) NOT NULL,
  PRIMARY KEY (`id`),
  CONSTRAINT `authorities_ibfk_1` FOREIGN KEY (`customer_id`) REFERENCES `customer` (`customer_id`)
);
```
The script first inserts `VIEWACCOUNT`, `VIEWCARDS`, `VIEWLOANS`, `VIEWBALANCE` for customer 1, then `DELETE FROM authorities` and inserts **`ROLE_USER`** and **`ROLE_ADMIN`**. The lesson is in that order: first authorities, then the switch to roles. After loading, `happy@example.com` has `ROLE_USER` and `ROLE_ADMIN` (verified in MySQL).

`model/Authority.java` and the new collection on `Customer`
```java
1  @Entity @Getter @Setter @Table(name="authorities")
2  public class Authority {
3      @Id @GeneratedValue(strategy = GenerationType.IDENTITY) private long id;
4      private String name;
5      @ManyToOne @JoinColumn(name="customer_id") private Customer customer;
6  }
```
```java
// in Customer
1  @OneToMany(mappedBy = "customer", fetch = FetchType.EAGER)
2  @JsonIgnore
3  private Set<Authority> authorities;
```
- **Line 5 / `mappedBy`**: `Authority` owns the foreign key; `Customer` just mirrors it.
- **`EAGER`**: load authorities together with the customer, because login needs them immediately and the `UserDetailsService` runs outside a transaction (lazy loading would fail).
- **`@JsonIgnore`**: never serialize authorities into `/user` responses (and avoids an infinite loop Customer ↔ Authority).

### 3.2 Loading them at login
`EazyBankUserDetailsService` changes one line:
```java
1  List<GrantedAuthority> authorities = customer.getAuthorities().stream()
2          .map(authority -> new SimpleGrantedAuthority(authority.getName()))
3          .collect(Collectors.toList());
4  return new User(customer.getEmail(), customer.getPwd(), authorities);
```
The DB value is used **verbatim**. So `ROLE_USER` must be stored *with* the prefix for `hasRole("USER")` to match.

### 3.3 URL rules
```java
1  .authorizeHttpRequests((requests) -> requests
2          /*.requestMatchers("/myAccount").hasAuthority("VIEWACCOUNT")
3          .requestMatchers("/myBalance").hasAnyAuthority("VIEWBALANCE", "VIEWACCOUNT") ... */
4          .requestMatchers("/myAccount").hasRole("USER")
5          .requestMatchers("/myBalance").hasAnyRole("USER", "ADMIN")
6          .requestMatchers("/myLoans").hasRole("USER")
7          .requestMatchers("/myCards").hasRole("USER")
8          .requestMatchers("/user").authenticated()
9          .requestMatchers("/notices", "/contact", "/error", "/register", "/invalidSession").permitAll());
```
Lines 2–3 (commented) are the authority version; lines 4–7 the role version. Other options you will meet: `permitAll`, `denyAll`, `authenticated`, `hasAnyAuthority`.

### 3.4 Denial events
`events/AuthorizationEvents.java`
```java
1  @Component @Slf4j
2  public class AuthorizationEvents {
3      @EventListener
4      public void onFailure(AuthorizationDeniedEvent deniedEvent) {
5          log.error("Authorization failed for the user : {} due to : {}", deniedEvent.getAuthentication().get().getName(), deniedEvent.getAuthorizationResult());
6      }
7  }
```
The authorization twin of chapter 07's listener: every 403 gets logged with the user and the reason.

## 4. Verified behaviour (sections 12 and 16)
| Situation | Result |
|-----------|--------|
| Token/user with `ROLE_USER`, `GET /myAccount` | 200 |
| Section 16 token with scope `openid` only (`ROLE_openid`), `GET /myAccount` | **403** `"Access Denied"` |
| No credentials | **401** |

## 5. Traps and senior notes
- **`hasRole("USER")` vs an authority named `USER`**: they do **not** match. The `ROLE_` prefix mismatch is the most common authorization bug.
- **401 vs 403**: 401 = "I don't know who you are", 403 = "I know you, and no".
- **URL rules only cover URLs.** A service method called from elsewhere is unprotected; chapter 12 adds method-level rules.
- **Keep the admin's `ROLE_ADMIN` and user's `ROLE_USER` distinct in the data**: `happy@example.com` holds both here, which is why `/myBalance` (USER or ADMIN) and `/myAccount` (USER only) both work for the same login.
