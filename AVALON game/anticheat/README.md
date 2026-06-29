# 🛡️ Anti‑cheat (server‑side vote tally) — optional add‑on

## The problem
The game is **serverless** (browser + Firebase Realtime DB only). Players write their
team‑vote (`approve`/`reject`) and quest‑card (`success`/`fail`) to the shared room, and the
**host's browser** tallies them. Because the room is readable, a technically‑skilled player can
open the browser console and read those raw values **before the reveal** — seeing who failed a
quest, or Merlin's voting pattern.

You can't fix this with client code alone: if the values are hidden from players, the host (also a
player) can't tally them either. The fix is a **Cloud Function** (trusted server code) that tallies
the hidden votes and writes back only the aggregate.

> ⚠️ Cloud Functions require the Firebase **Blaze (pay‑as‑you‑go)** plan. For a casual game among
> friends this is usually unnecessary — only set this up if you want competitive‑grade fairness.

## How it works
1. **Security rules** make `teamVotes` and `missionVotes` **write‑only**: a player may write *their
   own* entry but nobody (not even the host) can *read* the subtree.
2. A **Cloud Function** (admin access, bypasses rules) watches those paths. While votes come in it
   publishes only a **count of who has voted** (`voteProgress` — ids, no values). When everyone has
   voted it computes the result, writes the aggregate (`approve/reject` or `successes/fails`), and
   **deletes the raw votes**.
3. The **client** reads the safe `voteProgress`/result instead of the raw votes.

## Files here
- `functions-index.js` → copy to your Functions project as `functions/index.js`.
- `database.rules.json` → the Realtime Database security rules (merge with your existing rules).

## Deploy (once)
```bash
npm i -g firebase-tools
firebase login
firebase init functions        # choose your project, JavaScript
# replace functions/index.js with functions-index.js here
firebase deploy --only functions
# paste database.rules.json into Console → Realtime Database → Rules (or firebase deploy --only database)
```

## Client integration
This add‑on changes how the client reads votes. I kept the **live game untouched** so nothing
breaks before you deploy. When you're ready, tell me and I'll wire the client to the secure paths
behind a `SECURE_TALLY` flag (so it auto‑uses the function when present, and falls back otherwise).
That part needs to be tested against your deployed function.
