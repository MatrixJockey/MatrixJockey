# Unsober — storefront

A single-page, 3D, interactive sales site for the Unsober card game.
Plain HTML, CSS and JavaScript: no framework, no build step, no third-party scripts.

## Preview locally

```sh
cd unsober
python3 -m http.server 8000   # then open http://localhost:8000
```

(It must be served over http; opening `index.html` straight from disk will not load the scripts.)

## What to edit

Everything lives in [`js/config.js`](js/config.js):

| Setting | What it does |
| --- | --- |
| `checkoutUrl` | Your hosted checkout link. Empty = the buy button reads "Coming soon". |
| `allowedCheckoutHosts` | The only hosts the buy buttons may point at. |
| `price`, `contents`, `faq` | Shop copy. **The current values are placeholders.** |
| `cards` | The sample cards in the interactive deck. **Placeholders** — replace with real cards. |
| `cardBackImage`, `cards[].image` | Real card art. Drop files in `assets/cards/` and reference them here. |
| `contactEmail` | Adds a Contact link to the footer. |

## Security

- Strict Content-Security-Policy (`default-src 'none'`, scripts/styles/fonts/images from this site only), set both in `index.html` and in `_headers`.
- `_headers` also sets HSTS, `X-Frame-Options: DENY`, `nosniff`, a referrer policy and a permissions policy. Cloudflare Pages and Netlify read this file as-is.
- No inline scripts or styles, no cookies, no trackers, no forms, no network requests after load.
- The site never handles payment data. Buyers are sent to the payment provider's hosted checkout, and the link is validated (https + host allow-list) before it is used.
- All text from `config.js` is written with `textContent`; image paths are restricted to `assets/`.

## Deploying

Any static host works. Cloudflare Pages or Netlify are recommended because they apply `_headers` automatically: point the project at this repository and set the publish directory to `unsober`.
GitHub Pages also works, but it cannot send custom headers, so only the in-page CSP applies there.

## Checkout

Paste the hosted checkout URL into `checkoutUrl`. If you later want an in-page checkout overlay, the CSP in `index.html` and `_headers` must be widened to allow that provider's script and frame hosts.

Note: Lemon Squeezy's published rules list "physical goods of any kind" as prohibited, so confirm with them before building on it for a printed deck (see the links below).

- https://docs.lemonsqueezy.com/help/getting-started/prohibited-products
- https://docs.lemonsqueezy.com/help/getting-started/activate-your-store

## Font

Bricolage Grotesque, self-hosted under the SIL Open Font License (`assets/fonts/LICENSE.txt`).
