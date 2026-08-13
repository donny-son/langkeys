import AppKit
import ServiceManagement

/// Registration as a login item, shared by the menu and the settings window.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Could not change the login item"
            alert.runModal()
        }
    }
}
