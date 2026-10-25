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

  // 从 callAsyncJavaScript 的 arguments 里提取文本。
  // WebKit 传入的 arguments 形态不固定（可能是数组、可能是字典、也可能是 [字典]），
  // 这里逐层兼容，避免取到 undefined 后把字符串 "undefined" 填进输入框。
  function pickText(a) {
    if (a === undefined || a === null) { return null; }
    if (typeof a === 'string') { return a; }
    if (typeof a === 'number' || typeof a === 'boolean') { return String(a); }
    if (Object.prototype.toString.call(a) === '[object Array]') {
      for (var i = 0; i < a.length; i++) {
        var t = pickText(a[i]);
        if (t !== null) { return t; }
      }
      return null;
    }
    if (typeof a === 'object') {
      if (typeof a.payload === 'string') { return a.payload; }
      if (typeof a.text === 'string') { return a.text; }
      for (var k in a) {
        if (!Object.prototype.hasOwnProperty.call(a, k)) { continue; }
        var v = pickText(a[k]);
        if (v !== null) { return v; }
      }
    }
    return null;
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
  // 记录我们最近一次发出去的文本，用于识别「回显」——把自己发的用户消息
  // 误当成 DeepSeek 的回复，会导致工具块解析读到系统提示词里的示例。
  function markSent(text) {
    try { window.__eagentLastSent = String(text || ''); } catch (e) {}
  }
  function isOwnEcho(t) {
    try {
      var sent = window.__eagentLastSent;
      if (!sent) { return false; }
      var probe = sent.slice(0, 24);
      if (probe.length < 4) { return false; }
      return t.indexOf(probe) === 0;
    } catch (e) { return false; }
  }

  // 候选的「助手消息」元素，按文档顺序返回。
  // 注意：不要用 [class*="message"]——那会连用户消息一起匹配上。
  function assistantCandidates() {
    var sels = [
      '[data-message-author-role="assistant"]',
      '.ds-markdown',
      '[class*="markdown"]'
    ];
    var out = [];
    for (var si = 0; si < sels.length; si++) {
      var els = document.querySelectorAll(sels[si]);
      for (var i = 0; i < els.length; i++) {
        var el = els[i];
        if (out.indexOf(el) === -1) { out.push(el); }
      }
    }
    // 按在文档中的位置排序，保证「最后一条」判断正确
    out.sort(function (a, b) {
      if (!a.compareDocumentPosition) { return 0; }
      if (a === b) { return 0; }
      return (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) ? -1 : 1;
    });
    return out;
  }

  // 判断某个元素是否属于「用户消息」（我们发出去的那条）。
  // 优先看 DOM 上的角色标记，其次看文本是否与我们发出的内容吻合。
  function isUserMessage(el) {
    try {
      var role = el.getAttribute && el.getAttribute('data-message-author-role');
      if (role === 'user') { return true; }
      var cls = (el.className && String(el.className)) || '';
      if (/user|question|input/i.test(cls) && !/assistant|markdown|answer/i.test(cls)) { return true; }
    } catch (e) {}
    return false;
  }

  // 取「最后一条」助手回复，而不是「最长的一条」。
  // 最长的往往是我们自己回灌的那条用户消息（内含系统提示词），会导致工具块误解析。
  function lastReplyText() {
    var list = assistantCandidates();
    for (var i = list.length - 1; i >= 0; i--) {
      var el = list[i];
      if (!visible(el)) { continue; }
      if (isUserMessage(el)) { continue; }
      var t = (el.innerText || '').trim();
      if (!t) { continue; }
      if (isOwnEcho(t)) { continue; }
      return t;
    }
    return '';
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
    send: function (arg) {
      var text = pickText(arg);
      if (text === null) { return JSON.stringify({ ok: false, why: 'no-arg' }); }
      var ta = findTextarea();
      if (!ta) { return JSON.stringify({ ok: false, why: 'no-textarea' }); }
      setValue(ta, text);
      markSent(text);
      var btn = null;
      try { btn = findSendButton(ta); } catch (e) {}
      var clicked = false;
      if (btn) { try { btn.click(); clicked = true; } catch (e) {} }
      if (!clicked) { pressEnter(ta); }
      return JSON.stringify({ ok: true, clicked: clicked, leftChars: (ta.value || '').length, sent: text.length });
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
