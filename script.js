// ==========================================
// SUPABASE CONNECTION
// ==========================================

const SUPABASE_URL = 'https://pjqhkpjlluoauoegxgxo.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_FXNglIO3Q6-RaM8G1Mrm2w_kMqw6h7Q';

const supabaseClient = window.supabase.createClient(
  SUPABASE_URL,
  SUPABASE_PUBLISHABLE_KEY
);
/* ==========================================
   UI-only text (not menu content — menu content
   comes from Supabase and is already multilingual)
   ========================================== */
const uiText = {
  en: { footer1: "All prices are listed in Moroccan Dirhams (DH).", footer2: "", loading: "Loading menu…", error: "Unable to load the menu right now. Please try again shortly." },
  fr: { footer1: "Tous nos prix sont exprimés en Dirhams Marocains (DH).", footer2: "", loading: "Chargement du menu…", error: "Impossible de charger le menu pour le moment. Merci de réessayer." },
  es: { footer1: "Todos los precios están indicados en Dirhams Marroquíes (DH).", footer2: "", loading: "Cargando el menú…", error: "No se pudo cargar el menú. Inténtalo de nuevo en un momento." }
};

/* ==========================================
   MENU DATA — fetched from Supabase
   ========================================== */
let MENU_CATEGORIES = [];
let MENU_ITEMS = [];
const cartQtyMap = {}; // item id -> quantity, survives language switches and refreshes
let currentLang = 'es';
let customerChoseLang = false; // true once the visitor taps a flag button themselves

// Keep the customer's unfinished order on this device/browser.
// Only non-sensitive cart data is stored locally; no customer account data is involved.
const CART_STORAGE_KEY = 'babouche_cart_v1';
const CART_DRAFT_KEY = 'babouche_cart_draft_v1';

function persistCart(){
  try {
    const cleanCart = {};
    Object.entries(cartQtyMap).forEach(([id, qty]) => {
      const n = Math.max(0, Math.min(99, parseInt(qty || '0', 10) || 0));
      if (n) cleanCart[id] = n;
    });
    localStorage.setItem(CART_STORAGE_KEY, JSON.stringify(cleanCart));
  } catch (e) {
    console.warn('Unable to persist cart locally:', e);
  }
}

function restoreCart(){
  try {
    const saved = JSON.parse(localStorage.getItem(CART_STORAGE_KEY) || '{}');
    if (!saved || typeof saved !== 'object') return;
    Object.entries(saved).forEach(([id, qty]) => {
      const n = Math.max(0, Math.min(99, parseInt(qty || '0', 10) || 0));
      if (n) cartQtyMap[id] = n;
    });
  } catch (e) {
    console.warn('Unable to restore cart locally:', e);
  }
}

function persistCartDraft(){
  try {
    localStorage.setItem(CART_DRAFT_KEY, JSON.stringify({
      table: tableNumber ? tableNumber.value.slice(0, 40) : '',
      special: specialRequests ? specialRequests.value.slice(0, 1000) : ''
    }));
  } catch (e) {
    console.warn('Unable to persist cart draft locally:', e);
  }
}

function restoreCartDraft(){
  try {
    const saved = JSON.parse(localStorage.getItem(CART_DRAFT_KEY) || '{}');
    if (tableNumber && typeof saved.table === 'string') tableNumber.value = saved.table;
    if (specialRequests && typeof saved.special === 'string') specialRequests.value = saved.special;
  } catch (e) {
    console.warn('Unable to restore cart draft locally:', e);
  }
}

function clearPersistedCart(){
  try {
    localStorage.removeItem(CART_STORAGE_KEY);
    localStorage.removeItem(CART_DRAFT_KEY);
  } catch (e) {}
}

restoreCart();
restoreCartDraft();

async function loadMenu(){
  const menuSections = document.getElementById('menuSections');
  try {
    const [{ data: categories, error: catErr }, { data: items, error: itemErr }] = await Promise.all([
      supabaseClient.from('categories').select('*').order('sort_order', { ascending: true }),
      supabaseClient.from('menu_items').select('*').eq('available', true).order('sort_order', { ascending: true })
    ]);
    if (catErr) throw catErr;
    if (itemErr) throw itemErr;
    MENU_CATEGORIES = categories || [];
    MENU_ITEMS = items || [];

    // Remove cart entries for dishes that no longer exist or are unavailable.
    const validIds = new Set(MENU_ITEMS.map(item => String(item.id)));
    Object.keys(cartQtyMap).forEach(id => {
      if (!validIds.has(String(id))) delete cartQtyMap[id];
    });
    persistCart();
    renderMenu();
  } catch (err) {
    console.error('Menu load error:', err);
    menuSections.innerHTML = `<div class="menu-error">${(uiText[currentLang] || uiText.en).error}</div>`;
  }
}

function escapeHtml(str){
  return String(str ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function itemField(item, base){
  return item[base + '_' + currentLang] || item[base + '_en'] || '';
}
function catField(cat, base){
  return cat[base + '_' + currentLang] || cat[base + '_en'] || '';
}

function renderMenu(){
  const navScroll = document.getElementById('navScroll');
  const menuSections = document.getElementById('menuSections');

  if (!MENU_CATEGORIES.length){
    menuSections.innerHTML = `<div class="menu-error">${(uiText[currentLang] || uiText.en).error}</div>`;
    return;
  }

  navScroll.innerHTML = MENU_CATEGORIES.map(cat =>
    `<a href="#${escapeHtml(cat.slug)}" class="nav-btn">${escapeHtml(catField(cat,'name'))}</a>`
  ).join('');

  const sectionsHtml = MENU_CATEGORIES.map((cat, idx) => {
    const catItems = MENU_ITEMS.filter(it => it.category_id === cat.id);
    if (!catItems.length) return '';
    const itemsHtml = catItems.map(item => {
      const qty = cartQtyMap[item.id] || 0;
      const desc = itemField(item, 'desc');
      return `
        <div class="item" data-qty="${qty}" data-item-id="${item.id}">
          <div class="item-main">
            <div class="item-name">${escapeHtml(itemField(item,'name'))}</div>
            ${desc ? `<div class="item-desc">${escapeHtml(desc)}</div>` : ''}
          </div>
          <div class="item-price">${item.price} dh</div>
        </div>`;
    }).join('');
    return `
      <section id="${escapeHtml(cat.slug)}">
        <div class="section-title">${escapeHtml(catField(cat,'name'))}</div>
        ${itemsHtml}
      </section>
      ${idx < MENU_CATEGORIES.length - 1 ? '<hr class="rule">' : ''}`;
  }).join('');

  menuSections.innerHTML = sectionsHtml;
  updateCart();
}

function setLang(lang){
  currentLang = lang;
  document.querySelectorAll('.lang-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.lang === lang);
  });
  document.documentElement.lang = lang;
  closeModal();
  renderMenu();
  const t = uiText[lang] || uiText.en;
  const footer1El = document.getElementById('footerLine1');
  const footer2El = document.getElementById('footerLine2');
  if (footer1El) footer1El.textContent = t.footer1;
  if (footer2El) footer2El.textContent = t.footer2;
}

document.querySelectorAll('.lang-btn').forEach(btn => {
  btn.addEventListener('click', () => { customerChoseLang = true; setLang(btn.dataset.lang); });
});

/* ---- Dish photo popup ---- */
const dishModal = document.getElementById('dishModal');
const modalImg = document.getElementById('modalImg');
const modalPhoto = document.getElementById('modalPhoto');
const modalName = document.getElementById('modalName');
const modalDesc = document.getElementById('modalDesc');
const modalPrice = document.getElementById('modalPrice');
const modalQty = document.getElementById('modalQty');
const modalQtyLabel = document.getElementById('modalQtyLabel');
const qtyMinus = document.getElementById('qtyMinus');
const qtyPlus = document.getElementById('qtyPlus');
const modalAddBtn = document.getElementById('modalAddBtn');
let currentModalItemId = null;

function openModal(itemId){
  const item = MENU_ITEMS.find(it => it.id === itemId);
  if (!item) return;
  currentModalItemId = itemId;

  const desc = itemField(item, 'desc');
  modalName.textContent = itemField(item, 'name');
  modalDesc.textContent = desc;
  modalDesc.style.display = desc ? 'block' : 'none';
  modalPrice.textContent = `${item.price} dh`;
  modalQty.value = cartQtyMap[itemId] || 0;
  modalAddBtn.textContent = (cartTranslations[getCurrentLang()] || cartTranslations.en).add;

  modalPhoto.classList.remove('photo-fallback');
  if (item.image_url){
    modalImg.style.display = 'block';
    modalImg.onerror = () => {
      modalImg.style.display = 'none';
      modalPhoto.classList.add('photo-fallback');
    };
    modalImg.src = item.image_url;
  } else {
    modalImg.style.display = 'none';
    modalPhoto.classList.add('photo-fallback');
  }

  dishModal.classList.add('open');
  document.body.style.overflow = 'hidden';
}

function closeModal(){
  dishModal.classList.remove('open');
  currentModalItemId = null;
  document.body.style.overflow = '';
}

/* Event delegation: works for items rendered now or re-rendered later (language switch) */
document.getElementById('menuSections').addEventListener('click', (e) => {
  const itemEl = e.target.closest('.item[data-item-id]');
  if (itemEl) openModal(itemEl.dataset.itemId);
});

document.getElementById('modalClose').addEventListener('click', closeModal);
dishModal.addEventListener('click', (e) => {
  if (e.target === dishModal) closeModal();
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') { closeModal(); closeCart(); }
});

/* ---- Restaurant settings (WhatsApp number, header photo, socials) ---- */
let RESTAURANT_WHATSAPP = ''; // digits-only number, set from admin panel

async function loadSettings(){
  try {
    const { data, error } = await supabaseClient.from('settings').select('*');
    if (error) throw error;
    const settings = {};
    (data || []).forEach(row => { settings[row.key] = row.value; });

    // Default menu language is controlled from the admin panel (Restaurant
    // Settings -> Default Menu Language). Falls back to the 'es' set above
    // if this setting is missing, invalid, or the customer already tapped a
    // different flag button before this loaded.
    const validLangs = ['en', 'fr', 'es'];
    if (validLangs.includes(settings.default_language) && !customerChoseLang && settings.default_language !== currentLang){
      setLang(settings.default_language);
    }

    if (settings.header_image_url){
      document.documentElement.style.setProperty('--header-photo', `url('${settings.header_image_url}')`);
    }
    if (settings.whatsapp_number){
      const cleanNumber = settings.whatsapp_number.replace(/[^\d]/g, '');
      RESTAURANT_WHATSAPP = cleanNumber;
      const waBtn = document.getElementById('whatsappFloat');
      if (cleanNumber){
        waBtn.href = `https://wa.me/${cleanNumber}`;
        waBtn.classList.remove('hidden');
      }
    }
    const socialMap = {
      google_maps_url: 'socialGoogleMaps',
      instagram_url: 'socialInstagram',
      tripadvisor_url: 'socialTripadvisor'
    };
    Object.entries(socialMap).forEach(([key, id]) => {
      const el = document.getElementById(id);
      if (el && settings[key]){
        el.href = settings[key];
        el.style.display = '';
      }
    });
  } catch (err) {
    console.error('Settings load error:', err);
  }
}

/* ---- Cart & WhatsApp ordering ---- */

const cartBar = document.getElementById('cartBar');
const cartTitle = document.getElementById('cartTitle');
const cartTotal = document.getElementById('cartTotal');
const tableNumber = document.getElementById('tableNumber');
const sendOrderBtn = document.getElementById('sendOrderBtn');
const cartNote = document.getElementById('cartNote');
const cartSheetBackdrop = document.getElementById('cartSheetBackdrop');
const cartItemsList = document.getElementById('cartItemsList');
const cartSheetCount = document.getElementById('cartSheetCount');
const cartSubtitle = document.getElementById('cartSubtitle');
const cartOpenHint = document.getElementById('cartOpenHint');
const cartSubtotal = document.getElementById('cartSubtotal');
const cartGrandTotal = document.getElementById('cartGrandTotal');
const specialRequests = document.getElementById('specialRequests');

const cartTranslations = {
  en: {
    order: 'Your Order',
    review: 'Tap to review and modify',
    reviewHint: 'Review cart ›',
    item: 'item',
    items: 'items',
    tablePlaceholder: 'Table number',
    sheetTitle: 'Your Order',
    special: 'Special requests, allergies...',
    subtotal: 'Subtotal',
    total: 'Total',
    send: 'Order via WhatsApp',
    sending: 'Opening WhatsApp...',
    sentLabel: 'Sent to WhatsApp ✓',
    sentOk: '✓ Redirecting you to WhatsApp — tap send there to confirm!',
    sendError: 'Unable to open WhatsApp. Please try again.',
    noWhatsapp: 'Ordering isn\'t available right now — please contact the restaurant directly.',
    emptyCart: 'Your order is empty.',
    remove: 'Remove',
    add: 'Add',
    note: 'Review your items, then send your order on WhatsApp.',
    missingTable: 'Please enter your table number.',
    table: 'Table'
  },
  fr: {
    order: 'Votre commande',
    review: 'Touchez pour vérifier et modifier',
    reviewHint: 'Voir le panier ›',
    item: 'article',
    items: 'articles',
    tablePlaceholder: 'Numéro de table',
    sheetTitle: 'Votre commande',
    special: 'Demandes spéciales, allergies...',
    subtotal: 'Sous-total',
    total: 'Total',
    send: 'Commander via WhatsApp',
    sending: 'Ouverture de WhatsApp...',
    sentLabel: 'Envoyé sur WhatsApp ✓',
    sentOk: '✓ Redirection vers WhatsApp — appuyez sur envoyer pour confirmer !',
    sendError: 'Impossible d\'ouvrir WhatsApp. Veuillez réessayer.',
    noWhatsapp: 'La commande n\'est pas disponible pour le moment — merci de contacter le restaurant directement.',
    emptyCart: 'Votre commande est vide.',
    remove: 'Supprimer',
    add: 'Ajouter',
    note: 'Vérifiez votre commande puis envoyez-la sur WhatsApp.',
    missingTable: 'Veuillez entrer votre numéro de table.',
    table: 'Table'
  },
  es: {
    order: 'Su pedido',
    review: 'Toque para revisar y modificar',
    reviewHint: 'Ver carrito ›',
    item: 'producto',
    items: 'productos',
    tablePlaceholder: 'Número de mesa',
    sheetTitle: 'Su pedido',
    special: 'Peticiones especiales, alergias...',
    subtotal: 'Subtotal',
    total: 'Total',
    send: 'Pedir por WhatsApp',
    sending: 'Abriendo WhatsApp...',
    sentLabel: 'Enviado a WhatsApp ✓',
    sentOk: '✓ Te estamos redirigiendo a WhatsApp — pulsa enviar para confirmar.',
    sendError: 'No se pudo abrir WhatsApp. Inténtalo de nuevo.',
    noWhatsapp: 'Los pedidos no están disponibles por ahora — por favor contacta directamente con el restaurante.',
    emptyCart: 'Su pedido está vacío.',
    remove: 'Eliminar',
    add: 'Añadir',
    note: 'Revisa tu pedido y envíalo por WhatsApp.',
    missingTable: 'Introduce el número de mesa.',
    table: 'Mesa'
  }
};

function getCurrentLang(){
  return document.documentElement.lang || 'en';
}

function getCartItems(){
  const items = [];
  Object.entries(cartQtyMap).forEach(([itemId, qty]) => {
    qty = Math.max(0, parseInt(qty || '0', 10) || 0);
    if (!qty) return;
    const item = MENU_ITEMS.find(it => it.id === itemId);
    if (!item) return;
    const price = Number(item.price) || 0;
    items.push({
      id: item.id,
      name: itemField(item, 'name'),
      qty,
      price,
      image_url: item.image_url || '',
      subtotal: qty * price
    });
  });
  return items;
}

// Order recap sent to the restaurant over WhatsApp always uses English dish
// names, no matter which menu language the customer was browsing in.
function getCartItemsForWhatsApp(){
  const items = [];
  Object.entries(cartQtyMap).forEach(([itemId, qty]) => {
    qty = Math.max(0, parseInt(qty || '0', 10) || 0);
    if (!qty) return;
    const item = MENU_ITEMS.find(it => it.id === itemId);
    if (!item) return;
    const price = Number(item.price) || 0;
    items.push({
      id: item.id,
      name: item.name_en || itemField(item, 'name'),
      qty,
      price,
      image_url: item.image_url || '',
      subtotal: qty * price
    });
  });
  return items;
}

function money(value){
  return `${Number(value || 0).toFixed(2).replace(/\.00$/, '')} dh`;
}

function cartTotals(){
  const items = getCartItems();
  const subtotal = items.reduce((sum, item) => sum + item.subtotal, 0);
  return { items, subtotal, total: subtotal };
}

function renderCartSheet(){
  const { items, subtotal, total } = cartTotals();
  const t = cartTranslations[getCurrentLang()] || cartTranslations.en;
  const totalQty = items.reduce((sum, item) => sum + item.qty, 0);

  cartSheetCount.textContent = `${totalQty} ${totalQty === 1 ? t.item : t.items}`;
  cartSubtotal.textContent = money(subtotal);
  cartGrandTotal.textContent = money(total);
  document.getElementById('cartSheetTitle').textContent = t.sheetTitle;
  document.getElementById('specialRequestsLabel').textContent = t.special;
  specialRequests.placeholder = t.special;
  document.getElementById('subtotalLabel').textContent = t.subtotal;
  document.getElementById('totalLabel').textContent = t.total;
  tableNumber.placeholder = t.tablePlaceholder;
  sendOrderBtn.textContent = t.send;
  cartNote.textContent = t.note;

  if (!items.length){
    cartItemsList.innerHTML = `<div class="cart-empty"><div class="cart-empty-icon">✦</div>${escapeHtml(t.emptyCart)}</div>`;
    sendOrderBtn.disabled = true;
    return;
  }

  sendOrderBtn.disabled = false;
  cartItemsList.innerHTML = items.map(item => `
    <div class="cart-item-row" data-cart-id="${escapeHtml(item.id)}">
      ${item.image_url ? `<img class="cart-item-thumb" src="${escapeHtml(item.image_url)}" alt="" onerror="this.style.visibility='hidden'">` : `<div class="cart-item-thumb"></div>`}
      <div>
        <div class="cart-item-name">${escapeHtml(item.name)}</div>
        <div class="cart-item-price">${money(item.price)} · ${money(item.subtotal)}</div>
        <button class="cart-remove" type="button" data-cart-action="remove" data-item-id="${escapeHtml(item.id)}">${t.remove}</button>
      </div>
      <div class="cart-item-controls">
        <button class="cart-step" type="button" data-cart-action="minus" data-item-id="${escapeHtml(item.id)}" aria-label="Decrease">−</button>
        <span class="cart-item-qty">${item.qty}</span>
        <button class="cart-step" type="button" data-cart-action="plus" data-item-id="${escapeHtml(item.id)}" aria-label="Increase">+</button>
      </div>
    </div>`).join('');
}

function updateCart(){
  const { items } = cartTotals();
  const totalQty = items.reduce((sum, item) => sum + item.qty, 0);
  const total = items.reduce((sum, item) => sum + item.subtotal, 0);
  const t = cartTranslations[getCurrentLang()] || cartTranslations.en;

  cartBar.classList.toggle('open', totalQty > 0);
  cartTitle.textContent = `${t.order}`;
  cartSubtitle.textContent = t.review;
  cartOpenHint.textContent = t.reviewHint;
  cartTotal.textContent = money(total);
  renderCartSheet();
}

function openCart(){
  if (!getCartItems().length) return;
  renderCartSheet();
  cartSheetBackdrop.classList.add('open');
  cartSheetBackdrop.setAttribute('aria-hidden','false');
  document.body.style.overflow = 'hidden';
}
function closeCart(){
  cartSheetBackdrop.classList.remove('open');
  cartSheetBackdrop.setAttribute('aria-hidden','true');
  document.body.style.overflow = '';
}

cartBar.addEventListener('click', openCart);
cartBar.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openCart(); } });
document.getElementById('cartClose').addEventListener('click', closeCart);
cartSheetBackdrop.addEventListener('click', e => { if (e.target === cartSheetBackdrop) closeCart(); });

// Remember unfinished checkout details across refreshes.
tableNumber.addEventListener('input', persistCartDraft);
specialRequests.addEventListener('input', persistCartDraft);

cartItemsList.addEventListener('click', e => {
  const btn = e.target.closest('[data-cart-action]');
  if (!btn) return;
  const id = btn.dataset.itemId;
  const action = btn.dataset.cartAction;
  const current = cartQtyMap[id] || 0;
  if (action === 'plus') cartQtyMap[id] = Math.min(99, current + 1);
  if (action === 'minus') {
    if (current <= 1) delete cartQtyMap[id];
    else cartQtyMap[id] = current - 1;
  }
  if (action === 'remove') delete cartQtyMap[id];
  persistCart();
  renderMenu();
  if (!getCartItems().length) closeCart();
});

/* ---- Order submission: handed off to WhatsApp only; no order database is used ---- */
// Strips characters a customer could use to spoof the order message's
// structure (fake newlines pretending to be a new line item, WhatsApp
// markdown like *bold* used to imitate "Total:", etc). Applied to the
// free-text fields right before they go into the WhatsApp message.
function sanitizeForWhatsApp(text){
  return String(text || '')
    .replace(/[\r\n]+/g, ' ')
    .replace(/[*_~`]/g, '')
    .trim()
    .slice(0, 500);
}

function buildWhatsAppMessage(table, items, subtotal, total, special){
  const lines = [`🍽️ *New order — BABOUCHE*`, `Table: ${sanitizeForWhatsApp(table)}`, ''];
  items.forEach(item => {
    lines.push(`${item.qty}x ${item.name} — ${money(item.subtotal)}`);
  });
  lines.push('');
  lines.push(`Subtotal: ${money(subtotal)}`);
  lines.push(`*Total: ${money(total)}*`);
  if (special) {
    lines.push('');
    lines.push(`Special requests: ${sanitizeForWhatsApp(special)}`);
  }
  return lines.join('\n');
}

async function sendOrder() {
  const table = tableNumber.value.trim();
  const t = cartTranslations[getCurrentLang()] || cartTranslations.en;
  const { items, subtotal, total } = cartTotals();
  const special = specialRequests.value.trim();

  if (!table) {
    cartNote.textContent = t.missingTable;
    tableNumber.focus();
    return;
  }
  if (!items.length) {
    cartNote.textContent = t.emptyCart;
    return;
  }
  if (!RESTAURANT_WHATSAPP) {
    cartNote.textContent = t.noWhatsapp;
    return;
  }

  sendOrderBtn.disabled = true;
  sendOrderBtn.textContent = t.sending;

  try {
    const englishItems = getCartItemsForWhatsApp();
    const message = buildWhatsAppMessage(table, englishItems, subtotal, total, special);
    const waUrl = `https://wa.me/${RESTAURANT_WHATSAPP}?text=${encodeURIComponent(message)}`;
    window.open(waUrl, '_blank');
    cartNote.textContent = t.sentOk;
    sendOrderBtn.textContent = t.sentLabel;

    setTimeout(() => {
      Object.keys(cartQtyMap).forEach(id => delete cartQtyMap[id]);
      specialRequests.value = '';
      tableNumber.value = '';
      clearPersistedCart();
      closeCart();
      renderMenu();
      sendOrderBtn.disabled = false;
      sendOrderBtn.textContent = t.send;
    }, 1800);
  } catch (error) {
    console.error(error);
    cartNote.textContent = t.sendError;
    sendOrderBtn.disabled = false;
    sendOrderBtn.textContent = t.send;
  }
}

function setModalQty(value){
  if (!currentModalItemId) return;
  value = Math.max(0, Math.min(99, parseInt(value, 10) || 0));
  modalQty.value = value;
  if (value > 0){
    cartQtyMap[currentModalItemId] = value;
  } else {
    delete cartQtyMap[currentModalItemId];
  }
  persistCart();
  const rowEl = document.querySelector(`.item[data-item-id="${currentModalItemId}"]`);
  if (rowEl) rowEl.dataset.qty = String(value);
  updateCart();
}

qtyMinus.addEventListener('click', e => {
  e.stopPropagation();
  setModalQty((parseInt(modalQty.value, 10) || 0) - 1);
});

qtyPlus.addEventListener('click', e => {
  e.stopPropagation();
  setModalQty((parseInt(modalQty.value, 10) || 0) + 1);
});

modalAddBtn.addEventListener('click', e => {
  e.stopPropagation();
  if (!currentModalItemId) return;
  setModalQty(modalQty.value);
  closeModal();
});

modalQty.addEventListener('click', e => e.stopPropagation());
modalQty.addEventListener('keydown', e => e.stopPropagation());
modalQty.addEventListener('input', () => {
  if (!currentModalItemId) return;
  let value = parseInt(modalQty.value, 10);
  if (Number.isNaN(value) || value < 0) value = 0;
  if (value > 99) value = 99;
  setModalQty(value);
});
modalQty.addEventListener('change', () => {
  if (!currentModalItemId) return;
  let value = parseInt(modalQty.value, 10);
  if (Number.isNaN(value) || value < 0) value = 0;
  if (value > 99) value = 99;
  setModalQty(value);
});

tableNumber.addEventListener('input', () => {
  cartNote.style.color = 'var(--muted)';
  cartNote.textContent = (cartTranslations[getCurrentLang()] || cartTranslations.en).note;
});

document.getElementById('sendOrderBtn')
  .addEventListener('click', sendOrder);

/* ---- Initialize page: pull menu + settings from Supabase ---- */
setLang(currentLang); // Spanish by default — also syncs footer text, html lang and the active flag button
loadMenu();
loadSettings();
updateCart();
