import { config } from './config.js';

document.documentElement.classList.add('js');

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const TONES = ['pink', 'lime', 'blue', 'orange', 'yellow'];

/** Create an element. Text always goes through textContent, never innerHTML. */
function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

/* ---------- Safety helpers for values that come from config ---------- */

/** Returns a normalised https URL on an allowed checkout host, or null. */
function safeCheckoutUrl(raw) {
  if (typeof raw !== 'string' || !raw.trim()) return null;
  try {
    const url = new URL(raw.trim());
    if (url.protocol !== 'https:' || url.username || url.password) return null;
    const host = url.hostname.toLowerCase();
    const allowed = (config.allowedCheckoutHosts || []).some(
      (h) => host === h || host.endsWith('.' + h),
    );
    return allowed ? url.href : null;
  } catch {
    return null;
  }
}

/** Only local image files under assets/ may be used as card art. */
function safeImagePath(raw) {
  return typeof raw === 'string' && /^assets\/[\w\-./]+\.(webp|avif|png|jpe?g|svg)$/i.test(raw) && !raw.includes('..')
    ? raw
    : null;
}

/* ---------- Checkout, price, contents, FAQ, footer ---------- */

function setupStore() {
  const checkout = safeCheckoutUrl(config.checkoutUrl);
  if (config.checkoutUrl && !checkout) {
    console.warn('Unsober: checkoutUrl was ignored. It must be https and on a host listed in allowedCheckoutHosts.');
  }

  for (const link of $$('[data-checkout]')) {
    if (checkout) {
      link.href = checkout;
      link.rel = 'noopener';
    } else if (link.hasAttribute('data-main')) {
      link.textContent = 'Coming soon';
      link.classList.add('is-disabled');
      link.setAttribute('aria-disabled', 'true');
      link.removeAttribute('href');
    }
  }

  const price = typeof config.price === 'string' ? config.price.trim() : '';
  $('#price').textContent = price;
  for (const slot of $$('[data-price]')) slot.textContent = price ? `· ${price}` : '';

  const contents = $('#contents');
  (config.contents || []).forEach((item, i) => {
    const li = el('li', '', item);
    li.dataset.tone = TONES[i % TONES.length];
    contents.append(li);
  });

  const faq = $('#faqList');
  for (const { q, a } of config.faq || []) {
    const details = el('details');
    details.append(el('summary', '', q), el('p', '', a));
    faq.append(details);
  }

  $('#year').textContent = String(new Date().getFullYear());

  const contact = $('#contact');
  if (/^[^\s@<>"']+@[^\s@<>"']+\.[a-z]{2,}$/i.test(config.contactEmail || '')) {
    contact.href = `mailto:${config.contactEmail}`;
    contact.hidden = false;
  }
}

/* ---------- The deck ---------- */

function buildWordmark(className) {
  const mark = el('span', `wordmark ${className}`, 'Unsober');
  mark.dataset.text = 'Unsober';
  return mark;
}

function fillBack(node) {
  const image = safeImagePath(config.cardBackImage);
  if (image) {
    const img = el('img');
    img.src = image;
    img.alt = '';
    node.append(img);
  } else {
    node.append(buildWordmark('wordmark-card'));
  }
  return node;
}

function buildFront(card) {
  const front = el('div', 'face front');
  const image = safeImagePath(card.image);
  if (image) {
    const img = el('img');
    img.src = image;
    img.alt = card.text || '';
    front.append(img);
  } else {
    front.append(
      el('span', 'front-type', card.type),
      el('p', 'front-text', card.text),
      el('span', 'front-mark', 'Unsober'),
    );
  }
  return front;
}

function shuffle(list) {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

function setupDeck() {
  const world = $('#world');
  const pile = $('#pile');
  const hint = $('#hint');
  const live = $('#live');
  const cards = (config.cards || []).filter((c) => c && (c.text || c.image));
  if (!cards.length) return;

  const LAYERS = 9;
  for (let i = 0; i < LAYERS; i++) {
    const layer = el('div', i === LAYERS - 1 ? 'layer layer-top' : 'layer');
    layer.style.setProperty('--i', String(i));
    if (i === LAYERS - 1) fillBack(layer);
    pile.append(layer);
  }

  let queue = [];
  let current = null;
  let lastCard = null;

  function nextCard() {
    if (!queue.length) {
      queue = shuffle(cards);
      // Avoid showing the same card twice in a row across a reshuffle.
      if (queue.length > 1 && queue[0] === lastCard) queue.push(queue.shift());
    }
    lastCard = queue.shift();
    return lastCard;
  }

  function draw() {
    if (current) {
      const old = current;
      old.classList.add('gone');
      setTimeout(() => old.remove(), 900);
    }

    const data = nextCard();
    const card = el('div', 'card drawn');
    card.dataset.tone = TONES.includes(data.tone) ? data.tone : 'pink';
    card.append(fillBack(el('div', 'face back')), buildFront(data));
    card.addEventListener('click', draw);
    world.append(card);

    // Force a style pass so the card animates from the pile to your hand.
    void card.offsetWidth;
    card.classList.add('shown');
    current = card;

    pile.classList.remove('bump');
    void pile.offsetWidth;
    pile.classList.add('bump');

    hint.textContent = 'Tap for another';
    live.textContent = data.type ? `${data.type}. ${data.text}` : data.text;
  }

  // Stop mouse/touch presses from focusing the deck, which can make the page jump.
  pile.addEventListener('pointerdown', (event) => event.preventDefault());
  pile.addEventListener('click', draw);
  pile.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      draw();
    }
  });
}

/* ---------- Motion: one animation loop for the deck tilt and the box ---------- */

function setupMotion() {
  const stage = $('#stage');
  const world = $('#world');
  const scene = $('#boxScene');
  const box = $('#box');

  const visible = new Map([[stage, false], [scene, false]]);
  const tilt = { x: 0, y: 0, targetX: 0, targetY: 0 };
  const spin = { x: -10, y: -32, velocity: 0, dragging: false, lastX: 0, lastY: 0 };
  const AUTO_SPIN = 0.18;
  let running = false;
  let lastTime = 0;

  function frame(time) {
    const dt = Math.min((time - lastTime) / 16.67, 3) || 1;
    lastTime = time;

    if (visible.get(stage)) {
      const drift = reducedMotion.matches ? 0 : Math.sin(time / 1600) * 1.6;
      tilt.x += (tilt.targetX - tilt.x) * 0.08 * dt;
      tilt.y += (tilt.targetY + drift - tilt.y) * 0.08 * dt;
      world.style.setProperty('--rx', `${tilt.x.toFixed(2)}deg`);
      world.style.setProperty('--ry', `${tilt.y.toFixed(2)}deg`);
    }

    if (visible.get(scene)) {
      if (!spin.dragging) {
        const rest = reducedMotion.matches ? 0 : AUTO_SPIN;
        spin.velocity += (rest - spin.velocity) * 0.04 * dt;
        spin.y += spin.velocity * dt;
        spin.x += (-10 - spin.x) * 0.05 * dt;
      }
      box.style.setProperty('--bx', `${spin.x.toFixed(2)}deg`);
      box.style.setProperty('--by', `${spin.y.toFixed(2)}deg`);
    }

    if (visible.get(stage) || visible.get(scene)) {
      requestAnimationFrame(frame);
    } else {
      running = false;
    }
  }

  function start() {
    if (running) return;
    running = true;
    lastTime = performance.now();
    requestAnimationFrame(frame);
  }

  new IntersectionObserver((entries) => {
    for (const entry of entries) visible.set(entry.target, entry.isIntersecting);
    start();
  }).observe(stage);
  new IntersectionObserver((entries) => {
    for (const entry of entries) visible.set(entry.target, entry.isIntersecting);
    start();
  }).observe(scene);

  // Deck leans toward the pointer.
  window.addEventListener('pointermove', (event) => {
    if (event.pointerType === 'touch' || reducedMotion.matches) return;
    tilt.targetY = (event.clientX / window.innerWidth - 0.5) * 16;
    tilt.targetX = -(event.clientY / window.innerHeight - 0.5) * 10;
  }, { passive: true });

  // Drag the box to spin it. Let go and it coasts.
  scene.addEventListener('pointerdown', (event) => {
    spin.dragging = true;
    spin.lastX = event.clientX;
    spin.lastY = event.clientY;
    spin.velocity = 0;
    scene.setPointerCapture(event.pointerId);
    scene.classList.add('is-dragging');
  });
  scene.addEventListener('pointermove', (event) => {
    if (!spin.dragging) return;
    const dx = event.clientX - spin.lastX;
    const dy = event.clientY - spin.lastY;
    spin.lastX = event.clientX;
    spin.lastY = event.clientY;
    spin.y += dx * 0.6;
    spin.x = Math.max(-40, Math.min(40, spin.x - dy * 0.4));
    spin.velocity = dx * 0.6;
  });
  const release = () => {
    spin.dragging = false;
    scene.classList.remove('is-dragging');
  };
  scene.addEventListener('pointerup', release);
  scene.addEventListener('pointercancel', release);

  // Step cards tilt under the cursor.
  for (const card of $$('[data-tilt]')) {
    card.addEventListener('pointermove', (event) => {
      if (event.pointerType === 'touch' || reducedMotion.matches) return;
      const rect = card.getBoundingClientRect();
      const px = (event.clientX - rect.left) / rect.width - 0.5;
      const py = (event.clientY - rect.top) / rect.height - 0.5;
      card.classList.add('is-tilting');
      card.style.setProperty('--ty', `${(px * 14).toFixed(2)}deg`);
      card.style.setProperty('--tx', `${(-py * 14).toFixed(2)}deg`);
    });
    card.addEventListener('pointerleave', () => {
      card.classList.remove('is-tilting');
      card.style.setProperty('--tx', '0deg');
      card.style.setProperty('--ty', '0deg');
    });
  }
}

function setupReveal() {
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('in');
      observer.unobserve(entry.target);
    }
  }, { threshold: 0.15 });
  for (const node of $$('.reveal')) observer.observe(node);
}

setupStore();
setupDeck();
setupMotion();
setupReveal();
