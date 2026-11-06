/// What each `HostCall` is, in words, and the capability it needs. Kept here,
/// next to the calls, so the kit's error messages and the host's capability
/// check read from one place. The switches have no `default`: a new call
/// doesn't compile until it is described.
extension HostCall {
    /// The call in a few words, for messages such as "<label> failed".
    public var label: String {
        switch self {
        case .storageSet(let key, _): return "saving \(key)"
        case .secret(let name): return "reading secret \(name)"
        case .http(let request): return "\(request.method) \(request.url)"
        case .oauthToken(let provider, _): return "signing in to \(provider)"
        case .publish(let topic, _): return "publishing to \(topic)"
        case .notify: return "notification"
        case .alert: return "alert"
        case .playSound(let sound): return "playing \(sound.rawValue)"
        case .openURL(let url): return "opening \(url)"
        case .open(let url, _): return "opening \(url)"
        case .copy: return "copying"
        case .clipboardRead: return "reading the clipboard"
        case .clipboardWrite: return "writing the clipboard"
        case .paste: return "pasting"
        case .keepAwake(let request): return request == nil ? "letting the Mac sleep" : "keeping the Mac awake"
        case .systemStatus: return "reading system status"
        case .calendarEvents: return "reading calendar events"
        case .run(let request): return "running \(request.command)"
        case .cancelRun: return "stopping a run"
        case .context: return "reading the selection"
        case .finderSelection: return "reading Finder's selection"
        case .chooseFile: return "choosing a file"
        case .saveFile(let name, _): return "saving \(name)"
        case .resolveApplication(let name): return "finding the app \(name)"
        case .windows: return "reading windows"
        case .arrangeWindows: return "arranging windows"
        case .runningApps: return "reading running apps"
        case .activateApp(let id, _): return "switching to \(id)"
        case .hideApp(let id): return "hiding \(id)"
        case .setKeyLayer(let layer): return layer == nil ? "removing the key layer" : "setting the key layer"
        case .keyLayerStatus: return "reading the key layer's status"
        case .reminderAccess: return "checking Reminders access"
        case .reminderLists: return "reading Reminders lists"
        case .createReminderList(let title, _): return "making the list \(title)"
        case .reminders: return "reading reminders"
        case .saveReminder(let reminder, _): return reminder.id.isEmpty ? "adding a reminder" : "saving a reminder"
        case .deleteReminder: return "deleting a reminder"
        case .installedApps: return "listing installed apps"
        case .findFiles: return "finding files"
        case .hud: return "showing a message"
        case .system(let action): return action.title.lowercased()
        case .setExpansions(let expansions): return expansions.isEmpty ? "removing keywords" : "registering \(expansions.count) keywords"
        case .expansionStatus: return "reading the keywords' status"
        case .focusWindow(let target): return "switching to a window of \(target.appID)"
        case .menuItems: return "reading the menu bar"
        case .pressMenuItem(_, let path): return "choosing \(path.joined(separator: " > "))"
        case .pickColor: return "picking a color from the screen"
        case .define(let word): return "looking up \(word.prefix(40))"
        case .saveCalendarEvent(let draft): return draft.id.isEmpty ? "adding \"\(draft.title)\" to a calendar" : "changing \"\(draft.title)\""
        case .writableCalendars: return "listing the calendars it can add to"
        case .openInTerminal(let command, _): return "opening \(command.first ?? "a command") in the terminal"
        case .recognizeText: return "reading the text in an image"
        case .captureScreenText: return "reading text on the screen"
        case .sensors: return "reading temperatures and fans"
        }
    }

    /// The capability the call needs whatever its arguments, and what it is
    /// for ("read the clipboard"), which completes "to …" in the refusal.
    /// `nil` when it needs none, or when what it needs depends on the
    /// manifest's details (a declared domain, secret, provider or command),
    /// which the host checks itself.
    public var requirement: (capability: Capability, purpose: String)? {
        switch self {
        case .clipboardRead: return (.clipboard, "read the clipboard")
        case .clipboardWrite, .paste: return (.clipboard, "write or paste clipboard content")
        // Releasing never needs the capability, so a revoked plugin can let go.
        case .keepAwake(let request): return request == nil ? nil : (.power, "keep the Mac awake")
        case .systemStatus: return (.power, "read battery and running apps")
        case .calendarEvents: return (.calendar, "read calendar events")
        case .context: return (.context, "read the selected text and frontmost app")
        case .finderSelection: return (.context, "read Finder's selection")
        case .windows: return (.windows, "read your windows")
        case .arrangeWindows: return (.windows, "move and resize windows")
        case .runningApps: return (.apps, "read running apps")
        case .activateApp, .hideApp: return (.apps, "switch, open or hide apps")
        case .installedApps: return (.apps, "list installed apps")
        case .findFiles: return (.fileSearch, "find files by name")
        case .system: return (.systemActions, "lock, sleep or restart the Mac and empty the Trash")
        // Removing never needs the capability, so a revoked plugin can let go.
        case .setKeyLayer(let layer): return layer == nil ? nil : (.keyLayer, "switch apps from a held key")
        case .keyLayerStatus: return (.keyLayer, "read the key layer's status")
        case .setExpansions(let expansions): return expansions.isEmpty ? nil : (.textExpansion, "expand keywords as you type")
        case .expansionStatus: return (.textExpansion, "read the keywords' status")
        case .focusWindow: return (.windows, "switch to a window")
        case .menuItems: return (.menus, "read the front app's menus")
        case .pressMenuItem: return (.menus, "choose a menu item")
        case .saveCalendarEvent: return (.calendarWrite, "add calendar events")
        case .writableCalendars: return (.calendarWrite, "list your calendars")
        case .openInTerminal: return (.terminal, "open a command in the terminal")
        case .recognizeText: return (.clipboard, "read text in a clipboard image")
        case .captureScreenText: return (.screenText, "read text on the screen")
        case .sensors: return (.sensors, "read temperatures and fans")
        case .reminderAccess, .reminderLists, .reminders: return (.reminders, "read your reminders")
        case .createReminderList, .saveReminder, .deleteReminder: return (.reminders, "change your reminders")
        case .storageSet, .secret, .http, .oauthToken, .publish, .notify, .alert, .playSound,
             .openURL, .open, .copy, .run, .cancelRun, .chooseFile, .saveFile, .resolveApplication, .hud,
             .pickColor, .define:
            return nil
        }
    }
}
