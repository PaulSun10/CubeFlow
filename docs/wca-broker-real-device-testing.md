# WCA Broker: Controlled iPhone Test

Broker is now the default authentication owner in Debug and Release. This guide describes
manual iPhone acceptance; local tests/builds are not proof of live OAuth success.
`CUBEFLOW_WCA_BROKER_MOCK` is a DEBUG-only test override, ignored in Release.
The obsolete native OAuth application was permanently destroyed by its owner. Its grant,
refresh, storage implementation and fallback configuration have been removed. Old on-device
records are neither read nor migrated nor deleted by this retirement; returning Broker
users retain their existing v2 session. There is no alternative authentication provider.

## Before You Start

Ask Web Chat to confirm API Contract v1 readiness at `https://api.cubeflow.com.cn`:

- HTTPS/DNS/trusted certificate chain and persistent Broker storage are ready.
- The backend-only WCA application has the correct client configuration and exact registered redirect:
  `https://api.cubeflow.com.cn/v1/oauth/wca/callback`.
- Native redirect remains `cubeflow-wca://oauth/callback` with `ticket` + independent App State,
  or `error=access_denied` + App State. No tokens are returned in the URL.
- Production OAuth is enabled only after your explicit authorization. App code cannot enable it.
- `/healthz` success is NOT confirmation of any of the above, or of a valid login/session.

Use automatic date/time on the phone. Start has no server clock-calibration field;
the app conservatively rejects implausible/expired transaction deadlines.
You alone enter your password and approve WCA authorization. Do not share those details.

## Xcode Setup

1. Open `CubeFlow.xcodeproj`, select the **CubeFlow app target** and its **Debug** build settings.
2. Search **Active Compilation Conditions** (Swift Compiler - Custom Flags).
3. Use the normal Debug setting, with no Broker activation flag:

   ```text
   $(inherited) DEBUG
   ```

4. Remove `CUBEFLOW_WCA_BROKER_MOCK` if present. Do not add a runtime preference,
   or change the OAuth registration/redirect URL. No new scheme/configuration is needed.
5. Select the existing CubeFlow scheme and your own unlocked iPhone as the run destination.
   Confirm Run uses Debug. Use your normal signing team and build/run from Xcode yourself.
   Do not uninstall the app or erase its data; existing Broker sessions and app data must be preserved.
6. Open Xcode's console. `[CubeFlow WCA Broker] realTestMode` confirms the real-test assembly.
   Construction does not start login or make a request. The iPhone root starts v2 session
   restoration/profile acquisition at launch; Settings joins the same idempotent operation.
   Neither opens a login browser automatically, and restoration after logout is not repeated.

Release uses the same Broker implementation but does not compile the DEBUG console logging
or Mock factory. No activation flag or fallback provider is supported.

For device Keychain evidence, optionally select only `WCABrokerRealKeychainTests` under the
CubeFlowTests target in Xcode's Test navigator and run that class on your iPhone. Remove the Broker
development overrides from the app target first. Do not open Settings or manually initiate
restoration in the test host. The test class remaps every
Security.framework call to a fresh test-only namespace, uses synthetic fixtures, and cleans up afterward.
Do not run destructive tests against `wca_auth_session_v2` or legacy records. Device protection
attributes and actual locked-device failure behavior are not established by desktop tests.

## Login and Functional Checks

1. Open Settings and the existing WCA connection section; tap its Sign In/Connect WCA action.
2. Confirm the authorization page is the official `www.worldcubeassociation.org` page.
   Personally sign in and approve access. Never enter credentials into an app diagnostic screen.
3. Return through the system browser callback. Confirm your account name/WCA ID appears.
   Profile loading failure should retain the session and offer retry, not exchange the ticket again.
4. Open My Competitions, refresh the profile, and check My Results. Public result queries remain public
   and should also work for an available public profile while not signed in.
5. Open/close Settings repeatedly. There should be no repeated restoration or duplicate login browser.
6. During an explicit login, cancel, then try again. Try backgrounding/foregrounding the app without
   starting another login. The owner must remain stable; a stale callback must not complete a new attempt.
7. After successful login, terminate/relaunch and reopen Settings. Verify v2 restoration/profile recovery
   without a new authorization browser. If an uncompleted login was terminated, start a fresh login instead.
8. Sign out from the account page. Verify profile and v2 session presentation clear. A Keychain failure
   must show storage-unavailable, not successful sign-out. Retry should retry logout, not reload old credentials.
9. Sign in again if desired. Confirm the old account's profile/competition response never appears for the new one.

No app-side background polling, automatic authorization, or account-wide WCA revocation is implemented.
Broker logout revokes this Broker session only; it does not promise to revoke WCA tokens or other devices.

## Refresh and Failure Checks

- Profile refresh is not necessarily OAuth token refresh: an unexpired access token is reused.
- Natural access expiry or a real WCA 401 triggers the shared Broker refresh and at most one retry
  of the original WCA request. Do not edit production tokens, export credentials or change device time to force this.
- The app persists the operation UUID and send count before dispatch. A logical refresh has at most
  two sends, same UUID; budgets and Retry-After survive restart. No retry storm or new UUID bypass is permitted.
- A structured provider failure marks uncertainty; an old cached HTTP 200 cannot repair it.
  Generic 503 cannot distinguish server maintenance/disabled OAuth from uncertainty. Fresh sign-in may be required.
- Lost/ambiguous Complete responses require fresh authorization, never ticket replay.
- Deterministic live refresh timing would require a separately authorized Web-side test facility or controlled
  provider fixture. Contract v1 exposes no such endpoint. Do not add one or change provider tokens for this test.
- Locked-device accessibility and system-browser scene transitions require actual iPhone observation;
  desktop Keychain and Mock tests do not establish these behaviors.

## Safe Failure Report

Share iOS/app build version, the action sequence, foreground/background/termination timing,
the visible non-sensitive status, and only lines prefixed `[CubeFlow WCA Broker]`.
These contain fixed event names (for example `startSucceeded`, `callbackValidated`, `completeSucceeded`,
`sessionPersisted`, `profileLoaded`, `refreshUncertain`, `logoutLocalCleared`).

Do not share the full Xcode network console, authorization/callback URLs, response bodies, headers,
passwords, codes, tickets, App State, verifier, access/refresh/Broker tokens or idempotency UUIDs.
Do not send screenshots of credential entry or sensitive address bars.

## Web Chat Handoff - Real OAuth Test Readiness

- Origin: `https://api.cubeflow.com.cn`; implementation-backed API Contract v1.
- HTTPS callback: `https://api.cubeflow.com.cn/v1/oauth/wca/callback`.
- Native callback: `cubeflow-wca://oauth/callback?ticket=<ticket>&state=<app_state>`;
  denial uses `error=access_denied&state=<app_state>`.
- App-side Broker assembly is the shipping default and uses the existing connection UI, v2 Keychain,
  native browser and separate WCA access-token transport. No real authorization has been performed by Codex.
- Confirm TLS, backend WCA application/redirect, credential readiness, encryption/storage persistence,
  refresh replay/uncertainty semantics and explicit permission before enabling OAuth.
- The user reported production enablement on 2026-10-27 and successful Debug and signed Release
  iPhone E2E, including login, restoration, profile, competitions, results, logout/re-login and
  core functionality. The subsequent app-only retirement still needs a signed-device smoke check;
  do not infer physical acceptance of new source from an unsigned build.
- Health success alone is insufficient. User authorization and Web readiness precede the manual iPhone login.
