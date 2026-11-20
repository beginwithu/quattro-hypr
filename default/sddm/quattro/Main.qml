import QtQuick
import SddmComponents 2.0

Rectangle {
  id: root
  width: 640
  height: 480
  color: "#000000"

  property int userIndex: {
    if (userModel.lastUser) {
      for (var i = 0; i < userModel.rowCount(); i++) {
        var u = (userModel.data(userModel.index(i, 0), Qt.UserRole + 1) || "").toString()
        if (u === userModel.lastUser)
          return i
      }
    }
    if (userModel.lastIndex >= 0 && userModel.lastIndex < userModel.rowCount())
      return userModel.lastIndex
    return 0
  }

  property string currentUser: {
    if (userModel.rowCount() > 0 && root.userIndex >= 0 && root.userIndex < userModel.rowCount()) {
      var byRole = (userModel.data(userModel.index(root.userIndex, 0), Qt.UserRole + 1) || "").toString()
      if (byRole)
        return byRole
    }
    return userModel.lastUser || ""
  }

  property bool loginFailed: false
  property int sessionIndex: {
    var uwsmFallback = -1
    for (var i = 0; i < sessionModel.rowCount(); i++) {
      var idx = sessionModel.index(i, 0)
      // SDDM SessionModel roles: FileRole = Qt.UserRole + 2, NameRole = Qt.UserRole + 4
      var file = (sessionModel.data(idx, Qt.UserRole + 2) || "").toString().toLowerCase()
      var name = (sessionModel.data(idx, Qt.UserRole + 4) || "").toString().toLowerCase()
      if (file.indexOf("quattro.desktop") !== -1 || name.indexOf("quattro") !== -1)
        return i
      if (uwsmFallback === -1 && name.indexOf("uwsm") !== -1)
        uwsmFallback = i
    }
    if (uwsmFallback !== -1)
      return uwsmFallback
    return sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 40

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14

      Item {
        width: entry.width
        height: entry.height
        anchors.horizontalCenter: parent.horizontalCenter

        Image {
          source: root.loginFailed ? "lock-failed.png" : "lock.png"
          width: 34
          height: 38
          fillMode: Image.PreserveAspectFit
          anchors.right: parent.left
          anchors.rightMargin: 15
          anchors.verticalCenter: parent.verticalCenter
        }

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(password.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: "JetBrainsMono Nerd Font"
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "\u2022"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          focus: true

          onTextChanged: root.loginFailed = false

          Keys.onPressed: {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              sddm.login(root.currentUser, password.text, root.sessionIndex)
              event.accepted = true
            }
          }
        }
      }

      Text {
        visible: root.currentUser.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.currentUser
        textFormat: Text.PlainText
        color: "#888888"
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 13

        MouseArea {
          anchors.fill: parent
          enabled: userModel.rowCount() > 1
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: {
            root.userIndex = (root.userIndex + 1) % userModel.rowCount()
            password.forceActiveFocus()
          }
        }
      }
    }

  }

  Component.onCompleted: password.forceActiveFocus()
}
