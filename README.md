# swift-shim-probe

The stub is modelled on [mise's shims](https://mise.jdx.dev/dev-tools/shims.html), which on Windows are copies of `mise-shim.exe`. It is one tiny `.exe` that gets copied to `swift.exe`, `swiftc.exe` and so on. It reads its own file name and runs:

```
<manager> run <name> <args...>
```

The manager is `mini-swiftly-demo.exe` in the same folder (the mock swiftly from `../mini-swiftly-demo`). Toolchain selection (`+version`, `.swift-version`, `inUse`), `SDKROOT` and `Path` all stay there, so the stub never has to change when that logic does.

## What the stub does

- Finds its tool name with `GetModuleFileNameW`, not `argv[0]`.
- Starts the manager as a child process and returns its exit code (Windows has no `exec`).
- Returns `TRUE` from a Ctrl+C handler so the stub stays alive while the child decides what to do. It doesn't use `SetConsoleCtrlHandler(NULL, TRUE)`, because the child would inherit that.
- Puts the child in a Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so killing the stub kills the child.
- Quotes arguments with the MSVC rules.
- Prints `manager not found at <path>` and exits 1 if the manager isn't next to it.

It uses only the Swift standard library and `WinSDK`. No Foundation.

## Build

```
swift build --build-system native
```

`--build-system native` is needed on machines with two Swift versions installed, because both register an Android platform and the default build system refuses to start.

## Try it

Set up a folder with the manager and a stub named after a tool (PowerShell):

```powershell
$T = "C:\temp\shimtest"
New-Item -ItemType Directory -Force $T | Out-Null
Copy-Item "$env:LOCALAPPDATA\mini-swiftly-demo\bin\mini-swiftly-demo.exe" $T -Force
Copy-Item .build\debug\swift-shim-probe.exe "$T\swift.exe" -Force
& "$T\swift.exe" --version
```

`& "$T\swift.exe" +6.4 --version` and `mini-swiftly-demo.exe run swift +6.4 --version` should print the same thing, since the stub only adds `run <name>`.

## Tested

- `--version` passes through and the exit code comes back.
- `+6.4` reaches the manager.
- A missing manager gives a clean error.

## Not tested

- Ctrl+C during a long build.
- Killing the stub mid-build (does the compiler die too?).
- Arguments with embedded quotes. PowerShell 5.1 strips them before the stub sees them, so use Git Bash or cmd.
- Size of a release build. The debug build is about 150 KB.
