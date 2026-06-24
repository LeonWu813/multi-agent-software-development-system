# Style Examples

Concrete before/after examples for every convention in SKILL.md. Each section shows what to avoid and what to write instead.

---

## 1. Naming

### Variables and functions — camelCase; descriptive over abbreviations

**JavaScript/TypeScript**

```ts
// BAD
const uid = getUser(req);
const isAuth = checkToken(t);
const rt = 5000;
function procReq(r) { /* ... */ }

// GOOD
const userId = getUser(req);
const isAuthenticated = checkToken(token);
const requestTimeout = 5000;
function processRequest(request) { /* ... */ }
```

**Python**

```python
# BAD
uid = get_user(req)
is_auth = check_token(t)
rt = 5000
def proc_req(r): ...

# GOOD
user_id = get_user(req)
is_authenticated = check_token(token)
request_timeout = 5000
def process_request(request): ...
```

### Classes — PascalCase

```ts
// BAD
class userService { /* ... */ }
class httpClient { /* ... */ }

// GOOD
class UserService { /* ... */ }
class HttpClient { /* ... */ }
```

```python
# BAD
class userService: ...
class httpClient: ...

# GOOD
class UserService: ...
class HttpClient: ...
```

### Constants — UPPER_SNAKE_CASE

```ts
// BAD
const maxRetries = 3;
const apiBaseUrl = "https://api.example.com";

// GOOD
const MAX_RETRIES = 3;
const API_BASE_URL = "https://api.example.com";
```

```python
# BAD
max_retries = 3
api_base_url = "https://api.example.com"

# GOOD
MAX_RETRIES = 3
API_BASE_URL = "https://api.example.com"
```

### Files — kebab-case for modules; PascalCase for React components and class files

```
// BAD
UserService.ts        (utility module, not a class file)
authhelper.ts
PaymentProcessor.ts   (should be PascalCase — this one is actually fine as a class file)
userprofile.tsx       (React component)

// GOOD
user-service.ts       (utility module)
auth-helper.ts
PaymentProcessor.ts   (class file)
UserProfile.tsx       (React component)
```

---

## 2. Error Handling

### Silent catch (bad) vs log-and-rethrow with context (good)

**JavaScript/TypeScript**

```ts
// BAD — swallows the error; caller has no idea what happened
async function loadUserProfile(userId: string) {
  try {
    return await db.users.findById(userId);
  } catch (err) {
    // silent — nothing happens
  }
}

// GOOD — wraps with context and rethrows
async function loadUserProfile(userId: string) {
  try {
    return await db.users.findById(userId);
  } catch (err) {
    throw new Error(`Failed to load user profile for userId=${userId}`, { cause: err });
  }
}
```

**Python**

```python
# BAD
def load_user_profile(user_id: str):
    try:
        return db.users.find_by_id(user_id)
    except Exception:
        pass  # silent

# GOOD
def load_user_profile(user_id: str):
    try:
        return db.users.find_by_id(user_id)
    except Exception as exc:
        raise RuntimeError(f"Failed to load user profile for user_id={user_id}") from exc
```

### Generic Error (bad) vs typed/named error class (good)

**JavaScript/TypeScript**

```ts
// BAD — generic; callers can't distinguish error types
throw new Error("Not authorized");

// GOOD — typed; callers can catch specifically
class AuthorizationError extends Error {
  constructor(message: string, public readonly userId: string) {
    super(message);
    this.name = "AuthorizationError";
  }
}

throw new AuthorizationError("Token expired", userId);
```

**Python**

```python
# BAD
raise Exception("Not authorized")

# GOOD
class AuthorizationError(Exception):
    def __init__(self, message: str, user_id: str) -> None:
        super().__init__(message)
        self.user_id = user_id

raise AuthorizationError("Token expired", user_id=user_id)
```

---

## 3. Logging

### String interpolation (bad) vs structured key-value (good)

**JavaScript/TypeScript**

```ts
// BAD — unstructured; impossible to query in log aggregators
console.log(`User ${userId} logged in from ${ipAddress}`);
console.log("Payment failed: " + orderId);

// GOOD — structured; each field is independently queryable
logger.info("user.login", { userId, ipAddress });
logger.error("payment.failed", { orderId, reason: err.message });
```

**Python**

```python
# BAD
logging.info(f"User {user_id} logged in from {ip_address}")
logging.info("Payment failed: " + order_id)

# GOOD — use extra dict for structured fields
logger.info("user.login", extra={"user_id": user_id, "ip_address": ip_address})
logger.error("payment.failed", extra={"order_id": order_id, "reason": str(exc)})
```

### Wrong log level (bad) vs correct level (good)

**JavaScript/TypeScript**

```ts
// BAD — using error for a routine event; using info for a real failure
logger.error("User logged in", { userId });          // routine — should be info
logger.info("Database connection refused", { host }); // failure — should be error
logger.info("Cache miss on key", { key });            // dev detail — should be debug

// GOOD
logger.info("user.login", { userId });
logger.error("db.connection_refused", { host });
logger.debug("cache.miss", { key });
```

**Python**

```python
# BAD
logger.error("User logged in", extra={"user_id": user_id})
logger.info("Database connection refused", extra={"host": host})
logger.info("Cache miss on key", extra={"key": key})

# GOOD
logger.info("user.login", extra={"user_id": user_id})
logger.error("db.connection_refused", extra={"host": host})
logger.debug("cache.miss", extra={"key": key})
```

### Never log sensitive data

```ts
// BAD
logger.info("user.auth", { userId, password, authToken });

// GOOD
logger.info("user.auth", { userId });
// omit password and authToken entirely
```

```python
# BAD
logger.info("user.auth", extra={"user_id": user_id, "password": password, "token": token})

# GOOD
logger.info("user.auth", extra={"user_id": user_id})
```

---

## 4. Test Structure

### Vague name + implementation testing (bad) vs descriptive name + behavior testing (good)

**Jest (JavaScript/TypeScript)**

```ts
// BAD — vague name; tests internal implementation detail (mock call count)
test("auth test 3", () => {
  const result = authenticate("user@example.com", "wrongpassword");
  expect(mockDb.calls.length).toBe(1); // testing how, not what
});

// GOOD — describes observable behavior; asserts on output
test("returns 401 when password does not match", async () => {
  // Arrange
  const credentials = { email: "user@example.com", password: "wrongpassword" };

  // Act
  const response = await authenticate(credentials);

  // Assert
  expect(response.status).toBe(401);
  expect(response.body.error).toBe("Invalid credentials");
});
```

**pytest (Python)**

```python
# BAD
def test_auth():
    result = authenticate("user@example.com", "wrongpassword")
    assert mock_db.call_count == 1  # testing implementation

# GOOD
def test_returns_401_when_password_does_not_match():
    # Arrange
    credentials = {"email": "user@example.com", "password": "wrongpassword"}

    # Act
    response = authenticate(credentials)

    # Assert
    assert response.status_code == 401
    assert response.json()["error"] == "Invalid credentials"
```

### Missing AAA structure (bad) vs clear Arrange-Act-Assert (good)

**Jest**

```ts
// BAD — no structure; hard to see what's being tested
test("calculates order total with discount", () => {
  expect(calculateTotal([{ price: 100 }, { price: 50 }], 0.1)).toBe(135);
});

// GOOD — explicit AAA sections
test("applies percentage discount to order subtotal", () => {
  // Arrange
  const items = [{ price: 100 }, { price: 50 }];
  const discountRate = 0.10;

  // Act
  const total = calculateTotal(items, discountRate);

  // Assert
  expect(total).toBe(135); // (100 + 50) * 0.90
});
```

**pytest**

```python
# BAD
def test_order_total():
    assert calculate_total([{"price": 100}, {"price": 50}], 0.1) == 135

# GOOD
def test_applies_percentage_discount_to_order_subtotal():
    # Arrange
    items = [{"price": 100}, {"price": 50}]
    discount_rate = 0.10

    # Act
    total = calculate_total(items, discount_rate)

    # Assert
    assert total == 135  # (100 + 50) * 0.90
```

---

## 5. Commit Messages

Conventional commits format: `type(scope): description`

| Bad | Good |
|-----|------|
| `fixed stuff` | `fix(auth): resolve token expiry check off-by-one error` |
| `WIP` | `feat(checkout): add address validation step to order flow` |
| `updated login page` | `refactor(login): extract form validation into useLoginForm hook` |
| `tests` | `test(payments): add edge cases for zero-amount transactions` |
| `Jan 12 changes` | `chore(deps): upgrade express from 4.18 to 4.19` |

**Type reference:**

| Type | When to use |
|------|-------------|
| `feat` | New feature visible to users or callers |
| `fix` | Bug fix |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or updating tests only |
| `docs` | Documentation only |
| `chore` | Tooling, dependencies, build scripts |

---

## 6. File Organization

### Type-grouped (bad) vs feature-grouped (good)

**Bad — grouped by layer**

```
src/
  controllers/
    auth-controller.ts
    orders-controller.ts
    products-controller.ts
  models/
    user.ts
    order.ts
    product.ts
  services/
    auth-service.ts
    order-service.ts
    product-service.ts
  utils/
    auth-utils.ts
    email.ts
```

Problems: adding a feature requires touching four separate directories; unrelated files sit next to each other; deleting a feature means hunting across the whole tree.

**Good — grouped by feature**

```
src/
  auth/
    auth-controller.ts
    auth-service.ts
    auth-utils.ts
    index.ts            ← public API only
  orders/
    orders-controller.ts
    order-service.ts
    order.ts
    index.ts
  products/
    products-controller.ts
    product-service.ts
    product.ts
    index.ts
  shared/
    email.ts
    db-client.ts
```

Benefits: all auth code lives together; deleting a feature is one directory deletion; index.ts gates what the rest of the app can import.

**Index file rule — public API only**

```ts
// BAD — re-exporting internals leaks implementation details
// auth/index.ts
export { AuthController } from "./auth-controller";
export { hashPassword, compareHash } from "./auth-utils";   // internal helper
export { JWT_SECRET } from "./auth-utils";                  // internal constant

// GOOD — only what callers need
// auth/index.ts
export { AuthController } from "./auth-controller";
export type { AuthResult, LoginCredentials } from "./auth-service";
```
