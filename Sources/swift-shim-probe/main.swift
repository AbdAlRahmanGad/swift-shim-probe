// A mise-style shim: one tiny .exe that gets copied to bin\swift.exe, bin\swiftc.exe, ...
//
// It knows nothing about toolchains. It reads its own file name, then runs
//   <manager> run <name> <args...>
// where <manager> is mini-swiftly-demo.exe in the same directory (mise ships
// mise-shim.exe beside mise.exe the same way). Selection (+version, .swift-version,
// inUse), SDKROOT and Path all stay in the manager, so the shim never needs
// to change when that logic does; only a stale shim after a manager update does.
//
// Compare Scoop's shim, which is the other model: a copy of shim.exe plus a
// <name>.shim text file naming a fixed target. That can't follow .swift-version,
// so it doesn't fit here.
//
// Stdlib + WinSDK only, so the file stays small and starts fast.

import WinSDK

let shimVersion = 1

func die(_ message: String) -> Never {
  var bytes = Array("swift-shim: \(message)\n".utf8)
  var written: DWORD = 0
  WriteFile(GetStdHandle(STD_ERROR_HANDLE), &bytes, DWORD(bytes.count), &written, nil)
  exit(1)
}

func utf16(_ buffer: [WCHAR], _ length: Int) -> String {
  String(decoding: buffer.prefix(length), as: UTF16.self)
}

/// Path of this .exe. For a copy or hard link it's the copy's own path, which names the tool.
func ownPath() -> String {
  var buffer = [WCHAR](repeating: 0, count: 32768)
  let length = GetModuleFileNameW(nil, &buffer, DWORD(buffer.count))
  return utf16(buffer, Int(length))
}

func fileExists(_ path: String) -> Bool {
  path.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) != INVALID_FILE_ATTRIBUTES }
}

/// Quotes one argument for the MSVC CRT rules: backslashes only escape when a quote follows.
func quote(_ argument: String) -> String {
  if !argument.isEmpty && !argument.contains(where: { " \t\n\u{0B}\"".contains($0) }) { return argument }
  var out = "\""
  var backslashes = 0
  for character in argument {
    if character == "\\" {
      backslashes += 1
    } else if character == "\"" {
      out += String(repeating: "\\", count: backslashes * 2 + 1) + "\""
      backslashes = 0
    } else {
      out += String(repeating: "\\", count: backslashes) + String(character)
      backslashes = 0
    }
  }
  return out + String(repeating: "\\", count: backslashes * 2) + "\""
}

/// Windows has no exec(): start the manager as a child, wait, return its exit code.
func run(_ executable: String, _ arguments: [String]) -> DWORD {
  // Return TRUE so Ctrl+C doesn't kill the shim; the child got the same event and decides.
  // A handler routine, not SetConsoleCtrlHandler(nil, TRUE), which the child would inherit.
  SetConsoleCtrlHandler({ _ in true }, true)

  // Kill the child (and its children) if the shim is killed.
  let job = CreateJobObjectW(nil, nil)
  if let job {
    var limits = JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
    limits.BasicLimitInformation.LimitFlags = DWORD(JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE)
    _ = SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                                DWORD(MemoryLayout<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>.size))
  }

  var commandLine = Array(([executable] + arguments).map(quote).joined(separator: " ").utf16) + [0]
  var startup = STARTUPINFOW()
  startup.cb = DWORD(MemoryLayout<STARTUPINFOW>.size)
  var info = PROCESS_INFORMATION()
  let created = executable.withCString(encodedAs: UTF16.self) { app in
    CreateProcessW(app, &commandLine, nil, nil, true,
                   DWORD(CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT), nil, nil, &startup, &info)
  }
  guard created else { die("couldn't start \(executable): error \(GetLastError())") }
  if let job { _ = AssignProcessToJobObject(job, info.hProcess) }
  ResumeThread(info.hThread)
  CloseHandle(info.hThread)

  WaitForSingleObject(info.hProcess, INFINITE)
  var code: DWORD = 1
  GetExitCodeProcess(info.hProcess, &code)
  CloseHandle(info.hProcess)
  return code
}

let path = ownPath()
let separator = path.lastIndex(of: "\\")
let directory = separator.map { String(path[..<$0]) } ?? "."
var name = separator.map { String(path[path.index(after: $0)...]) } ?? path
if name.lowercased().hasSuffix(".exe") { name = String(name.dropLast(4)) }

let manager = directory + "\\mini-swiftly-demo.exe"
guard fileExists(manager) else { die("\(name): manager not found at \(manager)") }

// Run the shim as itself (swift-shim-probe.exe --version) to see what it would do.
if name.lowercased() == "swift-shim-probe" {
  print("shim v\(shimVersion): would run \(manager) run <tool> <args>")
  exit(0)
}

exit(Int32(bitPattern: run(manager, ["run", name] + CommandLine.arguments.dropFirst())))
