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
// ---- DeskDroid's desktop ---------------------------------------------------
// Scrolling that stops responding (touch, touchpad and mouse at once): on
// Wayland Firefox paces scrolling by the compositor's frame callbacks, and
// stalls when they pause. Its own timer instead.
pref("widget.wayland.vsync.enabled", false);
