import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property var games: []
    property bool isLoading: false
    property string statusMessage: ""

    property int launchingId: -1
    readonly property bool isLaunching: launchingId !== -1

    Component.onCompleted: {
        console.log("Lutris Launcher: Plugin initialized")
        fetchGames()
    }

    ListModel {
        id: gamesModel
    }

    ListModel {
        id: filteredGamesModel
    }

    property string searchQuery: ""
    property string filteredStatus: ""
    property bool favoriteOnly: false
    property bool blacklistOnly: false

    property int sortMode: pluginData.sortMode ?? 0
    property var favorites: pluginData.favorites ?? []
    property var playCounts: pluginData.playCounts ?? {}
    property var blacklist: pluginData.blacklist ?? []
    property string dateFormat: pluginData.dateFormat ?? "YYYY - MM - DD"

    function getFormattedDate(timestamp) {
        if (!timestamp) return "Never played"
        var d = new Date(timestamp)
        
        if (dateFormat === "relative") {
            var now = Date.now()
            var diff = now - timestamp
            var seconds = Math.floor(diff / 1000)
            var minutes = Math.floor(seconds / 60)
            var hours = Math.floor(minutes / 60)
            var days = Math.floor(hours / 24)
            
            if (days > 0) return days + "d ago"
            if (hours > 0) return hours + "h ago"
            if (minutes > 0) return minutes + "m ago"
            return "Just now"
        }

        var y = d.getFullYear()
        var m = (d.getMonth() + 1).toString().padStart(2, '0')
        var day = d.getDate().toString().padStart(2, '0')

        if (dateFormat === "DD / MM / YYYY") return day + " / " + m + " / " + y
        if (dateFormat === "MM / DD / YYYY") return m + " / " + day + " / " + y
        return y + " - " + m + " - " + day // Default YYYY - MM - DD
    }

    onPluginDataChanged: {
        if (pluginData.blacklist !== undefined) {
            blacklist = pluginData.blacklist
            updateFilteredModel()
        }
        if (pluginData.dateFormat !== undefined) {
            dateFormat = pluginData.dateFormat
        }
    }

    readonly property var sortModes: [
        { label: "Name", icon: "sort_by_alpha" },
        { label: "Recently Played", icon: "history" },
        { label: "Most Played", icon: "trending_up" }
    ]

    function fetchGames() {
        console.log("Lutris Launcher: Fetching games...")
        isLoading = true
        statusMessage = "Loading games..."
        
        Proc.runCommand(
            "lutris-launcher-fetch",
            ["/usr/bin/lutris", "-l", "-o", "-j"],
            function(output, exitCode) {
                console.log("Lutris Launcher: Fetch finished with exit code: " + exitCode)
                isLoading = false
                if (exitCode !== 0 && exitCode !== 124) { // 124 is timeout but might have data
                    statusMessage = "Error fetching games"
                    return
                }
                if (!output || output.trim() === "") {
                    console.log("Lutris Launcher: No output from Lutris")
                    gamesModel.clear()
                    statusMessage = "No installed games found"
                    return
                }
                try {
                    // Clean output: remove lines starting with date, WARNING, or ERROR
                    var lines = output.split("\n")
                    var cleanLines = lines.filter(function(line) {
                        var trimmed = line.trim()
                        if (trimmed.length === 0) return false
                        // Matches "2024-05-08 18:34:44,385: ..."
                        if (/^\d{4}-\d{2}-\d{2}/.test(trimmed)) return false
                        if (/^WARNING:/.test(trimmed)) return false
                        if (/^ERROR:/.test(trimmed)) return false
                        if (/^INFO/.test(trimmed)) return false
                        return true
                    })
                    
                    var cleanJson = cleanLines.join("\n")
                    // Still try to find the array if there's garbage at start/end
                    var start = cleanJson.indexOf("[")
                    var end = cleanJson.lastIndexOf("]")
                    if (start === -1 || end === -1) {
                        console.error("Lutris Launcher: No JSON array found after cleaning")
                        statusMessage = "Data format error"
                        return
                    }
                    cleanJson = cleanJson.substring(start, end + 1)
                    
                    var parsedGames = JSON.parse(cleanJson)
                    console.log("Lutris Launcher: Parsed " + parsedGames.length + " games")
                    
                    sortGames(parsedGames)

                    gamesModel.clear()
                    var gamesListForSettings = []
                    for (var i = 0; i < parsedGames.length; i++) {
                        gamesModel.append(parsedGames[i])
                        gamesListForSettings.push({
                            "name": parsedGames[i].name,
                            "slug": parsedGames[i].slug
                        })
                    }
                    // Save full list for Settings UI
                    pluginService?.savePluginData(pluginId, "allGames", gamesListForSettings)
                    
                    updateFilteredModel()
                    statusMessage = parsedGames.length + " games found"
                } catch(e) {
                    console.error("Lutris Launcher: Error parsing JSON: " + e)
                    statusMessage = "Error parsing game list"
                }
            },
            20000
        )
    }

    function launchGame(gameId, slug) {
        if (isLaunching) return

        console.log("Lutris Launcher: Launching " + slug)
        launchingId = gameId

        var newCounts = Object.assign({}, playCounts)
        if (!newCounts[slug]) newCounts[slug] = { count: 0, lastPlayed: 0 }
        newCounts[slug].count++
        newCounts[slug].lastPlayed = Date.now()
        playCounts = newCounts
        saveStats()

        Proc.runCommand(
            "lutris-launcher-launch",
            ["sh", "-c", "/usr/bin/lutris lutris:rungame/" + slug + " &"],
            function(output, exitCode) {
                Qt.callLater(() => {
                    var timer = Qt.createQmlObject('import QtQuick; Timer { interval: 20000; repeat: false; onTriggered: { parent.launchingId = -1; destroy(); } }', root);
                    timer.start();
                });
            },
            0
        )
    }

    function updateFilteredModel() {
        console.log("Lutris Launcher: Updating filtered model. Blacklist: " + JSON.stringify(root.blacklist))
        filteredGamesModel.clear()
        var query = searchQuery.toLowerCase().trim()
        
        var currentBlacklist = root.blacklist || []
        var blackSet = new Set()
        for (var b = 0; b < currentBlacklist.length; b++) {
            blackSet.add(currentBlacklist[b])
        }

        for (var i = 0; i < gamesModel.count; i++) {
            var game = gamesModel.get(i)
            var isBlacklisted = blackSet.has(game.slug)

            if (blacklistOnly) {
                if (!isBlacklisted) continue;
            } else {
                if (isBlacklisted) continue;
            }

            var matchesSearch = query === "" || (game.name && game.name.toLowerCase().includes(query))
            var matchesFavorite = !favoriteOnly || root.isFavorite(game.slug)
            if (matchesSearch && matchesFavorite) {
                // Create a fresh object to avoid QML reference issues
                filteredGamesModel.append({
                    "id": game.id,
                    "name": game.name,
                    "slug": game.slug,
                    "coverPath": game.coverPath,
                    "isVirtual": false,
                    "isBlacklisted": isBlacklisted
                })
            }
        }
        
        console.log("Lutris Launcher: Filtered model updated. Count: " + filteredGamesModel.count)
        filteredStatus = query === "" ? "" : filteredGamesModel.count + " of " + gamesModel.count + " games"
    }

    function onSearchTextChanged(text) {
        searchQuery = text
        updateFilteredModel()
    }

    function saveStats() {
        try {
            pluginService?.savePluginData(pluginId, "favorites", favorites)
            pluginService?.savePluginData(pluginId, "playCounts", playCounts)
            pluginService?.savePluginData(pluginId, "sortMode", sortMode)
            pluginService?.savePluginData(pluginId, "blacklist", blacklist)
        } catch(e) {
            console.log("Lutris Launcher: Failed to save stats", e)
        }
    }

    function sortGames(games) {
        var favSet = new Set(favorites)
        if (sortMode === 0) {
            games.sort((a, b) => {
                var aFav = favSet.has(a.slug) ? 0 : 1
                var bFav = favSet.has(b.slug) ? 0 : 1
                if (aFav !== bFav) return aFav - bFav
                return (a.name || "").localeCompare(b.name || "")
            })
        } else if (sortMode === 1) {
            games.sort((a, b) => {
                var aFav = favSet.has(a.slug) ? 0 : 1
                var bFav = favSet.has(b.slug) ? 0 : 1
                if (aFav !== bFav) return aFav - bFav
                var aTime = (playCounts[a.slug]?.lastPlayed || 0)
                var bTime = (playCounts[b.slug]?.lastPlayed || 0)
                return bTime - aTime
            })
        } else if (sortMode === 2) {
            games.sort((a, b) => {
                var aFav = favSet.has(a.slug) ? 0 : 1
                var bFav = favSet.has(b.slug) ? 0 : 1
                if (aFav !== bFav) return aFav - bFav
                var aCount = playCounts[a.slug]?.count || 0
                var bCount = playCounts[b.slug]?.count || 0
                return bCount - aCount
            })
        }
    }

    function toggleFavorite(slug) {
        var newFavs = favorites.slice()
        var idx = newFavs.indexOf(slug)
        if (idx >= 0) {
            newFavs.splice(idx, 1)
        } else {
            newFavs.push(slug)
            // If adding to favorites, remove from blacklist automatically
            var newBlacklist = (root.blacklist || []).slice()
            var bIdx = newBlacklist.indexOf(slug)
            if (bIdx >= 0) {
                newBlacklist.splice(bIdx, 1)
                root.blacklist = newBlacklist
            }
        }
        favorites = newFavs
        saveStats()
        updateFilteredModel()
    }

    function isFavorite(slug) {
        return favorites.indexOf(slug) >= 0
    }

    function toggleBlacklist(slug) {
        var currentBlacklist = (pluginData.blacklist || []).slice()
        var idx = currentBlacklist.indexOf(slug)
        if (idx >= 0) {
            currentBlacklist.splice(idx, 1)
        } else {
            currentBlacklist.push(slug)
        }
        pluginService.savePluginData(pluginId, "blacklist", currentBlacklist)
    }

    function sortGamesInternal() {
        var games = []
        for (var i = 0; i < gamesModel.count; i++) {
            var g = gamesModel.get(i)
            games.push({
                "id": g.id,
                "name": g.name,
                "slug": g.slug,
                "coverPath": g.coverPath
            })
        }
        sortGames(games)
        gamesModel.clear()
        for (var j = 0; j < games.length; j++) {
            gamesModel.append(games[j])
        }
        updateFilteredModel()
    }

    function cycleSortMode() {
        sortMode = (sortMode + 1) % sortModes.length
        saveStats()
        sortGamesInternal()
    }

    horizontalBarPill: Component {
        DankIcon {
            name: (root.isLaunching || root.isLoading) ? "refresh" : "sports_esports"
            size: Theme.iconSizeSmall
            color: (root.isLaunching || root.isLoading) ? Theme.warning : Theme.primary
            anchors.verticalCenter: parent.verticalCenter
            
            rotation: (root.isLaunching || root.isLoading) ? 0 : 0 // Placeholder to trigger binding if needed

            NumberAnimation on rotation {
                from: 0; to: 360; duration: 1000
                loops: Animation.Infinite
                running: root.isLaunching || root.isLoading
            }

            Behavior on rotation {
                enabled: !root.isLaunching && !root.isLoading
                NumberAnimation { duration: 300; easing.type: Easing.OutQuad }
            }
            
            onRotationChanged: {
                if (!root.isLaunching && !root.isLoading && rotation !== 0) {
                    rotation = 0
                }
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: (root.isLaunching || root.isLoading) ? "refresh" : "sports_esports"
            size: Theme.iconSizeSmall
            color: (root.isLaunching || root.isLoading) ? Theme.warning : Theme.primary
            anchors.horizontalCenter: parent.horizontalCenter

            NumberAnimation on rotation {
                from: 0; to: 360; duration: 1000
                loops: Animation.Infinite
                running: root.isLaunching || root.isLoading
            }

            Behavior on rotation {
                enabled: !root.isLaunching && !root.isLoading
                NumberAnimation { duration: 300; easing.type: Easing.OutQuad }
            }
            
            onRotationChanged: {
                if (!root.isLaunching && !root.isLoading && rotation !== 0) {
                    rotation = 0
                }
            }
        }
    }

    popoutContent: Component {
        FocusScope {
            id: contentFocusScope
            width: parent ? parent.width : 0
            implicitHeight: mainContent.implicitHeight
            focus: true

            property var parentPopout: null
            Connections {
                target: parentPopout
                function onOpened() {
                    Qt.callLater(() => {
                        searchField.forceActiveFocus();
                    });
                }
            }

            PopoutComponent {
                id: mainContent
                width: parent.width
                headerText: "Lutris Launcher"
                detailsText: root.isLaunching ? "Launching game..." : root.statusMessage
                showCloseButton: false
                
                Component.onDestruction: {
                    root.searchQuery = "";
                    root.updateFilteredModel();
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingM

                    Row {
                        width: parent.width
                        height: 44
                        spacing: Theme.spacingS

                        DankTextField {
                            id: searchField
                            width: parent.width - 36 - 36 - 36 - 36 - 36 - Theme.spacingS * 5
                            height: parent.height
                            leftIconName: "search"
                            placeholderText: "Search games..."
                            backgroundColor: Theme.surfaceVariant
                            normalBorderColor: Theme.surfaceContainerHigh
                            showClearButton: true
                            onTextEdited: root.onSearchTextChanged(text)
                            onTextChanged: {
                                if (text === "") {
                                    root.searchQuery = "";
                                    root.updateFilteredModel();
                                }
                            }
                            Keys.onTabPressed: {
                                if (filteredGamesModel.count > 0) {
                                    gamesGrid.currentIndex = 0;
                                    gamesGrid.forceActiveFocus();
                                }
                            }
                            Keys.onDownPressed: {
                                if (filteredGamesModel.count > 0) {
                                    gamesGrid.currentIndex = 0;
                                    gamesGrid.forceActiveFocus();
                                }
                            }
                        }

                        DankButton {
                            id: sortButton2
                            width: 36
                            height: parent.height
                            iconName: sortModes[sortMode].icon
                            backgroundColor: Theme.surfaceContainerHigh
                            textColor: Theme.surfaceText
                            onClicked: root.cycleSortMode()
                        }

                        DankButton {
                            id: favoriteOnlyButton
                            width: 36
                            height: parent.height
                            iconName: "star"
                            backgroundColor: root.favoriteOnly ? Theme.warning : Theme.surfaceContainerHigh
                            textColor: root.favoriteOnly ? Theme.onPrimary : Theme.surfaceText
                            onClicked: {
                                root.favoriteOnly = !root.favoriteOnly
                                if (root.favoriteOnly) root.blacklistOnly = false
                                root.updateFilteredModel()
                            }
                        }

                        DankButton {
                            id: blacklistOnlyButton
                            width: 36
                            height: parent.height
                            iconName: "visibility_off"
                            backgroundColor: root.blacklistOnly ? Theme.error : Theme.surfaceContainerHigh
                            textColor: root.blacklistOnly ? Theme.onPrimary : Theme.surfaceText
                            onClicked: {
                                root.blacklistOnly = !root.blacklistOnly
                                if (root.blacklistOnly) root.favoriteOnly = false
                                root.updateFilteredModel()
                            }
                        }

                        DankButton {
                            id: settingsButton
                            width: 36
                            height: parent.height
                            iconName: "settings"
                            backgroundColor: Theme.surfaceContainerHigh
                            textColor: Theme.surfaceText
                            onClicked: pluginService.showPluginSettings(root.pluginId)
                        }

                        DankButton {
                            id: refreshButton
                            width: 36
                            height: parent.height
                            iconName: "refresh"
                            backgroundColor: Theme.surfaceContainerHigh
                            textColor: root.isLoading ? Theme.surfaceVariantText : Theme.surfaceText
                            onClicked: root.fetchGames()

                            SequentialAnimation on rotation {
                                running: root.isLoading
                                loops: Animation.Infinite
                                NumberAnimation {
                                    from: 0; to: 360
                                    duration: 1000
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.min(500, gamesGrid.contentHeight)
                        color: "transparent"
                        clip: true
                        visible: !root.isLoading && filteredGamesModel.count > 0

                        GridView {
                            id: gamesGrid
                            anchors.fill: parent
                            model: filteredGamesModel
                            cellWidth: parent.width / 4
                            cellHeight: 220
                            boundsBehavior: Flickable.StopAtBounds
                            focus: false // Only gains focus via Tab or navigation
                            
                            highlightFollowsCurrentItem: true
                            keyNavigationEnabled: true
                            
                            Keys.onTabPressed: {
                                if (currentIndex < count - 1) {
                                    currentIndex++;
                                } else {
                                    currentIndex = 0;
                                }
                            }

                            Keys.onBacktabPressed: {
                                if (currentIndex > 0) {
                                    currentIndex--;
                                } else {
                                    searchField.forceActiveFocus();
                                }
                            }
                            
                            Keys.onReturnPressed: launchCurrent()
                            Keys.onEnterPressed: launchCurrent()
                            Keys.onSpacePressed: launchCurrent()
                            
                            function launchCurrent() {
                                var item = model.get(currentIndex);
                                if (item) {
                                    if (item.isVirtual) {
                                        Proc.runCommand("lutris-launcher-open", ["sh", "-c", "nohup /usr/bin/lutris > /dev/null 2>&1 &"], function() {}, 0);
                                    } else {
                                        root.launchGame(item.id, item.slug);
                                    }
                                }
                            }

                            delegate: Item {
                                id: delegateItem
                                width: gamesGrid.cellWidth
                                height: gamesGrid.cellHeight
                                
                                readonly property bool isCurrent: GridView.isCurrentItem

                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - Theme.spacingS
                                    spacing: Theme.spacingXS

                                    Rectangle {
                                        id: coverContainer
                                        width: parent.width
                                        height: 180
                                        color: Theme.surfaceContainer
                                        radius: Theme.roundness === "ROUND_FULL" ? 12 : (Theme.roundness === "ROUND_TWELVE" ? 12 : (Theme.roundness === "ROUND_EIGHT" ? 8 : 4))
                                        clip: true
                                        opacity: (root.isLaunching && model.id !== root.launchingId) ? 0.5 : 1.0
                                        scale: clickAnimation.running ? 0.95 : (delegateItem.isCurrent ? 1.05 : 1.0)
                                        z: delegateItem.isCurrent ? 5 : 1

                                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                                        Behavior on opacity {
                                            NumberAnimation { duration: 300 }
                                        }

                                        SequentialAnimation {
                                            id: clickAnimation
                                            NumberAnimation { target: coverContainer; property: "scale"; to: 0.95; duration: 50 }
                                            NumberAnimation { target: coverContainer; property: "scale"; to: 1.0; duration: 150 }
                                        }

                                        SequentialAnimation {
                                            running: model.id === root.launchingId
                                            loops: Animation.Infinite
                                            NumberAnimation { target: coverContainer; property: "opacity"; from: 1.0; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                            NumberAnimation { target: coverContainer; property: "opacity"; from: 0.8; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                                        }

                                        Image {
                                            id: coverImage
                                            anchors.fill: parent
                                            source: (model.coverPath && !model.isVirtual) ? "file://" + model.coverPath : ""
                                            fillMode: Image.PreserveAspectCrop
                                            visible: model.coverPath && !model.isVirtual
                                        }

                                        // Focus Highlight Border (On top of image)
                                        Rectangle {
                                            anchors.fill: parent
                                            color: "transparent"
                                            border.width: delegateItem.isCurrent ? 3 : 0
                                            border.color: Theme.primary
                                            radius: parent.radius
                                            z: 2
                                            Behavior on border.width { NumberAnimation { duration: 150 } }
                                        }

                                        DankIcon {
                                            anchors.centerIn: parent
                                            name: model.isVirtual ? "add" : "image"
                                            size: 32
                                            color: Theme.surfaceVariantText
                                            visible: !model.coverPath || model.isVirtual
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            cursorShape: (root.isLaunching && !model.isVirtual) ? Qt.ArrowCursor : Qt.PointingHandCursor
                                            enabled: !root.isLaunching || (model.isVirtual && !root.isLaunching)

                                            onClicked: (mouse) => {
                                                if (root.isLaunching) return;
                                                
                                                if (model.isVirtual) {
                                                    if (mouse.button === Qt.LeftButton) {
                                                        clickAnimation.start()
                                                        Proc.runCommand("lutris-launcher-open", ["sh", "-c", "nohup /usr/bin/lutris > /dev/null 2>&1 &"], function() {}, 0)
                                                    }
                                                    return
                                                }

                                                if (mouse.button === Qt.LeftButton) {
                                                    clickAnimation.start()
                                                    root.launchGame(model.id, model.slug)
                                                } else if (mouse.button === Qt.RightButton) {
                                                    infoPanel.visible = true
                                                }
                                            }
                                        }

                                        // Custom Info Panel (Replaces unreliable ToolTip)
                                        Rectangle {
                                            id: infoPanel
                                            anchors.fill: parent
                                            color: Qt.rgba(Theme.surfaceContainerHighest.r, Theme.surfaceContainerHighest.g, Theme.surfaceContainerHighest.b, 0.95)
                                            visible: false
                                            radius: parent.radius
                                            z: 10

                                            // This MouseArea intercepts clicks to prevent launching the game
                                            // while the info panel is open.
                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: infoPanel.visible = false
                                            }

                                            Column {
                                                anchors.centerIn: parent
                                                width: parent.width - Theme.spacingM
                                                spacing: Theme.spacingS

                                                StyledText {
                                                    width: parent.width
                                                    text: root.getFormattedDate(root.playCounts[model.slug]?.lastPlayed)
                                                    font.bold: true
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: Theme.primary
                                                    horizontalAlignment: Text.AlignHCenter
                                                }

                                                StyledText {
                                                    width: parent.width
                                                    text: "Plays: " + (root.playCounts[model.slug]?.count || 0)
                                                    font.pixelSize: 10
                                                    horizontalAlignment: Text.AlignHCenter
                                                }

                                                DankButton {
                                                    width: parent.width - Theme.spacingS
                                                    height: 32
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: model.isBlacklisted ? "Unhide" : "Hide"
                                                    iconName: model.isBlacklisted ? "visibility" : "block"
                                                    backgroundColor: Theme.surfaceContainerHigh
                                                    textColor: model.isBlacklisted ? Theme.primary : Theme.error
                                                    enabled: model.isBlacklisted || !root.isFavorite(model.slug)
                                                    
                                                    // Explicitly handle clicks and prevent propagation
                                                    onClicked: {
                                                        root.toggleBlacklist(model.slug)
                                                        infoPanel.visible = false
                                                    }
                                                    
                                                    // Ensure the button is above the panel's close-MouseArea
                                                    z: 11
                                                }
                                                
                                                StyledText {
                                                    visible: !model.isBlacklisted && root.isFavorite(model.slug)
                                                    text: "Can't hide favorites"
                                                    font.pixelSize: 9
                                                    color: Theme.error
                                                    horizontalAlignment: Text.AlignHCenter
                                                    width: parent.width
                                                }

                                                DankButton {
                                                    width: 40
                                                    height: 24
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: "Close"
                                                    backgroundColor: "transparent"
                                                    textColor: Theme.surfaceVariantText
                                                    onClicked: infoPanel.visible = false
                                                    z: 11
                                                }
                                            }
                                        }

                                        DankButton {
                                            width: 32
                                            height: 32
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.margins: Theme.spacingS
                                            iconName: root.isFavorite(model.slug) ? "star" : "star_border"
                                            backgroundColor: root.isFavorite(model.slug) ? Theme.warning : Theme.surfaceContainerHigh
                                            textColor: root.isFavorite(model.slug) ? Theme.onPrimary : Theme.surfaceVariantText
                                            radius: width / 2
                                            visible: !model.isVirtual
                                            enabled: !root.isLaunching
                                            onClicked: root.toggleFavorite(model.slug)
                                        }
                                    }

                                    StyledText {
                                        width: parent.width
                                        text: model.name || model.slug
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: (root.isLaunching && model.id !== root.launchingId) ? Theme.surfaceVariantText : Theme.surfaceText
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }

                            ScrollIndicator.vertical: ScrollIndicator { }
                        }
                    }

                    StyledText {
                        text: "Loading..."
                        visible: root.isLoading
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        text: root.searchQuery !== "" ? "No games match your search." : "No games found."
                        visible: !root.isLoading && filteredGamesModel.count === 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    popoutWidth: 600
}
