import Foundation
import Security

enum ProviderResult {
    case success(String)
    case needsLogin
    case notInstalled
    case failure(String)
}

protocol AIProvider {
    var id: String { get }
    var displayName: String { get }
    var executablePath: String? { get }
    var installCommand: String { get }
    var loginCommand: String { get }
    var isSignedIn: Bool { get }

    func translate(text: String, sourceName: String?, targetName: String, directives: String,
                   onDelta: @escaping (String) -> Void,
                   onDone: @escaping (ProviderResult) -> Void)

    func ask(prompt: String, system: String, imagePath: String?,
             onDelta: @escaping (String) -> Void,
             onDone: @escaping (ProviderResult) -> Void)
}

extension AIProvider {
    var isInstalled: Bool { executablePath != nil }

    // Install page embedded in installCommand, if any ("See https://…").
    var installURL: URL? {
        guard let range = installCommand.range(of: "https://") else { return nil }
        return URL(string: String(installCommand[range.lowerBound...]))
    }

    func userPrompt(text: String, sourceName: String?, targetName: String, directives: String) -> String {
        var directive = "Translate the text between <<< and >>> into \(targetName)."
        if let source = sourceName {
            directive = "The source language is \(source). " + directive
        }
        if !directives.isEmpty { directive += " \(directives)" }
        return "\(directive) Output only the translation.\n<<<\n\(text)\n>>>"
    }
}

// Three-tier resolution: persisted cache → known-dir scan (covers version
// managers like nvm/volta/pnpm/asdf) → the user's login shell (`command -v`,
// same PATH the terminal has). The shell hop is slow, so its result persists
// and AppDelegate warms the cache off-thread at launch.
func findExecutable(_ names: [String]) -> String? {
    let fm = FileManager.default
    let defaults = UserDefaults.standard
    for name in names {
        if let cached = defaults.string(forKey: "cli.path.\(name)"),
           fm.isExecutableFile(atPath: cached) { return cached }
    }

    let home = NSHomeDirectory()
    var dirs = ["/opt/homebrew/bin", "/usr/local/bin",
                "\(home)/.claude/local", "\(home)/.local/bin",
                "\(home)/.npm-global/bin", "\(home)/.bun/bin",
                "\(home)/.volta/bin", "\(home)/Library/pnpm",
                "\(home)/.asdf/shims", "\(home)/.local/share/mise/shims",
                "/opt/local/bin", "/usr/bin"]
    if let nodeVersions = try? fm.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
        dirs += nodeVersions.sorted(by: >).map { "\(home)/.nvm/versions/node/\($0)/bin" }
    }
    for name in names {
        for dir in dirs {
            let path = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: path) {
                defaults.set(path, forKey: "cli.path.\(name)")
                return path
            }
        }
    }

    for name in names {
        if let path = shellResolve(name) {
            defaults.set(path, forKey: "cli.path.\(name)")
            return path
        }
    }
    return nil
}

private func shellResolve(_ name: String) -> String? {
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let task = Process()
    task.executableURL = URL(fileURLWithPath: shell)
    task.arguments = ["-l", "-i", "-c", "command -v \(name)"]
    task.standardInput = FileHandle.nullDevice
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return nil }
    // Interactive rc files can block (prompts, slow plugins) — cap the wait.
    DispatchQueue.global().asyncAfter(deadline: .now() + 4) { [weak task] in
        if let task, task.isRunning { task.terminate() }
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard let out = String(data: data, encoding: .utf8) else { return nil }
    // rc noise is possible — take the last line that is the binary's path.
    for line in out.split(separator: "\n").reversed() {
        let path = line.trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("/"), path.hasSuffix("/\(name)"),
           FileManager.default.isExecutableFile(atPath: path) { return path }
    }
    return nil
}

// One live child process per kind ("translate"/"ask"/"document"). Starting a new
// one kills its predecessor, and a watchdog kills anything that outlives its
// timeout — so `busy` can never hang forever on a wedged CLI.
enum AITask {
    private static let lock = NSLock()
    private static var current: [String: Process] = [:]

    static func begin(_ kind: String, _ task: Process, timeout: TimeInterval = 120) {
        lock.lock()
        current[kind]?.terminate()
        current[kind] = task
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak task] in
            guard let task, task.isRunning else { return }
            task.terminate()
            // Wrappers/Node CLIs sometimes ignore SIGTERM — escalate so a
            // wedged process can never outlive its slot.
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak task] in
                if let task, task.isRunning { kill(task.processIdentifier, SIGKILL) }
            }
        }
    }

    static func end(_ kind: String, _ task: Process) {
        lock.lock()
        if current[kind] === task { current[kind] = nil }
        lock.unlock()
    }

    static func cancel(_ kind: String) {
        lock.lock()
        let task = current.removeValue(forKey: kind)
        lock.unlock()
        task?.terminate()
    }
}

// Drains a pipe on its own queue so the child can never block on a full stderr
// buffer while we read stdout (the classic two-pipe deadlock).
final class PipeDrain {
    private let lock = NSLock()
    private var data = Data()
    let handle: FileHandle

    init(_ pipe: Pipe) {
        handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self else { return }
            if chunk.isEmpty { h.readabilityHandler = nil }
            else { self.lock.lock(); self.data.append(chunk); self.lock.unlock() }
        }
    }

    func finish() -> String {
        handle.readabilityHandler = nil
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

func cliEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["LANG"] = "en_US.UTF-8"
    env["LC_ALL"] = "en_US.UTF-8"
    env["MAX_THINKING_TOKENS"] = "0"
    // GUI apps inherit a bare PATH (/usr/bin:/bin); CLIs installed via
    // homebrew/npm/bun need their dirs for `#!/usr/bin/env node` shebangs
    // and internal tool lookups to resolve.
    let home = NSHomeDirectory()
    let extra = ["/opt/homebrew/bin", "/usr/local/bin",
                 "\(home)/.local/bin", "\(home)/.bun/bin", "\(home)/.npm-global/bin"]
    env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
    return env
}

func runClaudeStream(path: String, args: [String], kind: String = "translate",
                     onDelta: @escaping (String) -> Void,
                     onDone: @escaping (ProviderResult) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        task.arguments = args
        task.environment = cliEnvironment()
        let pipe = Pipe(), errPipe = Pipe()
        task.standardOutput = pipe
        task.standardError = errPipe
        task.standardInput = FileHandle.nullDevice   // claude -p reads stdin; a GUI app's inherited stdin never EOFs → it waits forever
        do { try task.run() } catch { DispatchQueue.main.async { onDone(.failure("Could not launch claude")) }; return }
        AITask.begin(kind, task, timeout: kind == "translate" ? 60 : 120)
        let stderrDrain = PipeDrain(errPipe)

        // Parse stdout on the pipe's callback queue — never a blocking read.
        // The old `availableData` loop could hang forever when a killed CLI
        // left a grandchild holding the pipe open; now finalization runs as
        // soon as the task itself exits, no matter what the pipe does.
        let state = NSLock()
        var buffer = Data(), full = "", needsLogin = false, rateLimited = false
        func consume(_ data: Data) {   // caller holds `state`
            if let line = String(data: data, encoding: .utf8) {
                if line.contains("authentication_failed") || line.contains("Not logged in") { needsLogin = true }
                if line.contains("rate_limit") || line.contains("overloaded_error") { rateLimited = true }
            }
            guard !data.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "stream_event",
                  let event = obj["event"] as? [String: Any],
                  (event["type"] as? String) == "content_block_delta",
                  let delta = event["delta"] as? [String: Any],
                  (delta["type"] as? String) == "text_delta",
                  let piece = delta["text"] as? String else { return }
            full += piece
            DispatchQueue.main.async { onDelta(piece) }
        }
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            state.lock()
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                consume(buffer.subdata(in: buffer.startIndex..<nl))
                buffer.removeSubrange(buffer.startIndex...nl)
            }
            state.unlock()
        }
        task.waitUntilExit()
        AITask.end(kind, task)
        usleep(200_000)   // let the last buffered output arrive
        reader.readabilityHandler = nil
        let stderr = stderrDrain.finish()
        state.lock()
        if !buffer.isEmpty { consume(buffer); buffer.removeAll() }
        var loginNeeded = needsLogin
        let limited = rateLimited || stderr.contains("rate_limit") || stderr.contains("overloaded")
        let result = full.trimmingCharacters(in: .whitespacesAndNewlines)
        state.unlock()
        if stderr.contains("authentication_failed") || stderr.contains("Not logged in")
            || stderr.lowercased().contains("please run /login") { loginNeeded = true }
        let login = loginNeeded
        let killed = task.terminationReason == .uncaughtSignal
        DispatchQueue.main.async {
            if killed { onDone(.failure("Translation stopped (cancelled or timed out).")) }
            else if !result.isEmpty { onDone(.success(result)) }
            else if login { onDone(.needsLogin) }
            else if limited { onDone(.failure("Claude is rate-limited or overloaded right now — wait a moment and try again.")) }
            else { onDone(.failure("No response")) }
        }
    }
}

struct ClaudeProvider: AIProvider {
    let id = "claude"
    let displayName = "Claude"
    var executablePath: String? { findExecutable(["claude"]) }
    let installCommand = "See https://claude.com/claude-code"
    var loginCommand: String { "\(executablePath ?? "claude")" }

    // Claude Code stores credentials as a Keychain generic password (service
    // "Claude Code-credentials"). An attributes-only probe proves the item
    // exists without reading the secret, so macOS shows no permission prompt.
    var isSignedIn: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess { return true }
        // Older/Linux-style installs keep a credentials file instead.
        return FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.claude/.credentials.json")
    }

    func translate(text: String, sourceName: String?, targetName: String, directives: String,
                   onDelta: @escaping (String) -> Void,
                   onDone: @escaping (ProviderResult) -> Void) {
        guard let path = executablePath else { onDone(.notInstalled); return }
        let user = userPrompt(text: text, sourceName: sourceName, targetName: targetName, directives: directives)
        let args = ["-p", user, "--model", "haiku", "--tools", "",
                    "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence",
                    "--system-prompt", Prefs.systemPrompt,
                    "--output-format", "stream-json", "--include-partial-messages", "--verbose"]
        runClaudeStream(path: path, args: args, onDelta: onDelta, onDone: onDone)
    }

    func ask(prompt: String, system: String, imagePath: String?,
             onDelta: @escaping (String) -> Void,
             onDone: @escaping (ProviderResult) -> Void) {
        guard let path = executablePath else { onDone(.notInstalled); return }
        // With an image, the model views it via the Read tool (the only tool
        // allowed); text-only asks keep every tool disabled.
        let tools = imagePath == nil ? ["--tools", ""] : ["--allowedTools", "Read"]
        let args = ["-p", prompt, "--model", "sonnet"] + tools
                 + ["--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence",
                    "--system-prompt", system,
                    "--output-format", "stream-json", "--include-partial-messages", "--verbose"]
        runClaudeStream(path: path, args: args, kind: "ask", onDelta: onDelta, onDone: onDone)
    }
}

struct CodexProvider: AIProvider {
    let id = "codex"
    let displayName = "GPT (Codex)"
    var executablePath: String? { findExecutable(["codex"]) }
    let installCommand = "npm install -g @openai/codex"
    var loginCommand: String { "\(executablePath ?? "codex") login" }
    var isSignedIn: Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.codex/auth.json")
    }

    func translate(text: String, sourceName: String?, targetName: String, directives: String,
                   onDelta: @escaping (String) -> Void,
                   onDone: @escaping (ProviderResult) -> Void) {
        guard let path = executablePath else { onDone(.notInstalled); return }
        let prompt = Prefs.systemPrompt + "\n\n"
            + userPrompt(text: text, sourceName: sourceName, targetName: targetName, directives: directives)

        runCodex(path: path, prompt: prompt, kind: "translate", onDone: onDone)
    }

    func ask(prompt: String, system: String, imagePath: String?,
             onDelta: @escaping (String) -> Void,
             onDone: @escaping (ProviderResult) -> Void) {
        guard let path = executablePath else { onDone(.notInstalled); return }
        // Codex can read workspace files in its sandbox; the image path is in
        // the prompt (image asks are normally routed to Claude anyway).
        runCodex(path: path, prompt: system + "\n\n" + prompt, kind: "ask", onDone: onDone)
    }

    private func runCodex(path: String, prompt: String, kind: String,
                          onDone: @escaping (ProviderResult) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            task.arguments = ["exec", "--skip-git-repo-check", prompt]
            task.environment = cliEnvironment()
            let pipe = Pipe(), errPipe = Pipe()
            task.standardOutput = pipe
            task.standardError = errPipe
            task.standardInput = FileHandle.nullDevice   // same stdin-wait trap as claude
            do { try task.run() } catch { DispatchQueue.main.async { onDone(.failure("Could not launch codex")) }; return }
            AITask.begin(kind, task, timeout: kind == "translate" ? 60 : 120)
            // Drain both pipes off-thread — a blocking read here could hang
            // forever if a killed codex left a child holding the pipe open.
            let outDrain = PipeDrain(pipe)
            let stderrDrain = PipeDrain(errPipe)
            task.waitUntilExit()
            AITask.end(kind, task)
            usleep(200_000)
            let out = outDrain.finish()
            let err = stderrDrain.finish()
            let combined = (out + "\n" + err).lowercased()
            let result = out.trimmingCharacters(in: .whitespacesAndNewlines)
            let killed = task.terminationReason == .uncaughtSignal
            // Login markers only count when there is no usable result — otherwise a
            // translation that merely *contains* "login" would be thrown away.
            let needsLogin = result.isEmpty && (combined.contains("not logged in")
                || combined.contains("please run") || combined.contains("login"))
            DispatchQueue.main.async {
                if killed { onDone(.failure("Translation stopped (cancelled or timed out).")) }
                else if needsLogin { onDone(.needsLogin) }
                else if result.isEmpty { onDone(.failure("No response from codex")) }
                else { onDone(.success(result)) }
            }
        }
    }
}

enum Providers {
    static let all: [AIProvider] = [ClaudeProvider(), CodexProvider()]
    static func provider(id: String) -> AIProvider { all.first { $0.id == id } ?? ClaudeProvider() }

    // Directory-scan CLI detection off the main thread (Setup and the guide both use it).
    static func detectInstalled(_ completion: @escaping ([String: Bool]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var map: [String: Bool] = [:]
            for provider in all { map[provider.id] = provider.isInstalled }
            DispatchQueue.main.async { completion(map) }
        }
    }
}
