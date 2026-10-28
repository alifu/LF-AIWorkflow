// Read-only Safari bridge, run as: osascript -l JavaScript safari-bridge.js <command> <args...>
// Arguments arrive as argv only; nothing is ever interpolated into script source.
ObjC.import('Foundation');

function readFile(path) {
  var err = $();
  var s = $.NSString.stringWithContentsOfFileEncodingError($(path), $.NSUTF8StringEncoding, err);
  if (s.isNil()) throw new Error('extractScriptMissing');
  return ObjC.unwrap(s);
}

function isHttp(url) { return /^https?:\/\//i.test(url || ''); }

function run(argv) {
  var safari = Application('Safari');
  if (!safari.running()) throw new Error("Application isn't running. (-600)");
  var command = argv[0];
  if (command === 'list') {
    var out = [];
    var windows = safari.windows();
    for (var w = 0; w < windows.length; w++) {
      var tabs = windows[w].tabs();
      var currentIndex = -1;
      try { currentIndex = windows[w].currentTab().index(); } catch (e) {}
      for (var t = 0; t < tabs.length; t++) {
        var url = tabs[t].url();
        if (!isHttp(url)) continue;
        out.push({ window: w + 1, tab: t + 1, title: tabs[t].name() || '', url: url,
                   current: w === 0 && (t + 1) === currentIndex });
      }
    }
    return JSON.stringify(out);
  }
  if (command === 'extract') {
    var win = safari.windows()[parseInt(argv[1], 10) - 1];
    var tab = win.tabs()[parseInt(argv[2], 10) - 1];
    if (tab.url() !== argv[3] || !isHttp(tab.url())) throw new Error('tabChanged');
    var src = readFile(argv[4]);
    return safari.doJavaScript(src, { in: tab });
  }
  throw new Error('unknownCommand');
}
