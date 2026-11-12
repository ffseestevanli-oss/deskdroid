// ---- Etherium (DeskDroid): nothing phones home -----------------------------
// Firefox reaches Mozilla, Google and others on its own in many places. These
// defaults turn all of it off; anyone can turn a piece back on in about:config.
// Telemetry, studies, crash reports.
pref("datareporting.healthreport.uploadEnabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("datareporting.policy.firstRunURL", "");
pref("datareporting.usage.uploadEnabled", false);
pref("toolkit.telemetry.enabled", false);
pref("toolkit.telemetry.unified", false);
pref("toolkit.telemetry.archive.enabled", false);
pref("toolkit.telemetry.server", "");
pref("toolkit.telemetry.newProfilePing.enabled", false);
pref("toolkit.telemetry.shutdownPingSender.enabled", false);
pref("toolkit.telemetry.updatePing.enabled", false);
pref("toolkit.telemetry.bhrPing.enabled", false);
pref("toolkit.telemetry.firstShutdownPing.enabled", false);
pref("toolkit.telemetry.reportingpolicy.firstRun", false);
pref("toolkit.telemetry.coverage.opt-out", true);
pref("toolkit.coverage.opt-out", true);
pref("toolkit.coverage.endpoint.base", "");
pref("app.shield.optoutstudies.enabled", false);
pref("app.normandy.enabled", false);
pref("app.normandy.api_url", "");
pref("messaging-system.rsexperimentloader.enabled", false);
pref("nimbus.telemetry.targetingContextEnabled", false);
pref("breakpad.reportURL", "");
pref("browser.tabs.crashReporting.sendReport", false);
pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
pref("browser.ping-centre.telemetry", false);
pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
pref("browser.newtabpage.activity-stream.telemetry", false);
pref("extensions.webcompat-reporter.enabled", false);
// Mozilla's settings server (blocklists, experiments, search settings):
// pointed at a closed local port, so it is never asked. Firefox falls back
// to the copies it ships with.
pref("services.settings.server", "http://127.0.0.1:9/v1");
// Connectivity and captive-portal checks (detectportal.firefox.com).
pref("network.captive-portal-service.enabled", false);
pref("network.connectivity-service.enabled", false);
pref("captivedetect.canonicalURL", "");
// Safe Browsing (Google's lists, Mozilla's download checks).
pref("browser.safebrowsing.malware.enabled", false);
pref("browser.safebrowsing.phishing.enabled", false);
pref("browser.safebrowsing.blockedURIs.enabled", false);
pref("browser.safebrowsing.downloads.enabled", false);
pref("browser.safebrowsing.downloads.remote.enabled", false);
pref("browser.safebrowsing.downloads.remote.url", "");
pref("browser.safebrowsing.provider.google.updateURL", "");
pref("browser.safebrowsing.provider.google.gethashURL", "");
pref("browser.safebrowsing.provider.google4.updateURL", "");
pref("browser.safebrowsing.provider.google4.gethashURL", "");
pref("browser.safebrowsing.provider.mozilla.updateURL", "");
pref("browser.safebrowsing.provider.mozilla.gethashURL", "");
// Location and region lookups.
pref("geo.provider.network.url", "");
pref("browser.region.network.url", "");
pref("browser.region.update.enabled", false);
// Add-ons: no recommendations, no update checks (uBlock Origin updates its
// filter lists itself).
pref("extensions.getAddons.showPane", false);
pref("extensions.htmlaboutaddons.recommendations.enabled", false);
pref("extensions.update.enabled", false);
pref("extensions.update.autoUpdateDefault", false);
pref("extensions.systemAddon.update.enabled", false);
pref("extensions.systemAddon.update.url", "");
pref("browser.discovery.enabled", false);
// New tab and address bar: no Pocket, sponsored tiles, suggestions.
pref("extensions.pocket.enabled", false);
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("browser.newtabpage.activity-stream.discoverystream.enabled", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
pref("browser.topsites.contile.enabled", false);
pref("browser.urlbar.quicksuggest.enabled", false);
pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
pref("browser.urlbar.suggest.quicksuggest.nonsponsored", false);
pref("browser.urlbar.trending.featureGate", false);
pref("browser.search.suggest.enabled", false);
pref("browser.preferences.moreFromMozilla", false);
pref("browser.vpn_promo.enabled", false);
// Connections opened before you click.
pref("network.prefetch-next", false);
pref("network.dns.disablePrefetch", true);
pref("network.http.speculative-parallel-limit", 0);
pref("browser.urlbar.speculativeConnect.enabled", false);
pref("browser.places.speculativeConnect.enabled", false);
// Web push (Mozilla's push server), DNS over HTTPS rollout, plugin downloads.
pref("dom.push.connection.enabled", false);
pref("dom.push.serverURL", "");
pref("doh-rollout.enabled", false);
pref("media.gmp-provider.enabled", false);
pref("media.gmp-manager.url", "");
pref("media.gmp-gmpopenh264.enabled", false);
pref("browser.startup.homepage_override.mstone", "ignore");
// ---- Etherium (DeskDroid): no Google ---------------------------------------
// Startpage (Google's results, without Google seeing who asked) is the search
// engine, in private windows too. branding.py takes Google out of the search
// engines Etherium ships with; policies.json sets the default and removes
// Google from builds made before that.
pref("browser.search.separatePrivateDefault", true);
pref("browser.search.separatePrivateDefault.ui.enabled", true);
pref("browser.urlbar.placeholderName", "Startpage");
pref("browser.urlbar.placeholderName.private", "Startpage");
// Widevine is Google's DRM module, downloaded from Google: off, with the
// rest of the DRM machinery (there is no Widevine for this build anyway).
pref("media.eme.enabled", false);
pref("media.gmp-widevinecdm.enabled", false);
pref("media.gmp-widevinecdm.visible", false);
pref("media.gmp-manager.updateEnabled", false);
// Google's Safe Browsing report and advisory pages, should anyone turn Safe
// Browsing back on.
pref("browser.safebrowsing.provider.google.reportURL", "");
pref("browser.safebrowsing.provider.google4.reportURL", "");
pref("browser.safebrowsing.provider.google4.dataSharingURL", "");
pref("browser.safebrowsing.provider.google4.dataSharing.enabled", false);
pref("browser.safebrowsing.reportPhishURL", "");
// ---- Etherium (DeskDroid): privacy -----------------------------------------
// Tracking protection on Strict: trackers, cross-site cookies (each site
// gets its own cookie jar), cryptominers, fingerprinters, social trackers.
pref("browser.contentblocking.category", "strict");
pref("privacy.trackingprotection.enabled", true);
pref("privacy.trackingprotection.pbmode.enabled", true);
pref("privacy.trackingprotection.socialtracking.enabled", true);
pref("privacy.trackingprotection.emailtracking.enabled", true);
pref("privacy.trackingprotection.fingerprinting.enabled", true);
pref("privacy.trackingprotection.cryptomining.enabled", true);
pref("privacy.fingerprintingProtection", true);
pref("network.cookie.cookieBehavior", 5);
// Tracking bits stripped from links (?fbclid=, ?gclid= and the like).
pref("privacy.query_stripping.enabled", true);
pref("privacy.query_stripping.enabled.pbmode", true);
// Sites are told not to sell or share your data (Global Privacy Control,
// legally binding in some places), and Do Not Track.
pref("privacy.globalprivacycontrol.enabled", true);
pref("privacy.donottrackheader.enabled", true);
// Other sites only learn which site sent you, not the page.
pref("network.http.referer.XOriginTrimmingPolicy", 2);
// HTTPS only: plain HTTP pages ask first.
pref("dom.security.https_only_mode", true);
pref("dom.security.https_only_mode_send_http_background_request", false);
// Lookalike web addresses (Cyrillic "а" for "a") shown as what they are,
// since Safe Browsing is off.
pref("network.IDN_show_punycode", true);
// No hyperlink-auditing pings, no battery level for sites.
pref("browser.send_pings", false);
pref("dom.battery.enabled", false);
// Nothing sent to Mozilla about the sites you visit or what you type.
pref("browser.urlbar.suggest.trending", false);
pref("browser.urlbar.suggest.weather", false);
pref("browser.urlbar.suggest.yelp", false);
pref("browser.urlbar.suggest.fakespot", false);
pref("browser.urlbar.suggest.mdn", false);
pref("browser.urlbar.suggest.addons", false);
pref("browser.urlbar.suggest.pocket", false);
pref("browser.newtabpage.activity-stream.feeds.weatherfeed", false);
pref("browser.newtabpage.activity-stream.showWeather", false);
pref("browser.newtabpage.activity-stream.default.sites", "");
pref("browser.contentblocking.report.lockwise.enabled", false);
pref("browser.contentblocking.report.monitor.enabled", false);
pref("dom.private-attribution.submission.enabled", false);
pref("browser.ml.enable", false);
pref("browser.ml.chat.enabled", false);
pref("browser.tabs.groups.smart.enabled", false);
pref("signon.management.page.breach-alerts.enabled", false);
pref("signon.firefoxRelay.feature", "disabled");
pref("browser.shopping.experience2023.enabled", false);
pref("browser.attribution.enabled", false);
// ---- DeskDroid's desktop ---------------------------------------------------
// Scrolling that stops responding (touch, touchpad and mouse at once): on
// Wayland Firefox paces scrolling by the compositor's frame callbacks, and
// stalls when they pause. Its own timer instead.
pref("widget.wayland.vsync.enabled", false);

// ---- DD Party: dark like the rest of DeskDroid -----------------------------
// The browser's own pages and toolbars dark, and sites that offer a dark
// version show it (Settings › General › Website appearance changes it).
pref("browser.theme.toolbar-theme", 0);
pref("browser.theme.content-theme", 0);
pref("layout.css.prefers-color-scheme.content-override", 0);
