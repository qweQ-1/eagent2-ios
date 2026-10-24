import Foundation

/// 注入到 DeepSeek 页面的 JS 桥（WKUserScript, atDocumentStart）。
/// 注意：本文件是 Swift raw string，JS 里不要出现 """ 或 \#( 序列。
public enum BridgeScript {
    public static let source = #"""
(function () {
  if (window.__EAGENT_BRIDGE__) { return; }
  window.__EAGENT_BRIDGE__ = true;
  window.__eagentToken = null;

  function post(msg) {
    try { window.webkit.messageHandlers.eagent.postMessage(msg); } catch (e) {}
  }
  function nowLogin() {
    try {
      var t = null;
      try { t = window.localStorage.getItem('userToken'); } catch (e) {}
      if (!t) { try { t = window.sessionStorage.getItem('userToken'); } catch (e) {} }
      if (t) { return String(t).length > 8 && String(t).indexOf('null') !== 0; }
      return !!window.__eagentToken;
    } catch (e) { return false; }
  }
  function reportAuth(v) {
    if (window.__eagentToken) { return; }
    window.__eagentToken = v;
    post({ type: 'token' });
  }

  try {
    var ofetch = window.fetch;
    if (ofetch) {
      window.fetch = function () {
        try {
          var a = arguments[1];
          var h = a && a.headers;
          if (h) {
            var auth = (h.get && h.get('authorization')) || h['Authorization'] || h['authorization'];
            if (auth) { reportAuth(auth); }
          }
        } catch (e) {}
        return ofetch.apply(this, arguments);
      };
    }
  } catch (e) {}
  try {
    var oSet = XMLHttpRequest.prototype.setRequestHeader;
    XMLHttpRequest.prototype.setRequestHeader = function (k, v) {
      try { if (String(k).toLowerCase() === 'authorization') { reportAuth(v); } } catch (e) {}
      return oSet.apply(this, arguments);
    };
  } catch (e) {}

  function visible(el) {
    if (!el) { return false; }
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }
  function findTextarea() {
    var tas = document.querySelectorAll('textarea.ds-textarea__textarea, textarea');
    for (var i = 0; i < tas.length; i++) {
      var t = tas[i];
      if (!visible(t)) { continue; }
      if (t.disabled) { continue; }
      return t;
    }
    return null;
  }
  function findSendButton(ta) {
    var box = null;
    try { box = ta.closest('form') || ta.closest('[class*="textarea"]') || ta.closest('[class*="input"]') || ta.parentElement; } catch (e) { box = ta.parentElement; }
    if (!box) { return null; }
    var els = box.querySelectorAll('button, [role="button"]');
    var cand = [];
    for (var i = 0; i < els.length; i++) {
      var b = els[i];
      if (!visible(b)) { continue; }
      var label = ((b.getAttribute('aria-label') || '') + ' ' + (b.innerText || '')).replace(/\s+/g, '');
      if (/发送|send/i.test(label)) { return b; }
      cand.push(b);
    }
    for (var j = cand.length - 1; j >= 0; j--) {
      var el = cand[j];
      if (el.getAttribute('aria-disabled') === 'true' || el.disabled) { continue; }
      var rect = el.getBoundingClientRect();
      if (rect.width > 20 && rect.width < 90 && rect.height > 20 && rect.height < 90) { return el; }
    }
    return null;
  }
  function pressEnter(ta) {
    ['keydown', 'keypress', 'keyup'].forEach(function (type) {
      ta.dispatchEvent(new KeyboardEvent(type, { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true }));
    });
  }
  function setValue(ta, text) {
    var desc = null;
    try {
      var proto = (window.HTMLTextAreaElement && ta instanceof HTMLTextAreaElement) ? window.HTMLTextAreaElement.prototype : (ta.tagName === 'INPUT' ? window.HTMLInputElement.prototype : null);
      if (proto) { desc = Object.getOwnPropertyDescriptor(proto, 'value'); }
    } catch (e) {}
    try { ta.focus(); } catch (e) {}
    if (desc && desc.set) { desc.set.call(ta, text); } else { ta.value = text; }
    ta.dispatchEvent(new Event('input', { bubbles: true }));
    ta.dispatchEvent(new Event('change', { bubbles: true }));
  }
  function isGenerating() {
    var els = document.querySelectorAll('button, [role="button"], [class*="stop"]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (!visible(el)) { continue; }
      var txt = ((el.getAttribute('aria-label') || '') + ' ' + (el.innerText || '')).replace(/\s+/g, '');
      if (/停止|stop/i.test(txt)) { return true; }
    }
    return false;
  }
  function lastReplyText() {
    var list = document.querySelectorAll('.ds-markdown, [class*="markdown"], [class*="message"]');
    var best = '';
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (!visible(el)) { continue; }
      var t = (el.innerText || '').trim();
      if (t.length > best.length) { best = t; }
    }
    return best;
  }
  function clickStop() {
    var els = document.querySelectorAll('button, [role="button"], [class*="stop"]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i];
      if (!visible(el)) { continue; }
      var txt = ((el.getAttribute('aria-label') || '') + ' ' + (el.innerText || '')).replace(/\s+/g, '');
      if (/停止|stop/i.test(txt)) { try { el.click(); return true; } catch (e) {} }
    }
    return false;
  }

  window.EAgentBridge = {
    state: function () {
      return JSON.stringify({
        login: nowLogin(),
        hasInput: !!findTextarea(),
        generating: isGenerating(),
        replyLen: lastReplyText().length
      });
    },
    send: function (text) {
      var ta = findTextarea();
      if (!ta) { return JSON.stringify({ ok: false, why: 'no-textarea' }); }
      setValue(ta, text);
      var btn = null;
      try { btn = findSendButton(ta); } catch (e) {}
      var clicked = false;
      if (btn) { try { btn.click(); clicked = true; } catch (e) {} }
      if (!clicked) { pressEnter(ta); }
      return JSON.stringify({ ok: true, clicked: clicked, leftChars: (ta.value || '').length });
    },
    pressEnter: function () {
      var ta = findTextarea();
      if (!ta) { return JSON.stringify({ ok: false }); }
      pressEnter(ta);
      return JSON.stringify({ ok: true });
    },
    collect: function () {
      var txt = lastReplyText();
      return JSON.stringify({ len: txt.length, text: txt, generating: isGenerating(), login: nowLogin() });
    },
    stop: function () {
      return JSON.stringify({ clicked: clickStop() });
    }
  };
})();
"""#
}
