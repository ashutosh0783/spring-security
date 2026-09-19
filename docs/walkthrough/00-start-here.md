# Walkthrough: start here

This walkthrough explains the EazyBank security project **section by section, from scratch, with the real code walked through
line by line**. Read it the way a senior engineer would explain it to a new joiner: first *why*, then *what*, then *how the code does it*.

## How each chapter is laid out
1. **The problem**: what was missing before this section.
2. **The idea**: the concept in plain words.
3. **Code walkthrough**: real files from this repo, with **numbered lines**.
4. **Try it / verified results**: what was actually run, or "read from code only".
5. **Traps and senior notes**: things that bite in real projects.

## About the line numbers
Numbers in code blocks are **line numbers inside the excerpt**, not the original file. I removed `import` lines, blank lines and
Javadoc boilerplate so the code stays readable. The file path is printed above each excerpt.

## Chapter list (read in order)
| # | Chapter | Core idea |
|---|---------|-----------|
| 01 | [Sections 1–3: the basics](01-sections1-3-basics.md) | Default security, your own filter chain, in-memory users, password encoders |
| 04 | [Sections 4–5: users in a database](04-sections4-5-database-users.md) | `UserDetailsService`, registration, hashing |
| 06 | [Section 6: profiles and providers](06-section6-profiles-providers.md) | `@Profile`, custom `AuthenticationProvider` (and a dangerous shortcut) |
| 07 | [Section 7: sessions, errors, events](07-section7-sessions-errors-events.md) | Session limits, JSON 401/403, listening to auth events |
| 08 | [Section 8: CORS, CSRF, data](08-section8-cors-csrf-data.md) | Browser-facing defences and the full data model |
| 09 | [Section 9: roles](09-section9-roles.md) | Authorities vs roles, `hasRole` |
| 10 | [Section 10: filters](10-section10-filters.md) | Writing filters and placing them in the chain |
| 11 | [Section 11: JWT](11-section11-jwt.md) | Stateless auth with self-issued tokens |
| 12 | [Section 12: method security](12-section12-method-security.md) | `@PostAuthorize`, `@PostFilter` |
| 14 | [Section 14: social login](14-section14-social-login.md) | OAuth2 client, GitHub/Facebook |
| 15 | [Section 15: Keycloak resource server](15-section15-keycloak-resource-server.md) | Let someone else issue tokens |
| 16 | [Section 16: Spring Authorization Server](16-section16-authorization-server.md) | Be the token issuer |

Section 5 has no code change, and section 13 does not exist in the repo (theory only).

## Vocabulary you will see everywhere
| Term | Plain meaning |
|------|---------------|
| **Authentication** | Proving who you are |
| **Authorization** | Deciding what you may do |
| **Principal** | The authenticated user (`authentication.getName()`) |
| **Authority / Role** | A string permission. A *role* is an authority that starts with `ROLE_` |
| **`SecurityFilterChain`** | The bean where you describe your security rules |
| **`UserDetailsService`** | "Given a username, load the user" |
| **`PasswordEncoder`** | Hashes and compares passwords |
| **`AuthenticationProvider`** | The class that actually decides "these credentials are valid" |
| **JWT** | A signed token `header.payload.signature` that carries claims |
| **Resource server** | An API that accepts tokens |
| **Authorization server** | The service that issues tokens |

## The example data
Users: `happy@example.com` (roles USER + ADMIN, section 8+ password `EazyBytes@54321`) and the in-memory `user` / `admin`.
Full list in [../03-services-reference.md](../03-services-reference.md). Running instructions in [../04-running-with-docker.md](../04-running-with-docker.md).

## Verified vs. read-only
Chapters mark their status. Runtime-verified for this documentation: **sections 3, 12, 16**. The rest is read from code.
