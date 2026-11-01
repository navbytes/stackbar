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
        case .storageSet, .secret, .http, .oauthToken, .publish, .notify, .alert, .playSound,
             .openURL, .open, .copy, .run, .cancelRun, .chooseFile, .saveFile, .resolveApplication:
            return nil
        }
    }
}
