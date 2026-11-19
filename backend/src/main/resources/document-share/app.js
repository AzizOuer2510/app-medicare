(() => {
  'use strict';
  // Keep credentials in memory only. They never enter logs, query strings or browser storage.
  const token = window.location.hash.slice(1);
  history.replaceState(null, '', window.location.pathname);
  const form = document.querySelector('#unlock-form');
  const pin = document.querySelector('#pin');
  const button = document.querySelector('#unlock');
  const feedback = document.querySelector('#feedback');
  const panel = document.querySelector('#unlock-panel');
  const viewer = document.querySelector('#viewer');
  const preview = document.querySelector('#preview');
  const intro = document.querySelector('.intro');
  const download = document.querySelector('#download');
  let objectUrl;
  let expiryTimer;
  let pending = false;
  function clearPreview() {
    clearTimeout(expiryTimer);
    preview.replaceChildren();
    download.removeAttribute('href');
    if (objectUrl) URL.revokeObjectURL(objectUrl);
    objectUrl = null;
    viewer.hidden = true;
    panel.hidden = intro.hidden = false;
  }
  if (!/^[A-Za-z0-9_-]{43}$/.test(token)) {
    button.disabled = pin.disabled = true;
    feedback.textContent = 'Lien incomplet. Ouvrez le lien transmis par le patient ou scannez à nouveau son QR code.';
  }
  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (pending || !form.reportValidity()) return;
    pending = true;
    button.disabled = true;
    button.textContent = 'Vérification en cours…';
    feedback.textContent = '';
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 20000);
    try {
      const response = await fetch('/api/document-shares/access', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, pin: pin.value }),
        cache: 'no-store', credentials: 'omit', referrerPolicy: 'no-referrer', signal: controller.signal
      });
      if (!response.ok) {
        const error = await response.json().catch(() => ({}));
        if ([404, 410, 429].includes(response.status)) pin.disabled = true;
        throw new Error(error.message || 'Impossible d’ouvrir le document. Réessayez.');
      }
      const expires = new Date(response.headers.get('X-Share-Expires-At'));
      const remaining = expires.getTime() - Date.now();
      const blob = await response.blob();
      if (remaining <= 0) throw new Error('Ce partage a expiré. Demandez un nouveau lien au patient.');
      clearPreview();
      objectUrl = URL.createObjectURL(blob);
      const filename = decodeURIComponent((response.headers.get('X-Document-Filename') || 'document').replace(/\+/g, ' '));
      document.querySelector('#document-name').textContent = filename;
      document.querySelector('#expiration').textContent = `Accès autorisé jusqu’au ${expires.toLocaleString('fr-FR')}. Le patient a été informé de cette consultation.`;
      const element = document.createElement(blob.type === 'application/pdf' ? 'iframe' : 'img');
      element.src = objectUrl;
      if (element.tagName === 'IFRAME') element.title = 'Aperçu du document médical';
      else element.alt = 'Document médical partagé';
      preview.append(element);
      download.href = objectUrl;
      download.download = filename;
      pin.value = '';
      panel.hidden = intro.hidden = true;
      viewer.hidden = false;
      expiryTimer = setTimeout(() => {
        clearPreview();
        button.disabled = pin.disabled = true;
        feedback.textContent = 'Ce partage a expiré. Demandez un nouveau lien au patient.';
      }, Math.max(0, expires.getTime() - Date.now()));
    } catch (error) {
      feedback.textContent = error.name === 'AbortError'
        ? 'Le serveur met trop de temps à répondre. Réessayez.'
        : error instanceof TypeError ? 'Connexion au serveur impossible. Vérifiez votre connexion.' : error.message;
    } finally {
      clearTimeout(timeout);
      pending = false;
      button.disabled = pin.disabled;
      button.textContent = 'Consulter le document ↗';
    }
  });
  document.querySelector('#close').addEventListener('click', () => {
    clearPreview();
    feedback.textContent = 'Aperçu fermé. Saisissez le PIN pour ouvrir à nouveau le document.';
    pin.focus();
  });
  window.addEventListener('pagehide', clearPreview);
})();
