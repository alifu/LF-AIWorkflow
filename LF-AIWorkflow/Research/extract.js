(function () {
  'use strict';
  var MAX_TEXT = 200000, MAX_HEADINGS = 200, MAX_LINKS = 300;
  var MAX_TABLES = 50, MAX_ROWS = 500, MAX_COLS = 30, MAX_CELL = 500;
  var SKIP = 'nav,header,footer,aside,script,style,noscript,form,input,textarea,select,template,[aria-hidden="true"]';
  var BLOCK = /^(P|DIV|SECTION|ARTICLE|MAIN|LI|UL|OL|TR|TABLE|H[1-6]|PRE|BLOCKQUOTE|BR|DL|DT|DD|FIGURE|FIGCAPTION)$/;

  function hidden(el) {
    if (el.hidden) return true;
    var s = window.getComputedStyle(el);
    return s.display === 'none' || s.visibility === 'hidden';
  }
  function skipped(el) { return el.matches(SKIP) || hidden(el); }
  function squash(s) { return s.replace(/\s+/g, ' ').trim(); }

  function collect(el, out) {
    if (out.len >= MAX_TEXT) return;
    for (var n = el.firstChild; n; n = n.nextSibling) {
      if (out.len >= MAX_TEXT) return;
      if (n.nodeType === 3) {
        var t = n.nodeValue.replace(/\s+/g, ' ');
        out.parts.push(t); out.len += t.length;
      } else if (n.nodeType === 1 && !skipped(n)) {
        var b = BLOCK.test(n.tagName);
        if (b) out.parts.push('\n');
        collect(n, out);
        if (b) out.parts.push('\n');
      }
    }
  }
  function blockScore(el) {
    var score = 0, kids = el.children;
    for (var i = 0; i < kids.length; i++) {
      if (/^(P|LI|PRE|BLOCKQUOTE)$/.test(kids[i].tagName) && !skipped(kids[i])) score += kids[i].textContent.length;
    }
    return score;
  }
  function mainRoot() {
    var el = document.querySelector('article') || document.querySelector('main');
    if (el && !hidden(el)) return el;
    var best = null, bestScore = 0, cands = document.querySelectorAll('div,section,td,body');
    for (var i = 0; i < cands.length; i++) {
      if (skipped(cands[i]) || cands[i].closest(SKIP)) continue;
      var s = blockScore(cands[i]);
      if (s > bestScore) { best = cands[i]; bestScore = s; }
    }
    return best || document.body || document.documentElement;
  }

  var root = mainRoot();
  var acc = { parts: [], len: 0 };
  collect(root, acc);
  var text = acc.parts.join('').split('\n').map(function (l) { return l.replace(/ +/g, ' ').trim(); })
    .join('\n').replace(/\n{3,}/g, '\n\n').trim().slice(0, MAX_TEXT);

  function visible(el) { return !el.closest(SKIP) && !hidden(el); }

  var headings = [], hs = root.querySelectorAll('h1,h2,h3,h4,h5,h6');
  for (var i = 0; i < hs.length && headings.length < MAX_HEADINGS; i++) {
    if (!visible(hs[i])) continue;
    var h = squash(hs[i].textContent);
    if (h) headings.push(h.slice(0, MAX_CELL));
  }
  var links = [], as = root.querySelectorAll('a[href]');
  for (var j = 0; j < as.length && links.length < MAX_LINKS; j++) {
    if (!visible(as[j])) continue;
    var p = as[j].protocol;
    if (p === 'http:' || p === 'https:') links.push(as[j].href);
  }
  var tables = [], ts = root.querySelectorAll('table');
  for (var k = 0; k < ts.length && tables.length < MAX_TABLES; k++) {
    if (!visible(ts[k])) continue;
    var rows = [], trs = ts[k].querySelectorAll('tr');
    for (var r = 0; r < trs.length && rows.length < MAX_ROWS; r++) {
      var cells = [], tds = trs[r].querySelectorAll('th,td');
      for (var c = 0; c < tds.length && cells.length < MAX_COLS; c++) cells.push(squash(tds[c].textContent).slice(0, MAX_CELL));
      if (cells.length) rows.push(cells);
    }
    if (rows.length) tables.push(rows);
  }
  return JSON.stringify({
    v: 1, title: document.title || '', url: location.href, text: text,
    headings: headings, links: links, tables: tables,
    hasPasswordField: document.querySelector('input[type="password"]') !== null
  });
})();
