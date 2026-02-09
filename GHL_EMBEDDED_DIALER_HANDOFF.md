# GHL Embedded Dialer — PR #789 Handoff Document

> **repo:** `kokayicobb/consuelo_on_call_coaching`
> **pr:** #789 — `feat: GHL Embedded Dialer with SSO and PostMessage Bridge`
> **branch:** `feature/ghl-embedded-dialer` → `main`
> **size:** 63 files, +29,983 lines, 0 files modified (all new)
> **date:** 2026-02-09

---

## table of contents

1. [agent instructions — how to work remotely](#1-agent-instructions--how-to-work-remotely)
2. [what's been built (current state)](#2-whats-been-built-current-state)
3. [critical bugs — must fix before merge](#3-critical-bugs--must-fix-before-merge)
4. [missing features vs wavv benchmark](#4-missing-features-vs-wavv-benchmark)
5. [ko's GHL-side tasks](#5-kos-ghl-side-tasks)
6. [full file inventory](#6-full-file-inventory)
7. [reference links](#7-reference-links)

---

## 1. agent instructions — how to work remotely

you are working on an existing PR in a remote repo. **do not clone the repo locally.** use the github API and `gh` CLI exclusively.

### setup

```bash
# verify auth
gh auth status

# the repo
REPO="kokayicobb/consuelo_on_call_coaching"
BRANCH="feature/ghl-embedded-dialer"

# read a file from the PR branch
gh api repos/$REPO/contents/app/ghl_embed_auth.py?ref=$BRANCH --jq '.content' | base64 -d

# update a file (create a commit on the branch)
# 1. get the current file SHA
SHA=$(gh api repos/$REPO/contents/app/ghl_embed_auth.py?ref=$BRANCH --jq '.sha')
# 2. encode new content and commit
echo -n "NEW_CONTENT" | base64 | gh api repos/$REPO/contents/app/ghl_embed_auth.py \
  -X PUT \
  -f message="fix: rewrite SSO decryption to use AES-256-CBC" \
  -f content="$(cat encoded_content.b64)" \
  -f sha="$SHA" \
  -f branch="$BRANCH"

# for multi-file atomic commits, use the git trees API:
# 1. get the latest commit SHA on the branch
# 2. create a tree with all changed files
# 3. create a commit pointing to that tree
# 4. update the branch ref
```

### workflow

1. read the file you need to change using the github contents API
2. make your edits
3. commit directly to the `feature/ghl-embedded-dialer` branch
4. after all changes, leave a PR comment summarizing what was done

### important constraints

- **do not** create a new PR — work on the existing one (#789)
- **do not** modify any files outside the `app/ghl_embed_*`, `src/`, `e2e/`, `docs/`, or `public/embedded.html` paths
- **do not** touch existing app code (non-ghl files) — this PR is additive only
- test files should be updated to match any implementation changes
- keep commit messages descriptive with conventional commit prefixes (`fix:`, `feat:`, `refactor:`)

---

## 2. what's been built (current state)

### backend (python) — 4 files

| file | lines | status | notes |
|------|-------|--------|-------|
| `app/ghl_embed_auth.py` | 1,002 | ⚠️ **has critical bug** | SSO decryption uses wrong algorithm (Fernet instead of AES-256-CBC) |
| `app/ghl_embed_routes.py` | 3,404 | ✅ mostly complete | 20+ API endpoints: OAuth, SSO, widget settings, call management, marketplace install |
| `app/ghl_embed_schema.py` | 380 | ⚠️ needs field fix | SSO token fields expect `locationId` but GHL sends `activeLocation` |
| `app/tests/test_ghl_*.py` | 3 files | ⚠️ needs update | tests will need updating after SSO fix |

### frontend (react/typescript) — 36 files

| area | files | status | notes |
|------|-------|--------|-------|
| PostMessage bridge (`src/services/ghlBridge.ts`) | 1 + tests | ✅ solid | proper origin validation, event system, deep linking |
| Auth hooks (`src/hooks/useGHLAuth.ts`) | 1 | ✅ good | SSO flow, token refresh, session management |
| Bridge hook (`src/hooks/useGHLBridge.ts`) | 1 | ✅ good | contact context, click-to-call, navigation events |
| Subscription hook (`src/hooks/useEmbeddedSubscription.ts`) | 1 | ✅ good | stripe checkout, paywall enforcement |
| Types (`src/types/ghl.ts`) | 1 | ✅ comprehensive | 400+ lines of typed interfaces |
| Embedded components (`src/components/embedded/`) | 20 files | ✅ complete | full tab UI: dialer, queue, history, files, settings |
| Pages (onboarding) | 2 | ✅ good | first-time user + SSO onboarding flows |
| Layout + entry point | 3 | ✅ good | EmbeddedApp.tsx, EmbeddedLayout.tsx, embedded-index.tsx |

### e2e tests — 8 files

| file | status | notes |
|------|--------|-------|
| `e2e/tests/ghl-embed/sso-auth.spec.ts` | ⚠️ needs update | will need updating after SSO fix |
| `e2e/tests/ghl-embed/click-to-call.spec.ts` | ✅ | |
| `e2e/tests/ghl-embed/queue-management.spec.ts` | ✅ | |
| `e2e/tests/ghl-embed/call-logging.spec.ts` | ✅ | |
| `e2e/tests/ghl-embed/subscription-paywall.spec.ts` | ✅ | |
| `e2e/fixtures/ghl-mock.ts` | ⚠️ needs update | mock SSO tokens need to use correct encryption |
| `e2e/fixtures/ghl-test-data.ts` | ✅ | |
| `e2e/utils/ghl-helpers.ts` | ⚠️ needs update | SSO helper functions |

### docs — 10 files

all docs are comprehensive and well-written. update `docs/ghl-architecture.md` and `docs/ghl-embed-setup.md` after the SSO fix to reflect the correct encryption method.

---

## 3. critical bugs — must fix before merge

### 🔴 BUG 1: SSO decryption uses wrong encryption algorithm (BLOCKING)

**the problem:**
the PR uses Python's `Fernet` encryption (`cryptography.fernet.Fernet`) to decrypt SSO tokens. but GHL encrypts SSO tokens using **OpenSSL-compatible AES-256-CBC** with MD5 key derivation (the CryptoJS format). these are completely incompatible. every real SSO token from GHL will fail to decrypt.

**where it's wrong:**
- `app/ghl_embed_auth.py` lines 85-96 — initializes `Fernet` cipher
- `app/ghl_embed_auth.py` `decrypt_sso_token()` method — calls `self.cipher.decrypt()`

**what GHL actually sends:**
GHL encrypts user data using `CryptoJS.AES.encrypt(data, sharedSecret)` which produces an OpenSSL-compatible format:
1. base64-encoded blob
2. first 8 bytes: literal string `Salted__`
3. next 8 bytes: random salt
4. remaining bytes: AES-256-CBC encrypted ciphertext
5. key + IV derived from password + salt using MD5 (EVP_BytesToKey)

**the fix — replace Fernet with AES-256-CBC decryption:**

```python
import hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding
import base64
import json

def decrypt_sso_token(self, encrypted_token: str) -> dict:
    """
    Decrypt GHL SSO token using OpenSSL-compatible AES-256-CBC.
    GHL uses CryptoJS.AES.encrypt() which produces OpenSSL format.
    """
    if not self.sso_key:
        raise GHLEmbedAuthError("SSO key not configured")

    try:
        raw = base64.b64decode(encrypted_token)

        # OpenSSL format: "Salted__" (8 bytes) + salt (8 bytes) + ciphertext
        if raw[:8] != b'Salted__':
            raise GHLEmbedAuthError("Invalid SSO token format — missing salt prefix")

        salt = raw[8:16]
        ciphertext = raw[16:]

        # EVP_BytesToKey: derive key (32 bytes) + IV (16 bytes) using MD5
        key_iv = b''
        prev = b''
        while len(key_iv) < 48:  # 32 (key) + 16 (iv)
            prev = hashlib.md5(prev + self.sso_key.encode('utf-8') + salt).digest()
            key_iv += prev

        key = key_iv[:32]
        iv = key_iv[32:48]

        # Decrypt AES-256-CBC
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv))
        decryptor = cipher.decryptor()
        padded = decryptor.update(ciphertext) + decryptor.finalize()

        # Remove PKCS7 padding
        unpadder = padding.PKCS7(128).unpadder()
        data = unpadder.update(padded) + unpadder.finalize()

        return json.loads(data.decode('utf-8'))

    except GHLEmbedAuthError:
        raise
    except Exception as e:
        logger.error(f"Failed to decrypt SSO token: {e}")
        raise GHLEmbedAuthError(f"SSO token decryption failed: {str(e)}")
```

**also update:**
- remove `from cryptography.fernet import Fernet, InvalidToken` import
- add `from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes`
- add `from cryptography.hazmat.primitives import padding`
- change `__init__` to store `self.sso_key` as a string (not a Fernet object)
- env var `GHL_EMBED_SSO_KEY` should contain the Shared Secret string from GHL app settings (not a Fernet key)

**reference implementation:** https://github.com/GoHighLevel/ghl-marketplace-app-template/blob/main/src/ghl.ts — `decryptSSOData()` method

---

### 🔴 BUG 2: SSO token field mapping is wrong (BLOCKING)

**the problem:**
`app/ghl_embed_schema.py` defines required SSO token fields as:
```python
SSO_TOKEN_FIELDS = {
    "required": ["userId", "companyId", "locationId", "email"],
    ...
}
```

but GHL's actual decrypted token structure uses `activeLocation` (not `locationId`) for the location context. the field `locationId` does not exist in the SSO token.

**GHL's actual token structure (from their docs):**
```json
{
  "userId": "MKQJ7wOVVmNOMvrnKKKK",
  "companyId": "GNb7aIv4rQFVb9iwNl5K",
  "role": "admin",
  "type": "agency",
  "activeLocation": "yLKVZpNppIdYpah4RjNE",
  "userName": "John Doe",
  "email": "user@example.com",
  "isAgencyOwner": false,
  "versionId": "695505b431a9710730ee67d7",
  "appStatus": "live"
}
```

**the fix:**
1. in `app/ghl_embed_schema.py`: change `"locationId"` to `"activeLocation"` in required fields (note: `activeLocation` is only present in location context, not agency context — may need to make it optional)
2. in `app/ghl_embed_auth.py` `get_or_create_user_mapping()`: change `token_payload["locationId"]` to `token_payload.get("activeLocation")`
3. also note: GHL uses `userName` (not `name`) — check all references to `token_payload.get("name")` and update to `token_payload.get("userName")`
4. add `type`, `isAgencyOwner`, `appStatus` to the optional fields
5. update the `GHLUser` type in `src/types/ghl.ts` to match

---

### 🟡 BUG 3: hardcoded fallback JWT secret (non-blocking but fix before prod)

**the problem:**
in `app/ghl_embed_auth.py`:
```python
self.jwt_secret = os.environ.get(
    'JWT_SECRET_KEY',
    os.environ.get('GHL_EMBED_ENCRYPTION_KEY', 'dev-secret-change-in-production')
)
```

the fallback `'dev-secret-change-in-production'` is a hardcoded secret. this was flagged by the automated security review as a blocking issue.

**the fix:**
remove the hardcoded fallback. raise an error if no JWT secret is configured:
```python
self.jwt_secret = os.environ.get('JWT_SECRET_KEY') or os.environ.get('GHL_EMBED_ENCRYPTION_KEY')
if not self.jwt_secret:
    raise ValueError("JWT_SECRET_KEY or GHL_EMBED_ENCRYPTION_KEY must be set")
```

---

## 4. missing features vs wavv benchmark

wavv is the primary competitor — they're the only other embedded dialer in GHL. here's what they offer vs what the PR implements:

| feature | wavv | PR #789 | gap |
|---------|------|---------|-----|
| embedded in GHL iframe | ✅ | ✅ | — |
| SSO authentication | ✅ | ⚠️ broken (see bug 1) | fix encryption |
| click-to-call from contacts | ✅ | ✅ | — |
| call logging to GHL CRM | ✅ | ✅ | — |
| single-line dialing | ✅ | ✅ | — |
| **multi-line dialing (3 lines)** | ✅ core feature | ❌ not implemented | **big gap** — wavv's #1 differentiator |
| **spam protection + auto-remediation** | ✅ core feature | ❌ not implemented | big gap — wavv charges extra for this |
| **local presence dialing** | ✅ | ❌ not implemented | medium gap |
| unlimited minutes | ✅ | depends on twilio pricing | pricing model decision |
| queue/campaign management | ✅ (call campaigns) | ✅ (queue management) | close — different naming |
| **callbacks for multi-line overflow** | ✅ | ❌ | only relevant if multi-line added |
| team management/reporting | ✅ | ❌ not in this PR | future feature |
| **whisper mode (coaching)** | ✅ | ❌ not in embedded | consuelo has coaching in main app but not embedded |
| subscription/paywall | ✅ | ✅ | — |
| contact context from GHL | ✅ | ✅ | — |
| deep linking | unknown | ✅ | — |
| onboarding flow | ✅ | ✅ | — |
| **spotify integration** | ✅ (pause/resume music) | ❌ | nice-to-have, low priority |
| call transfers (warm/cold) | ✅ | ❌ | medium gap |

### priority recommendations for v1 launch

**must have (fix before merge):**
1. fix SSO encryption (bug 1)
2. fix token field mapping (bug 2)
3. remove hardcoded secret (bug 3)

**should have (v1.1 — soon after launch):**
4. whisper mode / coaching in embedded view (consuelo's differentiator vs wavv)
5. call transfers (warm + cold)

**nice to have (v2+):**
6. multi-line dialing (requires significant twilio architecture)
7. spam protection integration
8. local presence dialing
9. team management dashboard
10. reporting/analytics

> **note:** multi-line dialing is wavv's core differentiator but requires significant infrastructure (multiple simultaneous twilio calls per agent). consuelo's differentiator should be the **AI coaching** — whisper mode with real-time talking points is something wavv doesn't have. lean into that.

---

## 5. ko's GHL-side tasks

these are things that need to be done in the GHL marketplace developer portal (not code):

### before testing

1. **create a GHL developer account** (if not already done)
   - go to https://marketplace.gohighlevel.com/
   - sign up for developer access

2. **create the marketplace app**
   - navigate to "My Apps" → "Create App"
   - fill in app details (name: "Consuelo Dialer", description, etc.)
   - set app type: Custom Page / Sidebar Widget

3. **generate the Shared Secret key**
   - go to app → Advanced Settings → Auth section
   - click "Generate" under Shared Secret
   - copy this key — it becomes the `GHL_EMBED_SSO_KEY` env var

4. **configure OAuth 2.0**
   - set redirect URL to your backend's OAuth callback endpoint
   - configure scopes needed: `contacts.readonly`, `conversations.readonly`, `conversations.write`, `locations.readonly`, `users.readonly`
   - set up access token + refresh token endpoints

5. **configure the Custom Page URL**
   - set the iframe URL to your deployed embedded app (e.g., `https://your-domain.com/embedded.html`)

6. **set up environment variables on railway**
   ```
   GHL_EMBED_SSO_KEY=<shared secret from step 3>
   GHL_EMBED_CLIENT_ID=<from app settings>
   GHL_EMBED_CLIENT_SECRET=<from app settings>
   GHL_EMBED_REDIRECT_URI=<your oauth callback url>
   JWT_SECRET_KEY=<generate a strong random secret>
   ```

### for marketplace submission

7. **prepare marketplace listing assets**
   - app icon (512x512)
   - screenshots of the embedded dialer in action
   - demo video (optional but recommended)
   - fill in `assets/ghl-marketplace/` directory

8. **submit for review**
   - GHL reviews marketplace apps before they go live
   - follow the checklist in `docs/ghl-marketplace-listing.md`

### for testing with wavv as reference

9. **install wavv in a test sub-account** to see how they handle:
   - sidebar placement
   - click-to-call flow
   - contact context passing
   - the overall UX

---

## 6. full file inventory

### backend
```
app/ghl_embed_auth.py          (1,002 lines) — SSO auth ⚠️ NEEDS FIX
app/ghl_embed_routes.py        (3,404 lines) — API routes
app/ghl_embed_schema.py          (380 lines) — schemas ⚠️ NEEDS FIX
app/tests/test_ghl_contact_context.py
app/tests/test_ghl_make_call.py
app/tests/test_ghl_user_mapping.py
.tests/test_ghl_sso.py
```

### frontend
```
src/EmbeddedApp.tsx                              (813 lines)
src/embedded-index.tsx                            (67 lines)
src/layouts/EmbeddedLayout.tsx                   (324 lines)
src/pages/GHLOnboardingPage.tsx                  (547 lines)
src/pages/GHLSSOOnboardingPage.tsx               (446 lines)
src/services/ghlBridge.ts                        (981 lines)
src/services/__tests__/ghlBridge.test.ts         (779 lines)
src/hooks/useGHLAuth.ts                          (291 lines)
src/hooks/useGHLBridge.ts                        (341 lines)
src/hooks/useEmbeddedSubscription.ts             (319 lines)
src/types/ghl.ts                                 (403 lines)
src/components/embedded/CompactDialPad.tsx
src/components/embedded/DialConfirmationModal.tsx
src/components/embedded/EmbeddedCoachingPanel.tsx
src/components/embedded/EmbeddedCollapsibleSection.tsx
src/components/embedded/EmbeddedContactHeader.tsx
src/components/embedded/EmbeddedDialer.tsx
src/components/embedded/EmbeddedDialerTab.tsx
src/components/embedded/EmbeddedFiles.tsx
src/components/embedded/EmbeddedFilesTab.tsx
src/components/embedded/EmbeddedFloatingActionButton.tsx
src/components/embedded/EmbeddedHeader.tsx
src/components/embedded/EmbeddedHistory.tsx
src/components/embedded/EmbeddedHistoryTab.tsx
src/components/embedded/EmbeddedPaywall.tsx
src/components/embedded/EmbeddedQueue.tsx
src/components/embedded/EmbeddedQueueTab.tsx
src/components/embedded/EmbeddedSettingsPanel.tsx
src/components/embedded/EmbeddedSubscriptionBanner.tsx
src/components/embedded/EmbeddedTabNav.tsx
src/components/embedded/index.ts
public/embedded.html                             (221 lines)
```

### e2e tests
```
e2e/tests/ghl-embed/sso-auth.spec.ts
e2e/tests/ghl-embed/click-to-call.spec.ts
e2e/tests/ghl-embed/queue-management.spec.ts
e2e/tests/ghl-embed/call-logging.spec.ts
e2e/tests/ghl-embed/subscription-paywall.spec.ts
e2e/tests/embedded/ghl-embedded.spec.ts
e2e/fixtures/ghl-mock.ts                        (836 lines)
e2e/fixtures/ghl-test-data.ts                   (794 lines)
e2e/utils/ghl-helpers.ts                        (637 lines)
```

### docs
```
docs/ghl-architecture.md
docs/ghl-api-reference.md
docs/ghl-postmessage-protocol.md
docs/ghl-embed-setup.md
docs/ghl-user-guide.md
docs/ghl-quick-start.md
docs/ghl-testing-guide.md
docs/ghl-troubleshooting.md
docs/ghl-launch-plan.md
docs/ghl-marketplace-listing.md
```

---

## 7. reference links

- **GHL SSO docs (User Context):** https://marketplace.gohighlevel.com/docs/other/user-context-marketplace-apps
- **GHL official app template (has correct SSO decryption):** https://github.com/GoHighLevel/ghl-marketplace-app-template
- **GHL OAuth docs:** https://marketplace.gohighlevel.com/docs/Authorization/authorization_doc
- **GHL External Auth docs:** https://marketplace.gohighlevel.com/docs/oauth/ExternalAuthentication
- **GHL Developer Portal:** https://marketplace.gohighlevel.com/
- **Wavv embedded dialer (competitor):** https://ghl.wavv.com/
- **Wavv features page:** https://www.wavv.com/power-dialer
- **Wavv HighLevel page:** https://www.wavv.com/highlevel
- **PR #789:** https://github.com/kokayicobb/consuelo_on_call_coaching/pull/789

---

## summary for the agent

**tl;dr:** the PR is ~90% done and very comprehensive. the architecture, frontend, postMessage bridge, and UI are all solid. there are 3 bugs to fix — 2 critical (SSO encryption algorithm mismatch + token field mapping) and 1 medium (hardcoded secret fallback). after those fixes + updating tests/docs to match, this is ready for merge and testing against a real GHL environment.

**priority order:**
1. fix `decrypt_sso_token()` in `app/ghl_embed_auth.py` — replace Fernet with AES-256-CBC (code provided above)
2. fix SSO token field mapping in `app/ghl_embed_schema.py` — `locationId` → `activeLocation`, `name` → `userName`
3. update `get_or_create_user_mapping()` in `app/ghl_embed_auth.py` to use correct field names
4. remove hardcoded JWT secret fallback
5. update backend tests (`.tests/test_ghl_sso.py`, `app/tests/test_ghl_user_mapping.py`)
6. update e2e fixtures (`e2e/fixtures/ghl-mock.ts`) to use correct encryption for mock tokens
7. update docs (`docs/ghl-architecture.md`, `docs/ghl-embed-setup.md`) to reflect AES-256-CBC
8. leave a PR comment summarizing all changes
