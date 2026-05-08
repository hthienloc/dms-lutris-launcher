import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "lutris"

    StyledText {
        width: parent.width
        text: "Lutris Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledRect {
        width: parent.width
        height: blacklistColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        visible: (pluginData.blacklist && pluginData.blacklist.length > 0)

        Column {
            id: blacklistColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Hidden Games (Blacklist)"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            Repeater {
                model: pluginData.blacklist || []
                delegate: Row {
                    width: parent.width
                    spacing: Theme.spacingM

                    StyledText {
                        width: parent.width - 100
                        text: {
                            // Try to find name from allGames list
                            var slug = modelData
                            var name = slug
                            if (pluginData.allGames) {
                                for (var i = 0; i < pluginData.allGames.length; i++) {
                                    if (pluginData.allGames[i].slug === slug) {
                                        name = pluginData.allGames[i].name
                                        break
                                    }
                                }
                            }
                            return name
                        }
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    DankButton {
                        width: 80
                        height: 32
                        text: "Unhide"
                        iconName: "visibility"
                        backgroundColor: Theme.secondaryContainer
                        textColor: Theme.onSecondaryContainer
                        onClicked: {
                            var newBlacklist = pluginData.blacklist.slice()
                            var idx = newBlacklist.indexOf(modelData)
                            if (idx >= 0) {
                                newBlacklist.splice(idx, 1)
                                pluginService.savePluginData(root.pluginId, "blacklist", newBlacklist)
                            }
                        }
                    }
                }
            }
        }
    }

    StyledRect {
        width: parent.width
        height: 60
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        visible: !pluginData.blacklist || pluginData.blacklist.length === 0

        StyledText {
            anchors.centerIn: parent
            text: "No games are currently hidden."
            color: Theme.surfaceVariantText
        }
    }

    StyledRect {
        width: parent.width
        height: infoColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surface

        Column {
            id: infoColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                spacing: Theme.spacingM

                DankIcon {
                    name: "info"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "About Blacklist"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: "To hide a game, right-click its banner in the main widget and select 'Hide Game'. You can unhide them here in the settings."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }
        }
    }
}
