
// ---- DD Party: DeskDroid's look for the browser (chrome/*.css) -------------
// AutoConfig runs this at startup with the browser's privileges (settings.sh
// turns its sandbox off), so the style sheets apply in every profile,
// including a new one, without userChrome.css in it.
try {
  const sss = Cc["@mozilla.org/content/style-sheet-service;1"].getService(Ci.nsIStyleSheetService);
  for (const name of ["userChrome.css", "userContent.css"]) {
    const f = Services.dirsvc.get("GreD", Ci.nsIFile);
    f.append("etherium-chrome");
    f.append(name);
    if (!f.exists()) continue;
    const uri = Services.io.newFileURI(f);
    if (!sss.sheetRegistered(uri, sss.USER_SHEET)) sss.loadAndRegisterSheet(uri, sss.USER_SHEET);
  }
} catch (e) {
  Cu.reportError("Etherium: DD Party style sheets: " + e);
}
