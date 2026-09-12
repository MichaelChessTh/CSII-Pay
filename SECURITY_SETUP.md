# Security setup

Nodes refuse to start until two secrets exist. They are read from the process
environment, or from a `.env` file next to `node.py`.

## 1. Create the `.env` file

```bash
cp .env.example .env
python3 -c "import secrets; print('CSII_GENESIS_PASSWORD=' + secrets.token_urlsafe(48))" >> .env
python3 -c "import secrets; print('CSII_JWT_SECRET=' + secrets.token_urlsafe(48))" >> .env
```

Open `.env`, remove the empty placeholder lines, and set `CSII_ALLOWED_ORIGINS`
to the origins your Flutter web build is served from.

`.env` is ignored by git and by Docker (`.gitignore`, `.dockerignore`). Check
before your first commit:

```bash
git check-ignore .env   # should print .env
```

## 2. Rules for the two secrets

| Variable | Purpose | Who must share it |
|---|---|---|
| `CSII_GENESIS_PASSWORD` | Password of the Student Council account `6958082456`. The council key pair is derived from it. | Every node on the same chain |
| `CSII_JWT_SECRET` | HMAC key for access and refresh tokens. Any node can verify tokens issued by any other node. | Every node behind the same gateway |

Rotating `CSII_JWT_SECRET` logs everyone out; that is the intended way to
revoke all sessions at once.

The council account's key pair is derived from `CSII_GENESIS_PASSWORD`, so a
chain that already contains council-signed transactions (account verifications)
will not validate under a new value. Rotating it therefore means starting a new
chain: delete `node_*_chain.json` / `node_*.db` on every node and replace the
Firestore chain backup. The previous value `123` was committed to this
repository, so rotate before any real use.

## 3. Deploying

- **Docker / Koyeb:** pass the two variables as platform secrets. Do not bake
  `.env` into the image.
- **Gateway:** set `CSII_GATEWAY_TLS_TERMINATED=1` only when Cloudflare or
  another TLS terminator sits in front of it. Nodes should listen on loopback
  or a private network; the gateway is the only public entry point.
- **Council portal:** cookies are `Secure` by default. For plain-HTTP local
  testing set `COUNCIL_INSECURE_COOKIE=1`.

## 4. What the API now expects from clients

1. `POST /login` or `POST /register` returns `access_token` (15 min) and
   `refresh_token` (30 days). The private key is no longer returned; clients
   derive it locally from the password and the returned `salt`.
2. Every other `POST` except `/tx/submit`, `/auth/refresh`, `/block/new`,
   `/peers/add` and `/contracts/query` requires `Authorization: Bearer <access_token>`.
   Identity fields in the body (`account_id`, `sender`, `creator`, `author`) must
   match the token subject or the request is rejected with 403.
3. `POST /tx/submit` accepts only transactions carrying a real secp256k1
   signature and a nonce. Placeholder signatures (`DIRECT*`, `TEST_BYPASS`) are
   rejected at the network boundary.
4. `POST /auth/refresh` with `{"refresh_token": ...}` rotates both tokens.
   Reusing a consumed refresh token revokes the whole session family.
5. `POST /auth/logout` (Bearer) revokes the current access token and, if sent,
   the refresh token.
6. `/login` is limited to 10 requests per IP per ~50 seconds and locks an
   account for 30 s, doubling each failure, after 5 wrong passwords.

## 5. Still open after this change

- Password hashes written to the chain by earlier registrations remain
  readable via `GET /chain`. New chain epochs should carry only public keys.
- Keys are still derived from the password (client-side now). Client-generated
  keys and challenge–response login are the next step.
- The Flutter app stores the refresh token and private key in
  `SharedPreferences`; move them to `flutter_secure_storage`.
- `/block/new` and `/peers/add` are unauthenticated peer endpoints.
- Firestore `network_config/*` (gateway URL and the chain backup a fresh node
  restores from) and `users/*` are world-writable in `firestore.rules`. Locking
  them requires `tunnel_manager.py` and the node's cloud sync to write with a
  service account first; until then anyone can redirect clients or replace the
  backup chain.
