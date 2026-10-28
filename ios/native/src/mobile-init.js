(() => {
  // Older server frontends use randomUUID directly. UUID generation only needs
  // getRandomValues; leave secure-context APIs and certificate checks untouched.
  if (typeof crypto.randomUUID !== 'function') {
    Object.defineProperty(crypto, 'randomUUID', {configurable: true, value() {
      const bytes = crypto.getRandomValues(new Uint8Array(16));
      bytes[6] = (bytes[6] & 15) | 64;
      bytes[8] = (bytes[8] & 63) | 128;
      const hex = Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
      return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
    }});
  }
  Object.defineProperty(window, '__LUMIVERSE_MOBILE__', {value: true});
  Object.defineProperty(window, '__LUMIVERSE_PLATFORM__', {value: 'ios'});
  Object.defineProperty(window, '__LUMIVERSE_IOS_NATIVE__', {value: Object.freeze({
    version: 1,
    request(action, payload = {}) {
      const handler = window.webkit?.messageHandlers?.lumiverseNative;
      if (!handler) return Promise.reject(new Error('Update the Lumiverse iOS app to enable native permissions.'));
      return handler.postMessage({action, payload});
    }
  })});

  // UIKit's 650 ms app-controls hold is slower than page long-press timers.
  // WebKit's touch recognizers can keep delivering DOM events alongside UIKit,
  // so cancel page handlers at the second contact, before their timers fire.
  const touchTargets = new Set();
  const pointers = new Map();
  const cancellations = new WeakSet();
  let reserved = false, suppressUntil = 0;
  const fingers = event => Array.from(event.touches).filter(touch => touch.touchType !== 'stylus');
  const cancelPageTouches = touches => {
    if (reserved) return;
    reserved = true;
    for (const target of touchTargets) {
      const event = new TouchEvent('touchcancel', {bubbles: true,
        touches: [], targetTouches: [], changedTouches: touches.filter(touch => touch.target === target)});
      cancellations.add(event);
      target.dispatchEvent(event);
    }
    for (const [pointerId, pointer] of pointers) {
      const event = new PointerEvent('pointercancel', {bubbles: true,
        pointerId, pointerType: 'touch', isPrimary: pointer.isPrimary,
        clientX: pointer.clientX, clientY: pointer.clientY});
      cancellations.add(event);
      pointer.target.dispatchEvent(event);
    }
  };
  const resetTouches = () => { reserved = false; touchTargets.clear(); pointers.clear(); };
  const capture = {capture: true, passive: true};
  window.addEventListener('pointerdown', event => {
    if (event.pointerType !== 'touch') {
      if (!reserved) suppressUntil = 0;
      return;
    }
    if (!reserved && pointers.size === 0) suppressUntil = 0;
    pointers.set(event.pointerId, event);
    touchTargets.add(event.target);
    if (pointers.size > 1) cancelPageTouches([]);
    if (reserved) event.stopImmediatePropagation();
  }, capture);
  for (const type of ['pointermove', 'pointerup', 'pointercancel']) {
    window.addEventListener(type, event => {
      if (cancellations.has(event) || event.pointerType !== 'touch') return;
      if (reserved) event.stopImmediatePropagation();
      if (type !== 'pointermove') pointers.delete(event.pointerId);
    }, capture);
  }
  window.addEventListener('touchstart', event => {
    const touches = fingers(event);
    if (!reserved && touches.length === 1) suppressUntil = 0;
    for (const touch of touches) touchTargets.add(touch.target);
    if (touches.length > 1) cancelPageTouches(touches);
    if (reserved) event.stopImmediatePropagation();
  }, capture);
  window.addEventListener('touchmove', event => {
    if (reserved) event.stopImmediatePropagation();
  }, capture);
  for (const type of ['touchend', 'touchcancel']) {
    window.addEventListener(type, event => {
      if (cancellations.has(event)) return;
      if (reserved) {
        event.stopImmediatePropagation();
        // WebKit can dispatch its contextmenu/click after the last finger lifts.
        suppressUntil = performance.now() + 800;
      }
      if (fingers(event).length === 0) resetTouches();
    }, capture);
  }
  for (const type of ['contextmenu', 'click']) {
    window.addEventListener(type, event => {
      if (!reserved && performance.now() >= suppressUntil) return;
      event.preventDefault();
      event.stopImmediatePropagation();
    }, {capture: true, passive: false});
  }
  window.addEventListener('keydown', () => { if (!reserved) suppressUntil = 0; }, capture);
  window.addEventListener('pagehide', () => { resetTouches(); suppressUntil = 0; });
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'hidden') { resetTouches(); suppressUntil = 0; }
  });

  const mark = () => {
    document.documentElement?.setAttribute('data-tauri-mobile', 'ios');
    document.documentElement?.setAttribute('data-platform', 'ios');
    document.documentElement?.setAttribute('data-ios', '');
    document.documentElement?.removeAttribute('data-tauri-desktop');
  };
  mark();
  document.addEventListener('DOMContentLoaded', mark, {once: true});
})();
