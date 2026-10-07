# License server and Paddle

Slice 16 of the high-level plan. Paddle takes payment and is the seller, but Paddle Billing doesn't make license keys, and the app can't hold Paddle's secret API key or sign its own licenses. A small license server does both. The pages people see while buying live on the Locus website. The app's side of buying, keys, and codes is slice 17.

Decided on 2026-10-03, after checking Paddle's documentation (sources at the end).

## Where each part lives

- **locus.tjdraper.com**, the existing Next.js site in the `tjdraper.com-v8` repository, holds every page a buyer sees: the product page at `/git-gui` with its pricing, the checkout, the page after paying, the terms, the refund policy, and the privacy policy. It's the only domain submitted to Paddle for approval.
- **licenses.tjdraper.com** is a PHP service in its own repository, bootstrapped with `rxante/php-app-bootstrap`, in a Docker container on the same host as the tjdraper.com sites, behind the same Traefik. It holds the API the app calls, Paddle's webhooks, the license signing key, the database, the license email, and a command-line tool for running it. It serves no pages.

### Why this split

- Paddle approves each domain a checkout opens on, and approves subdomains separately. Every page Paddle's review looks for is already going on locus.tjdraper.com, so the checkout goes there too. The license server only talks to Paddle server to server (webhooks, API calls, customer portal sessions), which needs no approval.
- The license server's address is built into every copy of the app, so it gets a subdomain only it uses (see the high-level plan's Decisions). On a path of locus.tjdraper.com, wherever the website runs would have to keep forwarding that path to the license server forever, including a move to another host or stack. With Traefik, a subdomain is no more work than a path.
- PHP for the server, since it holds the signing key. Anyone with that key can make licenses for every copy of the app, so the code around it should be small, plain, and slow to change. Next.js stays on the website, where React earns its place.

## Paddle setup

- Build everything against Paddle's sandbox first. It needs no domain approval and accepts `localhost` as the checkout's address, so slices 16 and 17 can be finished before any page is public.
- One product with a monthly price of $7 and a yearly price of $59 (see the high-level plan's Decisions). The prices live in Paddle, so changing one needs no app release.
- The default payment link, which Paddle uses for payment links and in its emails about updating a card, is the checkout page. It has to be on an approved domain in the live account.
- Paddle's own discount codes stay switched on at checkout, for discounts on paid plans such as a launch sale.
- The live account needs account verification (domain, business, and identity), which can take a few days. Paddle approves most domains automatically, and a manual review takes about 5–7 business days. Submit locus.tjdraper.com well before launch.

### The one risk in domain approval

Paddle's domain review says: "If the domain includes unrelated products not sold through Paddle, it may lead to buyer confusion and a higher risk of chargebacks, which can impact approval." locus.tjdraper.com also has Launcher, ToDo (sold through the App Store), and Sound Control. They're one family under one name, so it should pass. If Paddle objects, the checkout moves to a subdomain of its own. The app gets the checkout's address from the license server, so that move needs no app release.

## Website pages

Built in the `tjdraper.com-v8` repository. Paddle's review needs these live before the live account can take payments:

- **Product page** (`/git-gui`): what the app is, its main features, and its prices. Prices come from `Paddle.PricePreview()` in Paddle.js, which finds the visitor's location itself and shows their currency and tax, with no call to the license server.
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

### Licenses

- Every purchase and every redeemed promo code makes a license: a key a person can read and type, and a record of what it covers and until when.
- Each license records which product it's for and how it was granted (Paddle, a promo code, by hand, or another seller), so the server can license other products later, sold through Paddle or not.
  - Each product gets its own signing key, so a leaked key unlocks only that product.
  - Signed licenses are for software running on someone else's machine, such as a Mac app, a command-line tool, or a plugin. A hosted web app asks the license server directly instead.
- The server signs each license with an Ed25519 key, and the app checks it offline against the public key it carries (see the high-level plan's Decisions). The signing key exists only on the server, and never in either repository.
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

The signing key, Paddle's API key, the webhook secret, Mailgun's API key, and the database password live only on the server, as Docker secrets. None goes in any repository. The license public key is built into the app and is safe to publish. Paddle's client-side token for Paddle.js is public by design.

- Settings that aren't secret, such as the Paddle environment, price ids, and the checkout's address, live in `.env` files loaded into the container's environment.
- The app is bootstrapped with `rxante/php-app-bootstrap`, whose `RuntimeConfig` reads a setting from the environment when it's there and from Docker secrets otherwise. The environment wins, so in production a secret must never also be set in a `.env` file or the environment, where it would quietly replace the Docker secret.

## Build order

Each numbered step is one Claude session in one repository, and ends with its tests passing or its result checked. Steps marked "You" are dashboard and DNS work done by hand. Slice 17 can start once step 4 is deployed, building against the license format and API this plan records by then, and takes up purchasing, codes, and the portal as steps 5–7 add their endpoints.

| | Where | Work |
|---|---|---|
| You | Paddle | The sandbox account, the product and its two prices, an API key, and a client-side token |
| 1 | License server | The repository, bootstrapped with `rxante/php-app-bootstrap`; Docker for development with MariaDB; migrations; settings through `RuntimeConfig`; tests running |
| 2 | License server | Licenses: their tables, key generation and loose key input, Ed25519 signing, and the command-line tool's commands to make, find, and revoke a license. The signed license's fields and encoding go into this plan's Licenses section. |
| 3 | License server | The app's API: refreshing and entering a key, tracking Macs and API versions, and the tool's reports on both. Each `/v1` request, response, and error goes into this plan's API section, and later steps add theirs. |
| 4 | License server and host | Deploying to `licenses.tjdraper.com` against the sandbox: Traefik, Docker secrets, MariaDB, and scheduled backups. You add the DNS record. |
| 5 | License server | Webhooks: signature checks, the IP allowlist, repeated and out-of-order events, licenses made and changed, and the purchase's license endpoint. Tried with Paddle's webhook simulator against the deployed server, so no tunnel to a laptop is needed. |
| 6 | License server | Prices and the checkout's address, and customer portal links |
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
- [Paddle: Create a customer portal session](https://developer.paddle.com/api-reference/customer-portals/create-customer-portal-session/)
- [Paddle: Paddle.PricePreview()](https://developer.paddle.com/paddle-js/methods/paddle-pricepreview/)
- [Paddle: Refund policy](https://www.paddle.com/legal/refund-policy)
