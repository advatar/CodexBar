Below is a **step-by-step change request** you can hand to the CodexBar developer to add:

1) **“Team login” (join team by invite code)**  
2) **Periodic reporting of current token/usage status** to your new dashboard backend  
3) **Privacy-by-default** (no emails / identity sent)

I’m writing this to match CodexBar’s existing architecture split (**CodexBarCore = fetch/parse**, **CodexBar = state/UI**) and its existing refresh cadence + SettingsStore pattern.  [oai_citation:0‡GitHub](https://raw.githubusercontent.com/advatar/CodexBar/main/docs/architecture.md)

---

## Change Request: Team Join + Periodic Reporting (Privacy-first)

### Goal
Add a new “Team” feature so a user can **join a team using an invite code** and CodexBar will **periodically POST anonymized usage snapshots** (token/limit status) to a server endpoint.

This must be **off by default**, must **never send account emails / identity**, and must **store server token securely**.

CodexBar already has a background refresh loop with configurable cadence (Manual / 1m / 2m / 5m default / 15m / 30m) stored via `SettingsStore`.  [oai_citation:1‡GitHub](https://raw.githubusercontent.com/advatar/CodexBar/main/docs/refresh-loop.md)  
CodexBar’s CLI JSON also contains identity fields like `accountEmail`, `signedInEmail`, and `identity` blocks; those MUST be removed before reporting.  [oai_citation:2‡GitHub](https://raw.githubusercontent.com/advatar/CodexBar/main/docs/cli.md)

---

## 0) Define the server contract (constants + endpoint paths)
**Add constants** (or config) for the team server base URL and function routes:

- `POST {TEAM_SERVER_BASE_URL}/functions/v1/redeem_invite`
- `POST {TEAM_SERVER_BASE_URL}/functions/v1/report_usage`

Also add a `TEAM_SERVER_BASE_URL` field in settings (editable, but with a sensible default).

**Acceptance:** developer can change server URL without rebuilding (UserDefaults / config).

---

## 1) Add persistent Team settings + secure token storage
### 1.1 SettingsStore additions
Add a `TeamReportingSettings` struct (Codable, Sendable) saved by `SettingsStore`:

- `serverBaseURL: URL`
- `enabled: Bool` (default `false`)
- `teamId: String?` (or UUID string)
- `teamName: String?`
- `memberPublicId: String?` (the anonymized member ID shown in dashboard)
- `deviceId: String?`
- `deviceLabel: String` (default “<HostName>”)
- `reportInterval: ReportInterval`  
  - default: **match refresh frequency** (or clamp to min 5m)
- `lastReportAt: Date?`
- `lastReportResult: enum { ok, throttled, authFailed, serverError, networkError }`
- `lastReportErrorMessage: String?` (user-friendly, no tokens)

### 1.2 Keychain storage
Store the **device reporting token** in Keychain, **not** in UserDefaults / config.

- Key: `com.codexbar.team.deviceToken.<deviceId>` (or stable key per team)
- Also store `tokenLast4` (optional) for UI display without exposing the token

CodexBar already uses Keychain for various provider auth flows; follow the existing Keychain helper patterns.  [oai_citation:3‡GitHub](https://github.com/advatar/CodexBar)

**Acceptance:** No plaintext device token appears in logs, UserDefaults, or config JSON.

---

## 2) Implement “Join Team” (redeem invite) flow
Create a `TeamAPIClient` (in **CodexBarCore** or **CodexBar**—prefer Core if you want reuse with CLI) that supports:

### 2.1 `redeemInvite(inviteCode, deviceLabel, platform, appVersion)`
**Request:**
```json
{
  "invite_code": "CBT-XXXXXX-XXXX",
  "device_label": "Alice’s MacBook",
  "platform": "macos",
  "app_version": "x.y.z"
}
```

**Response expected (example):**
```json
{
  "team": { "id": "...", "name": "Team Name" },
  "member": { "public_id": "mbr_7K2P9D" },
  "device": { "id": "...", "device_label": "...", "platform": "macos", "app_version": "..." },
  "reporting": { "token": "<PLAINTEXT_DEVICE_TOKEN>", "recommended_interval_seconds": 300 },
  "claim": { "claim_code": "....", "expires_at": "....", "claim_page": "/claim" }
}
```

### 2.2 On success, persist:
- `teamId/teamName/memberPublicId/deviceId` into `SettingsStore`
- `enabled = true` (or ask user to toggle)
- Save the `reporting.token` into Keychain
- Save `recommended_interval_seconds` as suggested default (but allow override)

### 2.3 UI feedback
Show:
- “Joined Team: <name>”
- “Member ID: <public_id>” (copy button)
- “Reporting: Enabled/Disabled”
- “Last report: …”
- Optional: “Claim code” + “Open claim page” (deep link to dashboard claim screen)

**Acceptance:** entering invite code + clicking “Join” results in a stored team membership + stored token + reporting enabled.

---

## 3) Add a “Team” section in Settings UI (CodexBar target)
Add a new Settings page/tab/section: **Settings → Team**

### Required UI elements
- Toggle: **Enable Team Reporting**
- Text field: **Server URL**
- Text field: **Invite Code**
- Text field: **Device Label**
- Picker: **Report Interval**  
  - Auto (follow refresh)  
  - 1m / 2m / 5m / 15m / 30m
- Buttons:
  - **Join Team**
  - **Send Test Report Now**
  - **Leave Team** (clears token + IDs)
  - **Open Dashboard** (opens `/app/teams/<teamId>` or generic dashboard home)
- Status panel:
  - Joined team name
  - Member public ID
  - Device ID
  - Last report time / last status

**Acceptance:** user can fully configure + verify reporting from settings without CLI.

---

## 4) Build the anonymized reporting payload from in-app usage data
CodexBar already has:
- A background refresh that fills a `UsageStore` with provider usage + credits, and optionally cost usage for Codex/Claude.  [oai_citation:4‡GitHub](https://raw.githubusercontent.com/advatar/CodexBar/main/docs/refresh-loop.md)

### 4.1 Create `TeamReportBuilder`
Inputs:
- `UsageStore` latest provider models
- `SettingsStore.TeamReportingSettings`

Output:
```json
{
  "report_id": "<uuid>",
  "generated_at": "<ISO8601>",
  "client": { "platform": "macos", "app_version": "x.y.z" },
  "snapshots": [ ... ],
  "cost": [ ... optional ... ]
}
```

### 4.2 Privacy sanitizer (non-negotiable)
Implement a `TeamReportSanitizer` that guarantees:
- Remove **all identity-related fields** before encoding:
  - `usage.identity` blocks
  - `usage.accountEmail`, `accountOrganization`, `loginMethod`
  - `openaiDashboard.signedInEmail`
  - any field named `*email*`, `*identity*`, `*organization*`
- Ensure **no cookie contents**, **no file paths**, **no prompt content** are included.

This is crucial because CodexBar’s existing JSON output includes identity/email metadata in multiple locations.  [oai_citation:5‡GitHub](https://raw.githubusercontent.com/advatar/CodexBar/main/docs/cli.md)

**Acceptance:** a unit test proves that given a sample provider JSON containing `accountEmail`/`signedInEmail`, the outbound JSON contains **none** of those keys.

---

## 5) Implement the periodic reporter (schedule + throttling)
### 5.1 Add `TeamReporter` service
Responsibilities:
- Determine when to report
- Build + sanitize payload
- POST to `/functions/v1/report_usage` with Authorization

### 5.2 Scheduling strategy
Use one of these (prefer #1 because it aligns with existing architecture):

1) **Hook into the existing refresh loop completion** (recommended):  
   After a successful refresh updates `UsageStore`, call `TeamReporter.maybeReport(latestUsage)` which sends if:
   - team enabled
   - token exists
   - lastReportAt is older than reportInterval
   - and there’s at least one provider snapshot available

2) Or a separate Timer/Task loop that runs every N seconds and checks `maybeReport`.

CodexBar already has a refresh cadence concept; reuse it rather than adding a second independent scheduler.  [oai_citation:6‡GitHub](https://raw.githubusercontent.com/advatar/CodexBar/main/docs/refresh-loop.md)

### 5.3 Throttling + backoff
- If the app refreshes more frequently than report interval, do nothing.
- On network errors, retry with exponential backoff but never more than e.g. 1 attempt per minute.
- On server `401/403`, mark token invalid and set status `authFailed`, disable reporting, and prompt user to re-join.

**Acceptance:** reporting never spams the server and behaves predictably if offline.

---

## 6) Implement `report_usage` API call (auth + idempotency)
### 6.1 Request headers
- `Authorization: Bearer <deviceToken>`
- `Content-Type: application/json`
- Optional: `X-CodexBar-Device-ID: <deviceId>` (redundant but helpful)

### 6.2 Idempotency
- Generate `report_id` UUID per send attempt
- If server responds OK, save `lastReportAt`
- If server responds conflict/duplicate, treat as OK

**Acceptance:** repeated sends of the same payload do not produce duplicates server-side.

---

## 7) “Leave team” + token rotation
### 7.1 Leave
Implement “Leave Team” to:
- Clear teamId/teamName/memberPublicId/deviceId from SettingsStore
- Remove the Keychain token for that device
- Set enabled=false
- Reset status fields

### 7.2 Rotate token (optional but valuable)
If you expose it, “Rotate Token” should call a backend endpoint to revoke old + issue new token (or user re-joins).

**Acceptance:** leaving fully stops reporting and removes secrets.

---

## 8) Add CLI support (optional but recommended)
CodexBar has a bundled Commander-based CLI and a config file at `~/.codexbar/config.json`.  [oai_citation:7‡GitHub](https://raw.githubusercontent.com/advatar/CodexBar/main/docs/cli.md)  
Add commands to support headless usage and easy testing:

- `codexbar team join --server <url> --invite <code> --device-label <label>`
- `codexbar team report --once`
- `codexbar team status`
- `codexbar team leave`

Implementation notes:
- On macOS, still store the device token in Keychain (prefer).
- On Linux (CLI-only), store token in a root-only file (0600) under `~/.codexbar/`.

**Acceptance:** developer can test end-to-end join/report using only CLI.

---

## 9) Tests + QA checklist
### 9.1 Unit tests
- Sanitizer removes all identity keys (use sample JSON like the CLI doc shows).  [oai_citation:8‡GitHub](https://raw.githubusercontent.com/advatar/CodexBar/main/docs/cli.md)
- Report builder produces valid payload when one provider is enabled and has usage.

### 9.2 Manual QA (must pass)
1) Fresh install: Team Reporting disabled.
2) Join team with invite code → token saved in Keychain → member public ID shown.
3) Enable reporting and wait one interval → server receives report.
4) “Send test report now” works instantly.
5) Simulate auth failure (invalid token) → UI shows “Disconnected” and stops retrying aggressively.
6) Leave team → no further reports sent.

---

## Acceptance Criteria Summary
- **Team join** works with invite code and does not require provider logins.
- **Periodic reporting** runs at configured interval (default aligns with existing refresh cadence).
- **Privacy**: outbound payload contains **no emails**, **no identity blocks**, **no prompts/code/file paths**.  [oai_citation:9‡GitHub](https://raw.githubusercontent.com/advatar/CodexBar/main/docs/cli.md)
- **Security**: device token stored in **Keychain**, never logged.  [oai_citation:10‡GitHub](https://github.com/advatar/CodexBar)
- **User control**: can enable/disable, test, and leave.

---

If you want, I can also write the **exact JSON schema** CodexBar should emit (including which fields are required vs optional) so the developer and backend stay perfectly in sync—without ever shipping identity fields.
