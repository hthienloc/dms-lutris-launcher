import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "./dms-common"

PluginSettings {
    id: root
    pluginId: "lutrisLauncher"

    SettingsCard {
        SectionTitle { text: I18n.tr("Usage Guide"); icon: "help" }
        UsageGuide {
            items: [
                I18n.tr("Left Click: Launch the selected game instantly."),
                I18n.tr("Right Click: Show detailed stats and hide/blacklist options."),
                I18n.tr("Blacklist Toggle: Manage your hidden games library directly from the widget.")
            ]
        }
    }

    SettingsCard {
        SectionTitle { text: I18n.tr("Display Options"); icon: "visibility" }

        SelectionSetting {
            settingKey: "dateFormat"
            label: I18n.tr("Last Played Format")
            description: I18n.tr("Choose how the last played date is displayed")
            options: [
                { label: I18n.tr("YYYY - MM - DD"), value: "YYYY - MM - DD" },
                { label: I18n.tr("DD / MM / YYYY"), value: "DD / MM / YYYY" },
                { label: I18n.tr("MM / DD / YYYY"), value: "MM / DD / YYYY" },
                { label: I18n.tr("Relative time"), value: "relative" }
            ]
            defaultValue: "YYYY - MM - DD"
        }

        ToggleSetting {
            settingKey: "showHints"
            label: I18n.tr("Show Hints")
            description: I18n.tr("Display helpful usage tips and shortcuts at the bottom of the popout.")
            defaultValue: true
        }
    }

    PluginAbout {
        repoUrl: "https://github.com/hthienloc/dms-lutris-launcher"
    }
}
