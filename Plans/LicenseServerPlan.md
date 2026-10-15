# License server and Paddle

Slice 16 of the high-level plan. Paddle takes payment and is the seller, but Paddle Billing doesn't make license keys, and the app can't hold Paddle's secret API key or sign its own licenses. A small license server does both. The pages people see while buying live on the Locus website. The app's side of buying, keys, and codes is slice 17.

Decided on 2026-10-03, after checking Paddle's documentation (sources at the end).

## Where each part lives

- **locus.tjdraper.com**, the existing Next.js site in the `tjdraper.com-v8` repository, holds every page a buyer sees: the product page at `/git-gui` with its pricing, the checkout, the page after paying, the terms, the refund policy, and the privacy policy. It's the only domain submitted to Paddle for approval.
- **licenses.tjdraper.com** is a PHP service in the `licenses.tjdraper.com/` folder of the `tjdraper.com-v8` repository, beside the sites, bootstrapped with `rxante/php-app-bootstrap`, in a Docker container on the same host as the tjdraper.com sites, behind the same Traefik. It holds the API the app calls, Paddle's webhooks, the license signing key, the database, the license email, and a command-line tool for running it. It serves no pages.

### Why this split

- Paddle approves each domain a checkout opens on, and approves subdomains separately. Every page Paddle's review looks for is already going on locus.tjdraper.com, so the checkout goes there too. The license server only talks to Paddle server to server (webhooks, API calls, customer portal sessions), which needs no approval.
- The license server's address is built into every copy of the app, so it gets a subdomain only it uses (see the high-level plan's Decisions). On a path of locus.tjdraper.com, wherever the website runs would have to keep forwarding that path to the license server forever, including a move to another host or stack. With Traefik, a subdomain is no more work than a path.
- PHP for the server, since it holds the signing key. Anyone with that key can make licenses for every copy of the app, so the code around it should be small, plain, and slow to change. Next.js stays on the website, where React earns its place.

## Paddle setup

- Build everything against Paddle's sandbox first. It needs no domain approval and accepts `localhost` as the checkout's address, so slices 16 and 17 can be finished before any page is public.
- One product with a monthly price of $7 and a yearly price of $59 (see the high-level plan's Decisions). The prices live in Paddle, so changing one needs no app release.
- Prices exclude tax, so a buyer pays the price plus their local tax, which Paddle adds at checkout. Each price's tax setting is exclusive; Paddle's automatic setting includes tax in places such as the UK.
- Every buyer pays in US dollars. Local currencies would need each price's own amount for each country, kept up by hand, which isn't worth it (decided 2026-10-15). The `currency` field in `GET /v1/prices` stays, so adding them later needs no app release.
- The default payment link, which Paddle uses for payment links and in its emails about updating a card, is the checkout page. It has to be on an approved domain in the live account. The sandbox's is `https://localhost/git-gui/checkout`, since its form rejects a port and plain `http`.
- The API key never expires and has only the permissions the server uses: `customer.read`, `transaction.read`, and `customer_portal_session.write`. An expiring key would quietly break the server on the day it lapsed. A leaked key gets revoked and replaced.
- Paddle's own discount codes stay switched on at checkout, for discounts on paid plans such as a launch sale.
- The live account needs account verification (domain, business, and identity), which can take a few days. Paddle approves most domains automatically, and a manual review takes about 5–7 business days. Submit locus.tjdraper.com well before launch.

### The one risk in domain approval

Paddle's domain review says: "If the domain includes unrelated products not sold through Paddle, it may lead to buyer confusion and a higher risk of chargebacks, which can impact approval." locus.tjdraper.com also has Launcher, ToDo (sold through the App Store), and Sound Control. They're one family under one name, so it should pass. If Paddle objects, the checkout moves to a subdomain of its own. The app gets the checkout's address from the license server, so that move needs no app release.

## Website pages

Built in the `tjdraper.com-v8` repository. Paddle's review needs these live before the live account can take payments:

- **Product page** (`/git-gui`): what the app is, its main features, and its prices. Prices come from `Paddle.PricePreview()` in Paddle.js, which finds the visitor's location itself and shows their tax, with no call to the license server.
- **Checkout** (such as `/git-gui/checkout`): opens Paddle's checkout with the plan and purchase id the app put in the URL, passing the purchase id as `customData`. Paddle hands `customData` back in the transaction and subscription webhooks, which is how the server knows which purchase belongs to which waiting app.
- **After paying**: opens the app through its URL scheme, and says the license key is on its way by email for when that hand-off doesn't work.
- **Terms**: `EULA.md` as a page. Paddle prefers a sole proprietor's legal name in the terms, so the agreement names Timmothy Allen Draper II, with TJ Draper as the name used through the rest of it.
- **Refund policy**: as the agreement says, Paddle's buyer terms govern refunds. The page says so and links Paddle's refund policy.
- **Privacy**: the existing `/privacy` page gains a section for this app: Paddle holds the payment details, the server keeps an email address and the license, and the license check sends no repository data.
- The pages stay unlisted until the app's release: public, so Paddle's review can see them, but left out of the site's menu and sitemap and marked `noindex`, so nobody finds them by chance. Adding them to the menu is the last item of slice 18 in the high-level plan.
- Paddle wants terms, the refund policy, and privacy "clearly accessible via navigation", which the site's menu would normally do. While the pages are unlisted, every Git Gui page links all three in its own navigation, and the domain submission gives Paddle the `/git-gui` address to start from. If Paddle still asks for the site's menu, the menu item goes in early; nothing in the app depends on when.

### Apple Pay

Apple Pay works in Paddle's checkout without extra setup, through a pop-up from a Paddle domain. Verifying the domain lets Safari show it directly. That needs Paddle's domain association file at `locus.tjdraper.com/.well-known/apple-developer-merchantid-domain-association`. Traefik currently sends all of `/.well-known` on that host to the certbot nginx container, so the rule narrows to `/.well-known/acme-challenge` and Next serves the file from `public/.well-known/`.

Apple Pay in Chrome, Firefox, and Edge, paid for by scanning a code with an iPhone, comes from Apple's Apple Pay JS SDK, which the checkout's own Apple Pay has to load. That's Paddle's checkout, not this page, and Paddle lists Apple Pay only on iPhone, iPad, and Safari on Mac (checked 2026-10-07). Buyers in Chrome get Google Pay and cards.

## The license server

### API

Under a versioned path (`/v1/…`). Copies of the app already out keep calling the paths they were built with, so each path keeps working, and keeps answering the same way, for as long as any app version still supported uses it. Adding an endpoint, or a field to a response, needs no new version, since older copies ignore what they don't know. A change that would break them, such as removing or renaming a field, changing what one means, or changing how licenses are signed, goes under `/v2/…` beside `/v1/…`. A version can be retired once no supported app version calls it. Everything outside the API, such as the pages and the checkout's address, can move.

Every request from the app carries its version and the Mac's anonymous identifier. The server keeps, for each API version, app version, and Mac, the day it last called, so it can say how many Macs called each API version in the last 30 or 90 days, and on which app versions. It counts Macs rather than requests, since one Mac refreshes every day, and keeps no log of individual requests or IP addresses. A version is safe to retire when no Mac has called it for a few months. A Mac still on it then keeps working through its 30 days offline (see the high-level plan's Decisions) and is asked to reconnect, which an update fixes.

- **Prices and the checkout's address.** The app shows prices from here and opens the checkout from the address given, so neither is built into the app.
- **A purchase's license.** The app asks for the license made for its purchase id, and keeps asking for a few minutes after opening the checkout.
- **License refresh.** At launch and once a day: the current signed license, or that it's been revoked. Each refresh carries an anonymous identifier for the Mac and the app's version, and nothing about any repository.
- **Enter a license key.** Exchanges a key for the signed license.
- **Redeem a promo code.**
- **Customer portal link.** A new portal session each time it's asked for. Paddle says not to cache them. The portal switches between monthly and yearly, updates the card, cancels, and downloads invoices. A session can include direct links for cancelling and for updating the card. Switching plans in the portal has to be switched on in Paddle, and arrives as a subscription update webhook.

#### Every request

- `https://licenses.tjdraper.com/v1/…`, with `Accept: application/json`. A request with a body sends a JSON object with `Content-Type: application/json`.
- `Locus-App-Version`: the app's version, such as `2026.1` or `2026.1.3`. Numbers separated by dots, up to four parts.
- `Locus-Mac-Id`: the Mac's anonymous identifier, a UUID the app makes once and keeps. Any UUID version.
- A request missing either header, or with one that doesn't fit, gets `invalid_client` and isn't counted.
- The server keeps only the day, in UTC, that each Mac last called each API version on each app version.

#### Errors

An error from the API is a JSON object with a status code:

```json
{"error": "license_not_found", "message": "No license has this key"}
```

The app branches on `error`, a code that never changes meaning. `message` is English for logs, and may change. A path or method that doesn't exist gets the framework's own 404 or 405, with only a `message`, so the app treats any failure without an `error` like the server being unreachable.

| `error` | Status | When |
|---|---|---|
| `invalid_client` | 400 | `Locus-App-Version` or `Locus-Mac-Id` is missing or doesn't fit |
| `invalid_request` | 400 | The body isn't a JSON object with the fields the endpoint takes |
| `license_not_found` | 404 | No license has the key, including input that can't be read as a key |
| `license_revoked` | 410 | The license has been revoked |
| `purchase_not_found` | 404 | No license has been made for the purchase id yet |
| `subscription_not_found` | 404 | The license isn't paid for by a Paddle subscription, such as one from a promo code or made by hand |

#### `POST /v1/license/enter-key` and `POST /v1/license/refresh`

Both take a key and answer with its signed license. `enter-key` is for a key the person typed or pasted, and `refresh` is the refresh at launch and once a day, with the key from the signed license the app already holds. They do the same thing today. Separate paths let them part later without copies of the app already out losing the difference.

- Request: `{"key": "LGG-7K2QM-F9XHD-3RTVA-WN8EP"}`, in any of the loose forms under License keys. The key goes in the body rather than the URL, so it stays out of access logs.
- Response, 200: `{"license": "<signed license>"}`, in the format under Licenses.
- An expired license is still signed. Its `expiresAt` says when it ended, and the app reads it like any other.
- Errors: `invalid_request`, `license_not_found`, `license_revoked`.
- Each call that finds a license counts the Mac for that license, revoked or not, so a revoked key still in use shows up.

#### `POST /v1/purchase/license`

The license made for a purchase, which the app asks for every few seconds for a few minutes after opening the checkout.

- Request: `{"purchaseId": "0199c4d2-5b1e-4a3c-9f00-000000000001"}`, the UUID the app put in the checkout's URL. Any UUID version.
- Response, 200: `{"license": "<signed license>"}`, the same as `refresh`. The key is in the signed license's payload.
- Errors: `invalid_request` (no `purchaseId`, or one that isn't a UUID), `purchase_not_found` (Paddle's webhook hasn't made the license yet, or never will), `license_revoked`.
- The server can't tell "not yet" from "never", so the app stops asking after a few minutes and tells the person the key is on its way by email.
- If one purchase id paid twice, such as a reloaded checkout page, the newer subscription's license comes back.
- A call that finds the license counts the Mac, like `refresh`.

#### `GET /v1/prices`

Each plan's price where the Mac is, and the checkout's address for it.

- Query: `product=locus-git-gui`, and `country`, the Mac's region setting as an ISO 3166-1 alpha-2 code in capitals, such as `GB`. The server passes Paddle only the country, never the Mac's IP address. Without a country, Paddle answers in the prices' own currency (US dollars), before tax.
- Response, 200:

  ```json
  {
    "currency": "USD",
    "plans": [
      {
        "plan": "monthly",
        "subtotal": "$7.00",
        "tax": "$1.40",
        "total": "$8.40",
        "checkoutUrl": "https://locus.tjdraper.com/git-gui/checkout?plan=monthly"
      },
      {"plan": "yearly", "…": "…"}
    ]
  }
  ```

- `plan` is `monthly` or `yearly`. Amounts are for one billing period, formatted by Paddle in `currency`. `subtotal` is the price before tax, and `total` is what the buyer pays. The app skips a plan it doesn't know, so plans can be added.
- The app opens `checkoutUrl` with `purchaseId=<uuid>` added to its query, and must keep any query it already has. The checkout page maps `plan` to Paddle's price id itself, since the product page needs those ids anyway.
- Errors: `invalid_request` (no `product`, one the server doesn't know, or a `country` that isn't two capital letters). A country Paddle doesn't sell to fails as the server being unreachable.
- Each call asks Paddle's pricing preview (`POST /pricing-preview`, which needs the API key's `transaction.read` permission), with nothing cached. The price ids are settings (`LOCUS_GIT_GUI_PADDLE_MONTHLY_PRICE_ID` and `…_YEARLY_PRICE_ID`), as is the checkout's address (`LOCUS_GIT_GUI_CHECKOUT_URL`), all in `.env.prod`.

#### `POST /v1/subscription/portal`

New links into Paddle's customer portal, signed in as the buyer, for Manage Subscription… and for the link to fix a declined card.

- Request: `{"key": "LGG-7K2QM-F9XHD-3RTVA-WN8EP"}`, as for `refresh`.
- Response, 200: `{"overviewUrl": "…", "cancelUrl": "…", "updatePaymentMethodUrl": "…"}`. The overview is the portal's front page. The other two open the subscription with its cancel form or card form already open, or the overview once it's paused or cancelled.
- The links expire, so the app asks for new ones each time and never keeps them.
- Errors: `invalid_request`, `license_not_found`, `license_revoked`, `subscription_not_found`.
- Anyone holding the key gets the buyer's portal, with their invoices and billing address and the power to cancel, with no email code. That's the same trust the key already carries for the app (decided 2026-10-15). A revoked license gets no portal, since a revoked key may be one posted publicly.
- Each call makes a portal session (`POST /customers/{id}/portal-sessions`, which needs the API key's `customer_portal_session.write` permission). It doesn't count the Mac.

### Licenses

- Every purchase and every redeemed promo code makes a license: a key a person can read and type, and a record of what it covers and until when.
- Each license records which product it's for and how it was granted (Paddle, a promo code, by hand, or another seller), so the server can license other products later, sold through Paddle or not.
  - Each product gets its own signing key, so a leaked key unlocks only that product.
  - Signed licenses are for software running on someone else's machine, such as a Mac app, a command-line tool, or a plugin. A hosted web app asks the license server directly instead.
- The server signs each license with an Ed25519 key, and the app checks it offline against the public key it carries (see the high-level plan's Decisions). The production signing key exists only on the server, and never in either repository.
  - The signing key is a 32-byte Ed25519 seed in base64, in a Docker secret named for its product (`LOCUS_GIT_GUI_SIGNING_KEY`). The public key the app carries is the raw 32 bytes in base64, which CryptoKit's `Curve25519.Signing.PublicKey(rawRepresentation:)` reads. `signing-key:generate` in the command-line tool makes a pair.
  - Local development has its own key pair. Its signing key is committed to `tjdraper.com-v8` at `docker/licenses.tjdraper.com/secrets/`, so every machine signs with the same key, and its public key is `JidROdKIKnsELDadN5rzv3fcOr9R3ZNa33sdFd93azQ=`. Debug builds of the app trust it. Release builds must trust only the production public key: the app picks the key by build configuration, and a test checks that a release build carries only the production key. A release build that trusted the dev key would take licenses from anyone who has that file.
  - A signed license is one line of text: the payload in base64, a `.`, and the signature in base64. Both are standard base64 with padding, which `Data(base64Encoded:)` reads. The signature covers the payload's exact bytes, so the app checks the signature against the decoded bytes before reading them as JSON, never against JSON it has encoded again.
  - The payload is a JSON object:

    | Field | Example | Meaning |
    |---|---|---|
    | `format` | `1` | The payload's format. It stays 1 for as long as fields are only added. |
    | `product` | `"locus-git-gui"` | The product the license is for |
    | `key` | `"LGG-7K2QM-F9XHD-3RTVA-WN8EP"` | The license key, formatted, for showing in the License pane |
    | `expiresAt` | `"2026-11-08T12:30:00Z"` | When the license stops working, or `null` for a lifetime license |
    | `issuedAt` | `"2026-10-08T12:30:00Z"` | When the server signed it, which the 30 days offline can count from, since the app can't fake it |

    Dates are ISO 8601 in UTC, to the second, ending in `Z`, which `ISO8601DateFormatter` reads with its default options. Fields may be added, so the app ignores any it doesn't know. A revoked license is never signed.
- The server counts the Macs that refresh each license, so a key posted publicly shows up and can be revoked.
- Revoking a license, for refunds and for keys posted publicly. A revoked license stops working at its next refresh.

### License keys

- A key only names a license and carries nothing else. What the license covers and until when is in the signed license the server returns for the key, which the app keeps and checks offline at every launch. The key is needed once, on a Mac iCloud doesn't reach, and the daily refresh brings each renewal's new date.
  - A key that carried its own dates would go stale at every renewal, and with an Ed25519 signature inside it would run past 100 characters.
- The format is a product prefix and twenty characters in groups of five: `LGG-7K2QM-F9XHD-3RTVA-WN8EP`.
  - `LGG` is Locus Git Gui. It says which product a key belongs to in a support email, and makes a key posted publicly easy to search for.
  - The characters are Crockford's base32, which leaves out I, L, O, and U, so nothing is mistaken for 0 or 1 when read aloud or typed from a printout. Twenty of them hold 100 random bits, too many to guess even without rate limiting.
  - No check character. Crockford's uses symbols such as `*` and `~` that are awkward to type. A mistyped key gets "no license with this key" from the server.
- Keys come from PHP's `random_bytes`, never from the license's UUID, whose leading timestamp makes part of it guessable.
- The app and the server accept lowercase, spaces, missing dashes, and stray line breaks from an email, and read O as 0 and I or L as 1, before looking a key up.
- Keys are stored as they are, not hashed, so the command-line tool can resend a lost one. A database leak would expose them, but a key only unlocks the app and can be revoked or reissued.

### Webhooks

- Paddle's subscription events say when a subscription starts, renews, goes past due, is paused or resumed, or is cancelled, and adjustment events carry refunds. Paddle's setup checklist lists pausing and resuming among the cases to handle, so a paused subscription is handled even though nothing in the app offers pausing.
- Every webhook's signature is checked, and a Traefik IP allowlist on the webhook route lets in only Paddle's addresses, as Paddle asks.
- Paddle can send the same event more than once and out of order, so handling one is safe to repeat and goes by the event's own time.
- Paddle posts to `https://licenses.tjdraper.com/paddle/webhook`, outside `/v1`, since only Paddle calls it and it can move. The notification destination is subscribed to `subscription.created`, `.updated`, `.activated`, `.trialing`, `.past_due`, `.paused`, `.resumed`, `.canceled`, and `adjustment.created` and `.updated`. Any other event is answered with a 200 and ignored, so a destination subscribed to too much doesn't get retried.
- The signature is an HMAC-SHA256 of `<ts>:<raw body>` with the destination's secret, in the `Paddle-Signature` header. A timestamp more than five seconds from the server's clock is refused, as Paddle's SDKs do. A bad signature gets a 401. A signed event the server can't read fails with a 500, so Paddle sends it again and the log shows why.
- The Traefik allowlist holds both Paddle's sandbox and live addresses, so going live needs no change to it.
- Each subscription webhook carries the whole subscription, so the server keeps the time of the last event it applied for each subscription and ignores any event no newer, which covers both repeats and lateness. The row is locked while an event applies, so two at once go one after the other.
- The first webhook for a subscription makes its license, whatever kind of event it is. The checkout's `customData` is `{"purchaseId": "<uuid>"}`, which Paddle copies to the subscription. A purchase id that isn't a UUID is dropped rather than failing the webhook, since the buyer's browser hands it to the checkout and could change it.
- Paddle's webhooks don't carry the customer's email, so making a license looks it up with Paddle's API (`GET /customers/{id}`, which needs the API key's `customer.read` permission). A customer Paddle doesn't have, as in the webhook simulator's sample events, makes the license with no email. Any other failure fails the webhook, which Paddle retries. A customer who later changes their email in Paddle keeps the old one on the license.
- When the license expires:
  - Active, trialing, or past due: seven days after the current billing period ends. The week covers a renewal that lands late or a Mac that doesn't refresh for a few days around one. Past due keeps working while Paddle retries the payment, as Paddle recommends, until Paddle cancels or pauses the subscription.
  - A cancellation or pause scheduled for the end of the period: exactly when it takes effect, with no extra week.
  - Cancelled or paused: when that happened.
- An approved full refund or a chargeback revokes the subscription's license. A partial refund, a credit, or a refund still waiting for Paddle's approval doesn't. Revoking doesn't cancel the subscription in Paddle; that's done in Paddle's dashboard.
- Each product the server licenses has a setting holding its Paddle product id (`LOCUS_GIT_GUI_PADDLE_PRODUCT_ID`, in `.env.prod`), which differs between the sandbox and live accounts. The license is for whichever product among the subscription's items has one. A subscription for nothing the server licenses is answered with a 200, logged, and makes no license, so the Paddle account can sell other things. A missing or empty setting fails every subscription webhook rather than quietly ignoring sales. A subscription has one license, so one for two licensed products at once fails until bundles get a license per product.

### Promo codes

- Each grants free months, free years, or a lifetime unlock. Single-use or with a redemption limit, with an optional last day to redeem.
- Redeeming needs no card and makes a license like any other.
- Redeemed while subscribed, free time moves the subscription's next billing date back through Paddle's API instead of making a second license.

### Email

The server emails the license key once Paddle confirms payment, and again when the command-line tool resends it. Paddle sends its own receipt.

- Sent through Mailgun's API, from `licenses@tjdraper.com`.
- tjdraper.com is a verified sending domain in Mailgun (confirmed 2026-10-07), so sending from a new address needs no DNS changes.
- People will reply to the license email asking for help, so `licenses@tjdraper.com` has to receive mail too. tjdraper.com's mail goes through Namecheap's email forwarding, so it needs a new forwarder there to a mailbox that's read. Not set up yet.
- The email is plain and short: the key, how to enter it, and where to get help. It holds nothing Paddle's receipt already does.

### Database

Licenses, promo codes, redemptions, the Macs that refresh each license, and the last day each Mac called each API version, on a volume that's backed up. These are sales records.

- MariaDB, in its own container on the same host, on the current long-term release (11.8 as of 2026-10-07). The host runs no database server yet, so this adds the container and a scheduled `mariadb-dump` to the backed-up volume.
- Every primary key is a UUIDv7 made in PHP with `ramsey/uuid`, stored in MariaDB's native `UUID` column type. No auto-incrementing keys. Version 7 starts with a timestamp, so new keys sort in insert order, and MariaDB's InnoDB, which keeps rows in primary-key order, adds them at the end rather than scattered through the table.

### Command-line tool

Run on the server for everything the app and Paddle don't do:

- Make, list, and retire promo codes
- Find a license by email
- Resend a license key
- Revoke a license
- Show how many Macs refresh a license
- Show how many Macs called each API version recently, and on which app versions

Each operation is written once in the service and the tool calls it, so an admin interface later wraps the same code rather than copying the tool's.

### An admin interface later

If one is built, it's a Next.js front end that calls the license server's API over the host's private network, and stays off the public internet behind Tailscale or Cloudflare Access with its own sign-in. The signing key stays in the PHP service, so a hole in the front end can't make licenses. Customers, transactions, and refunds stay in Paddle's dashboard; the admin interface only shows what Paddle doesn't hold.

## Secrets

The signing key, Paddle's API key, the webhook secret, Mailgun's API key, and the database password live only on the server, as Docker secrets. None goes in any repository; the one exception is local development's own signing key (see Licenses). The license public key is built into the app and is safe to publish. Paddle's client-side token for Paddle.js is public by design.

- Settings that aren't secret, such as the Paddle environment, price ids, and the checkout's address, live in `.env` files loaded into the container's environment.
- The app is bootstrapped with `rxante/php-app-bootstrap`, whose `RuntimeConfig` reads a setting from the environment when it's there and from Docker secrets otherwise. The environment wins, so in production a secret must never also be set in a `.env` file or the environment, where it would quietly replace the Docker secret.

## Build order

Each numbered step is one Claude session in one repository, and ends with its tests passing or its result checked. Steps marked "You" are dashboard and DNS work done by hand. Slice 17 can start once step 4 is deployed, building against the license format and API this plan records by then, and takes up purchasing, codes, and the portal as steps 5–7 add their endpoints.

| | Where | Work |
|---|---|---|
| You | Paddle | The sandbox account, the product and its two prices, an API key, and a client-side token. Done 2026-10-07; the ids and key are in 1Password. |
| 1 | License server | The `licenses.tjdraper.com/` folder in `tjdraper.com-v8`, bootstrapped with `rxante/php-app-bootstrap`; Docker for development with MariaDB; migrations; settings through `RuntimeConfig`; tests running. Done 2026-10-08. |
| 2 | License server | Licenses: their tables, key generation and loose key input, Ed25519 signing, and the command-line tool's commands to make, find, and revoke a license. The signed license's fields and encoding go into this plan's Licenses section. Done 2026-10-08: `license:make`, `license:find` (by email or key), `license:revoke`, and `signing-key:generate`. |
| 3 | License server | The app's API: refreshing and entering a key, tracking Macs and API versions, and the tool's reports on both. Each `/v1` request, response, and error goes into this plan's API section, and later steps add theirs. Also a `signing-key:public` command that prints the configured key's public half, which is how the dev public key reaches the app's Debug build. Done 2026-10-08: the two license endpoints, `license:macs` (one key's Macs, or the 20 licenses with the most in the last 30 days), `api:usage`, and `signing-key:public`. |
| 4 | License server and host | Deploying to `licenses.tjdraper.com` against the sandbox: Traefik, Docker secrets, MariaDB, and backups. You add the DNS record. Done 2026-10-15: the server runs in the tjdraper.com stack on buzzingpixel-hetzner-docker, on `rxantesystems/php-nginx:8.5.11-fpm-trixie-r1` (PHP 8.5) with MariaDB 11.8.9, and serves over HTTPS with a Let's Encrypt certificate. Production secrets are external Docker secrets with versioned names (`LICENSES_PROD_<NAME>_V1`), generated on a Mac and kept in 1Password. `docker/licenses.tjdraper.com/Secrets.md` in `tjdraper.com-v8` covers creating and rotating them. Each deploy runs `migrate:up` as a one-off service and fails if it fails. `rxante/php-app-bootstrap` 1.4.0 added `runApplication(exitWithStatusCode: true)`, so the server's `cli` exits with the command's status code. The healthcheck reports only this server's health and answers while MariaDB is down. No log keeps IP addresses: the Dockerfile strips the client IP and `X-Forwarded-For` from both the nginx and the php-fpm access log formats, and fails the build if a new base image changes them. Traefik's access log, which logged every site's client IPs, is turned off. Datadog is off (`ENABLE_DATADOG=0`), since the host has no agent, so the server's logs go to `docker service logs`. Backups aren't part of the app's stack: `site-backups` on Ivy dumps the database nightly with `mariadb-dump`. Its first run is still to be confirmed. |
| 5 | License server | Webhooks: signature checks, the IP allowlist, repeated and out-of-order events, licenses made and changed, and the purchase's license endpoint. Tried with Paddle's webhook simulator against the deployed server, so no tunnel to a laptop is needed. Done 2026-10-15: `POST /paddle/webhook`, `POST /v1/purchase/license`, the `paddle_subscriptions` table, and two new Docker secrets, `PADDLE_API_KEY` and `PADDLE_WEBHOOK_SECRET` (`LICENSES_PROD_PADDLE_…_V1`). `LOCUS_GIT_GUI_PADDLE_PRODUCT_ID` holds the sandbox product. The sandbox notification destination is subscribed to the ten events. Tried against the deployed server: a request from outside Paddle gets Traefik's 403; the simulator's sample `subscription.created` was answered and ignored; an edited one made a license the purchase endpoint returned; and an edited full, approved refund revoked it. The simulator only lets you edit a payload after a first run, and its editor shows the event's `data` without the wrapper. |
| 6 | License server | Prices and the checkout's address, and customer portal links. Done 2026-10-15: `GET /v1/prices` and `POST /v1/subscription/portal`, with the sandbox's price ids and the checkout's address in `.env.prod`. Tried against the deployed server: GB answered $7.00 + $1.40 VAT and the US $7.00 with no tax, once the prices' tax setting was changed from automatic, which had included VAT in GB's price, to exclusive. A revoked key got `license_revoked` from the portal. A real portal session needs a real sandbox purchase, which waits for the checkout page in step 9. |
| 7 | License server | Promo codes: their tables, the tool's commands, redeeming, and moving a subscription's billing date through Paddle |
| 8 | License server | The license email through Mailgun, and the tool's resend command. You add the `licenses@tjdraper.com` forwarder in Namecheap. |
| 9 | Website | The checkout and after-paying pages, against the sandbox |
| 10 | Website | The product page with Paddle's price preview, the terms, the refund policy, the privacy section, and links between them, all unlisted, the narrowed `/.well-known` rule in Traefik, and the Apple Pay file |
| You | Paddle | The live account's verification and domain approval |
| 11 | License server and website | Switching to live: the product, prices, webhook destination, default payment link, and settings, then one real purchase, refunded |

## Sources

- [Paddle: Domain review](https://www.paddle.com/help/start/account-verification/what-is-domain-verification)
- [Paddle: Setup checklist](https://developer.paddle.com/build/onboarding/set-up-checklist)
- [Paddle: Go-live checklist](https://developer.paddle.com/build/onboarding/go-live-checklist)
- [Paddle: Default payment link](https://developer.paddle.com/build/transactions/default-payment-link/)
- [Paddle: Sandbox](https://developer.paddle.com/build/tools/sandbox)
- [Paddle: Apple Pay](https://developer.paddle.com/concepts/payment-methods/apple-pay/)
- [Paddle: Webhooks](https://developer.paddle.com/webhooks/overview)
- [Paddle: subscription.created](https://developer.paddle.com/webhooks/subscriptions/subscription-created/)
- [Paddle: Signature verification](https://developer.paddle.com/webhooks/signature-verification)
- [Paddle: Respond to webhooks](https://developer.paddle.com/webhooks/respond-to-webhooks)
- [Paddle: Provision access with webhooks](https://developer.paddle.com/build/subscriptions/provision-access-webhooks)
- [Paddle: Custom data](https://developer.paddle.com/build/transactions/custom-data)
- [Paddle: adjustment.updated](https://developer.paddle.com/webhooks/adjustments/adjustment-updated)
- [Paddle: Create a customer portal session](https://developer.paddle.com/api-reference/customer-portals/create-customer-portal-session/)
- [Paddle: Paddle.PricePreview()](https://developer.paddle.com/paddle-js/methods/paddle-pricepreview/)
- [Paddle: Refund policy](https://www.paddle.com/legal/refund-policy)
