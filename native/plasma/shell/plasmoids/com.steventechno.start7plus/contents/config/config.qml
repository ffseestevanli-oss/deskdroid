import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory { name: i18n("General");         icon: "configure";        source: "configGeneral.qml" }
    ConfigCategory { name: i18n("Orb / Button");    icon: "start-here-kde";   source: "configOrb.qml" }
    ConfigCategory { name: i18n("Places");          icon: "folder";           source: "configPlaces.qml" }
    ConfigCategory { name: i18n("Custom Places");   icon: "bookmarks";        source: "configCustomPlaces.qml" }
    ConfigCategory { name: i18n("Manage Entries");  icon: "view-list-details"; source: "configManage.qml" }
    ConfigCategory { name: i18n("Profile Picture"); icon: "user-identity";    source: "configAvatar.qml" }
    ConfigCategory { name: i18n("Special");         icon: "applications-other"; source: "configSpecial.qml" }
    ConfigCategory { name: i18n("About");           icon: "help-about";       source: "configAbout.qml" }
}
