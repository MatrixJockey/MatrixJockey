// Everything you are likely to edit lives in this file.

export const config = {
  // Hosted checkout link (Lemon Squeezy, Stripe Payment Link, Shopify, ...).
  // Leave empty to show "Coming soon" on the buy button.
  checkoutUrl: '',

  // The buy buttons only ever send people to these hosts (or their subdomains).
  // A typo or a tampered link fails closed instead of sending buyers elsewhere.
  allowedCheckoutHosts: [
    'lemonsqueezy.com',
    'buy.stripe.com',
    'myshopify.com',
    'thegamecrafter.com',
  ],

  // Price is not set yet. Leave '' to hide it everywhere, or e.g. '$24.99'.
  price: '',

  // Shown as a "Contact" link in the footer when set.
  contactEmail: '',

  // PLACEHOLDER - what is in the box.
  contents: [
    '100+ cards',
    '3 to 10 players',
    'Learn it in 30 seconds',
    'Fits in a jacket pocket',
  ],

  // PLACEHOLDER sample cards for the interactive deck.
  // To use real card art instead, drop the files in assets/cards/ and add
  //   image: 'assets/cards/your-file.webp'
  // to a card. `text` is then used as the description for screen readers.
  // tone: 'pink' | 'lime' | 'blue' | 'orange' | 'yellow'
  cards: [
    { type: 'Dare', tone: 'pink', text: 'Do your best impression of the player on your left. They score it. Under a 7? Sip.' },
    { type: 'Truth', tone: 'blue', text: 'What is the last thing you searched for that you would rather not explain?' },
    { type: 'Rule', tone: 'lime', text: 'Nobody says the word "drink". Whoever slips, sips. Lasts until the next Rule card.' },
    { type: 'Vote', tone: 'orange', text: 'On three, point at whoever would last longest in a zombie apocalypse. Winner hands out 3 sips.' },
    { type: 'Dare', tone: 'pink', text: 'Speak only in questions until your next turn. Every slip is a sip.' },
    { type: 'Wild', tone: 'yellow', text: 'Swap seats with anyone. Their drink stays. Yours too.' },
    { type: 'Truth', tone: 'blue', text: 'Which player here would you trust with your unlocked phone? Everyone else sips.' },
    { type: 'Rule', tone: 'lime', text: 'You are the Thumb Master. Put your thumb on the table any time. Last to copy you sips.' },
  ],

  // Optional image for the back of every card, e.g. 'assets/cards/back.webp'.
  cardBackImage: '',

  // PLACEHOLDER answers - check them against your printer and policies.
  faq: [
    { q: 'How does shipping work?', a: 'Every deck is printed and mailed straight to you. You get a tracking link by email as soon as it ships.' },
    { q: 'Who is it for?', a: 'Adults 21 and over. Three to ten players works best, and nobody has to drink alcohol to play. Water, soda, or a silly forfeit all work.' },
    { q: 'Is checkout safe?', a: 'Yes. Payment happens on our checkout partner\'s secure page. This site never sees or stores your card details.' },
    { q: 'What if my deck arrives damaged?', a: 'Send us a photo and we will replace it.' },
  ],
};
