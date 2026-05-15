import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "./components"

PluginSettings {
    id: root
    pluginId: "lutrisLauncher"

    PluginHeader {
        title: "Lutris Launcher Settings"
    }

    SettingsCard {
        SectionTitle { text: "Display Options" }

        SelectionSetting {
            settingKey: "dateFormat"
            label: "Last Played Format"
            description: "Choose how the last played date is displayed"
            options: [
                { label: "YYYY - MM - DD", value: "YYYY - MM - DD" },
                { label: "DD / MM / YYYY", value: "DD / MM / YYYY" },
                { label: "MM / DD / YYYY", value: "MM / DD / YYYY" },
                { label: "Relative time", value: "relative" }
            ]
            defaultValue: "YYYY - MM - DD"
        }

        ToggleSetting {
            settingKey: "showHints"
            label: "Show Hints"
            description: "Display helpful usage tips and shortcuts at the bottom of the popout."
            defaultValue: true
        }
    }

    SettingsCard {
        SectionTitle { text: "Quick Guide" }
        
        InfoText {
            text: "• Left Click: Launch game\n• Right Click: Show stats & hide option\n• Blacklist Toggle: View and manage hidden games directly in the main widget."
        }
    }
}
