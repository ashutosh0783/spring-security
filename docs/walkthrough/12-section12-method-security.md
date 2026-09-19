# Chapter 12: Section 12, method-level security (`section_12/`)

**Verified** on section 12: `@PostFilter` on `/contact`, the array-shaped contact API. `@PostAuthorize` on `/myLoans` was read from code (the URL rule already allows any authenticated user; the user in my runs held `ROLE_USER`).

## 1. The problem
URL rules protect *URLs*. Sometimes the decision depends on **data**: "return the loan only if…", "drop the rows the caller may not see". That needs rules on **methods**, with access to arguments and return values.

## 2. The idea
Turn on method security, then annotate methods.

| Annotation | Runs | Can see | Typical use |
|------------|------|---------|-------------|
| `@PreAuthorize("expr")` | before the call | arguments | "may this user call me with these arguments?" |
| `@PostAuthorize("expr")` | after the call | return value (`returnObject`) | "may the caller see *this* result?" |
| `@PreFilter("expr")` | before | elements of a collection **argument** (`filterObject`) | drop unwanted input items |
| `@PostFilter("expr")` | after | elements of a collection **result** | drop unwanted output items |

It works through a Spring **proxy** around your bean, so it only triggers on calls that come *through the proxy*: a `this.method()` inside the same class bypasses it.

## 3. Code walkthrough

### 3.1 Switching it on
`EazyBankBackendApplication.java`
```java
1  @SpringBootApplication
2  @EnableWebSecurity
3  @EnableMethodSecurity(jsr250Enabled = true, securedEnabled = true)
4  public class EazyBankBackendApplication { ... }
```
- **Line 3**: `@EnableMethodSecurity` activates the `@Pre/Post…` annotations. `jsr250Enabled` also enables `@RolesAllowed`, and `securedEnabled` enables the older `@Secured`.

### 3.2 `@PostAuthorize` on loans
```java
1  @GetMapping("/myLoans")
2  @PostAuthorize("hasRole('USER')")
3  public List<Loans> getLoanDetails(@RequestParam long id) { ... }
```
In `LoanRepository` a `// @PreAuthorize("hasRole('USER')")` is left commented: the same rule could be placed on the repository.

### 3.3 `@PostFilter` on contacts
`ContactController.java`
```java
1  @PostMapping("/contact")
2  // @PreFilter("filterObject.contactName != 'Test'")
3  @PostFilter("filterObject.contactName != 'Test'")
4  public List<Contact> saveContactInquiryDetails(@RequestBody List<Contact> contacts) {
5      List<Contact> returnContacts = new ArrayList<>();
6      if (!contacts.isEmpty()) {
7          Contact contact = contacts.getFirst();
8          contact.setContactId(getServiceReqNumber());
9          contact.setCreateDt(new Date(System.currentTimeMillis()));
10         Contact savedContact = contactRepository.save(contact);
11         returnContacts.add(savedContact);
12     }
13     return returnContacts;
14 }
```
- **Line 4**: the endpoint now takes and returns a **list**, because filter annotations only work on collections/arrays/streams.
- **Line 7**: only the **first** contact is saved (a demo simplification).
- **Line 3**: after the method returns, Spring removes list elements whose expression is false. Here: hide any contact named `Test`. **Important**: the row is already **saved** by then; `@PostFilter` only hides it from the response.
- **Line 2 (commented)**: `@PreFilter` would strip the item from the *input*, so it would never be saved.

## 4. Verified results
| Request | Result |
|---------|--------|
| `POST /contact` `[{"contactName":"Test", …}]` | 200 `[]` |
| `POST /contact` `[{"contactName":"Bob", …}]` | 200 `[{"contactEmail":"a@b.c","contactId":"SR411222251","contactName":"Bob","createDt":"…","message":"m","subject":"s"}]` |

## 5. Traps and senior notes
- **`@PostFilter`/`@PostAuthorize` run *after* the work is done.** A database write, an email or a payment has already happened. Use `@PreAuthorize`/`@PreFilter` when the action has side effects.
- **`@PostFilter` on big result sets loads everything first**, then discards. Filter in the query instead (or pass the user into a repository method).
- **Self-invocation bypass**: calling an annotated method from another method of the *same* class skips the proxy and its security.
- **Do not rely on the URL rule alone.** Defence in depth: a URL rule *and* a method rule means a forgotten matcher does not expose data.
- **Object-level checks belong here.** `@PostAuthorize("returnObject.customerId == authentication.principal.id")`-style rules are the fix for chapter 08's `?id=` problem.
- The API shape change (single object → array) is a **breaking change** for existing clients of `/contact` (the Angular UI in `bank-app-ui` has its own copy per section).
