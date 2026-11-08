# Tasks

## 1. Core (StackbarHostCore)
- [x] 1.1 `HelperRecord` / `HelperIndex`: signed records, `helpers.json` beside the index, best match
- [x] 1.2 `PrebuiltHelpers`: lookup and save under `Prebuilt/`, download and verify
- [x] 1.3 `PluginBuilder`: prebuilt lookup, toolchain check without the swift shim, clear no-toolchain failure
- [x] 1.4 Tests (Linux and the CryptoKit-only signing tests)

## 2. stackbarctl
- [x] 2.1 `helper kit`, `helper build`, `helper prebuild`
- [x] 2.2 `doctor`: toolchain only needed to write plugins

## 3. App
- [x] 3.1 Store install and update fetch the helper first; wait when none is usable
- [x] 3.2 Store check fetches helpers for installed plugins and reloads failed ones
- [x] 3.3 `bundle.sh` prebuilds the carried bundles and examples and signs them

## 4. Docs
- [x] 4.1 README, download page, installer, cask caveats, AuthoringGuide/llms.txt where they mention the toolchain

## 5. stackbar-plugins
- [x] 5.1 `scripts/helpers.sh` and the Helpers workflow
- [x] 5.2 Raise the Stackbar pin to the release with `stackbarctl helper`
- [x] 5.3 Each Stackbar release starts the Helpers workflow (`PLUGINS_DISPATCH_TOKEN`), since its hourly schedule is unreliable

## 6. On a Mac
- [x] 6.1 A Mac without the Command Line Tools installs and runs a store plugin (verified with 0.20.0 on the no-toolchain macOS runner (No toolchain workflow, #97))
