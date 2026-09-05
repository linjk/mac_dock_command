# BarCmd Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出可运行的 BarCmd：菜单栏管理长期 shell 命令，启停、日志、端口、YAML 双向同步。

**Architecture:** `@MainActor` `AppModel` 编排；View 只谈 AppModel。进程在独立进程组里用 login shell 跑；日志剥 ANSI 后进环形缓冲；端口 = 日志正则 + 进程组 `lsof`。配置原子写 + 哈希，避免自己写自己重载。

**Tech Stack:** Swift 5.9+ / SwiftUI `MenuBarExtra` / macOS 14 / Yams / XCTest

## Global Constraints

- 显示名 `BarCmd`；Bundle ID `com.dorian.barcmd`；最低 macOS 14.0
- 只允许第三方依赖 Yams；禁止 App Sandbox
- Agent App：`LSUIElement = true`，无 Dock 图标；菜单栏图标必须是 template，禁止 SF Symbol
- 用户可见文案中文；标识符、文件名英文
- 退出前停止全部 running/starting 命令；运行中不可直接编辑/删除
- 规格：`docs/superpowers/specs/2026-08-30-mac-menu-bar-command-runner-design.md`
- 架构：`docs/superpowers/specs/2026-09-01-barcmd-architecture.md`（与规格伪代码冲突时以架构为准）
- 提交信息中文，前缀 `feat:` / `fix:` / `test:` / `chore:` / `docs:`

## File Structure

```
BarCmd/BarCmd.xcodeproj
BarCmd/BarCmd/App/BarCmdApp.swift
BarCmd/BarCmd/App/AppDelegate.swift
BarCmd/BarCmd/App/AppModel.swift
BarCmd/BarCmd/App/UserPrompter.swift
BarCmd/BarCmd/Models/CommandConfig.swift
BarCmd/BarCmd/Models/CommandRuntime.swift
BarCmd/BarCmd/Models/CommandStatus.swift
BarCmd/BarCmd/Models/PathExpand.swift
BarCmd/BarCmd/Services/ProcessControlling.swift
BarCmd/BarCmd/Services/ProcessSpawner.swift
BarCmd/BarCmd/Services/ProcessTree.swift
BarCmd/BarCmd/Services/ProcessManager.swift
BarCmd/BarCmd/Services/LogBuffer.swift
BarCmd/BarCmd/Services/ANSIStripper.swift
BarCmd/BarCmd/Services/PortDetector.swift
BarCmd/BarCmd/Services/LsofClient.swift
BarCmd/BarCmd/Services/ConfigStore.swift
BarCmd/BarCmd/Views/MenuBarView.swift
BarCmd/BarCmd/Views/CommandRowView.swift
BarCmd/BarCmd/Views/CommandEditSheet.swift
BarCmd/BarCmd/Views/LogWindowView.swift
BarCmd/BarCmd/Resources/Info.plist
BarCmd/BarCmd/Resources/BarCmd.entitlements
BarCmd/BarCmd/Assets.xcassets/
BarCmd/BarCmdTests/*.swift
```

`BarCmd` 是 application target（`ENABLE_TESTABILITY = YES`）。测试 `@testable import BarCmd`。不要另起 Core 库。

---

### Task 1: Xcode 工程、身份、图标

**Files:**
- Create: `BarCmd/BarCmd.xcodeproj/project.pbxproj`
- Create: `BarCmd/BarCmd.xcodeproj/xcshareddata/xcschemes/BarCmd.xcscheme`
- Create: `BarCmd/BarCmd/App/BarCmdApp.swift`
- Create: `BarCmd/BarCmd/Resources/Info.plist`
- Create: `BarCmd/BarCmd/Resources/BarCmd.entitlements`
- Create: `BarCmd/BarCmd/Assets.xcassets/Contents.json`
- Create: `BarCmd/BarCmd/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `BarCmd/BarCmd/Assets.xcassets/MenuBarIcon.imageset/Contents.json`
- Create: `BarCmd/BarCmdTests/BarCmdTests.swift`

**Interfaces:**
- Consumes: 图标源 `docs/superpowers/specs/icons/barcmd-icon-c-brackets.png`、`barcmd-menubar-template.svg`
- Produces: 可 `xcodebuild` 编译的 `BarCmd` scheme；`MenuBarExtra` 占位；Bundle ID `com.dorian.barcmd`

- [ ] **Step 1: 建目录并拷图标**

```bash
mkdir -p BarCmd/BarCmd/App BarCmd/BarCmd/Models BarCmd/BarCmd/Services BarCmd/BarCmd/Views BarCmd/BarCmd/Resources
mkdir -p BarCmd/BarCmd/Assets.xcassets/AppIcon.appiconset BarCmd/BarCmd/Assets.xcassets/MenuBarIcon.imageset
mkdir -p BarCmd/BarCmd.xcodeproj/xcshareddata/xcschemes BarCmd/BarCmdTests
cp docs/superpowers/specs/icons/barcmd-icon-c-brackets.png BarCmd/BarCmd/Assets.xcassets/AppIcon.appiconset/AppIcon.png
cp docs/superpowers/specs/icons/barcmd-menubar-template.svg BarCmd/BarCmd/Assets.xcassets/MenuBarIcon.imageset/barcmd-menubar-template.svg
```

- [ ] **Step 2: 写资源与占位源码**

`BarCmd/BarCmd/Assets.xcassets/Contents.json`:

```json
{ "info": { "author": "xcode", "version": 1 } }
```

`BarCmd/BarCmd/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images": [
    { "filename": "AppIcon.png", "idiom": "mac", "scale": "1x", "size": "1024x1024" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

`BarCmd/BarCmd/Assets.xcassets/MenuBarIcon.imageset/Contents.json`:

```json
{
  "images": [
    { "filename": "barcmd-menubar-template.svg", "idiom": "universal" }
  ],
  "info": { "author": "xcode", "version": 1 },
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template"
  }
}
```

`BarCmd/BarCmd/Resources/BarCmd.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

`BarCmd/BarCmd/Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
  <key>CFBundleDisplayName</key><string>BarCmd</string>
  <key>CFBundleExecutable</key><string>$(EXECUTABLE_NAME)</string>
  <key>CFBundleIdentifier</key><string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
  <key>CFBundleName</key><string>BarCmd</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

`BarCmd/BarCmd/App/BarCmdApp.swift`:

```swift
import SwiftUI

@main
struct BarCmdApp: App {
    var body: some Scene {
        MenuBarExtra {
            Text("BarCmd")
                .padding()
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}
```

`BarCmd/BarCmdTests/BarCmdTests.swift`:

```swift
import XCTest
@testable import BarCmd

final class BarCmdTests: XCTestCase {
    func testModuleImports() {
        XCTAssertEqual(CommandStatus.stopped.rawValue, "stopped")
    }
}
```

这一步 `CommandStatus` 还不存在，先把测试写成：

```swift
import XCTest
@testable import BarCmd

final class BarCmdTests: XCTestCase {
    func testBundleName() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "BarCmd")
    }
}
```

测试跑在 xctest bundle 里，`Bundle.main` 不是 App。改成：

```swift
func testAppModuleLoads() {
    XCTAssertTrue(true)
}
```

占位即可，真正断言从 Task 2 开始。

- [ ] **Step 3: 写 `project.pbxproj` 与 shared scheme**

把下面整份写入 `BarCmd/BarCmd.xcodeproj/project.pbxproj`（Xcode 16 synchronized group，后续任务加文件不必再改工程文件）。`Info.plist` 用例外排除出 Compile Sources。

工程根目录是 `BarCmd/`，所以 `INFOPLIST_FILE` = `BarCmd/Resources/Info.plist`。

`BarCmd/BarCmd.xcodeproj/project.pbxproj` 全文：

```
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXBuildFile section */
		A10000000000000000000020 /* Yams in Frameworks */ = {isa = PBXBuildFile; productRef = A10000000000000000000021 /* Yams */; };
		A10000000000000000000022 /* Yams in Frameworks */ = {isa = PBXBuildFile; productRef = A10000000000000000000023 /* Yams */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		A10000000000000000000030 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = A10000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = A10000000000000000000002;
			remoteInfo = BarCmd;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		A10000000000000000000010 /* BarCmd.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = BarCmd.app; sourceTree = BUILT_PRODUCTS_DIR; };
		A10000000000000000000011 /* BarCmdTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = BarCmdTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		A10000000000000000000040 /* Exceptions for BarCmd folder in BarCmd target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Resources/Info.plist,
			);
			target = A10000000000000000000002 /* BarCmd */;
		};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		A10000000000000000000050 /* BarCmd */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				A10000000000000000000040 /* Exceptions for BarCmd folder in BarCmd target */,
			);
			path = BarCmd;
			sourceTree = "<group>";
		};
		A10000000000000000000051 /* BarCmdTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = BarCmdTests;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		A10000000000000000000060 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A10000000000000000000020 /* Yams in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10000000000000000000061 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A10000000000000000000022 /* Yams in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		A10000000000000000000070 = {
			isa = PBXGroup;
			children = (
				A10000000000000000000050 /* BarCmd */,
				A10000000000000000000051 /* BarCmdTests */,
				A10000000000000000000071 /* Products */,
			);
			sourceTree = "<group>";
		};
		A10000000000000000000071 /* Products */ = {
			isa = PBXGroup;
			children = (
				A10000000000000000000010 /* BarCmd.app */,
				A10000000000000000000011 /* BarCmdTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		A10000000000000000000002 /* BarCmd */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A10000000000000000000080 /* Build configuration list for PBXNativeTarget "BarCmd" */;
			buildPhases = (
				A10000000000000000000090 /* Sources */,
				A10000000000000000000060 /* Frameworks */,
				A10000000000000000000091 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				A10000000000000000000050 /* BarCmd */,
			);
			name = BarCmd;
			packageProductDependencies = (
				A10000000000000000000021 /* Yams */,
			);
			productName = BarCmd;
			productReference = A10000000000000000000010 /* BarCmd.app */;
			productType = "com.apple.product-type.application";
		};
		A10000000000000000000003 /* BarCmdTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A10000000000000000000081 /* Build configuration list for PBXNativeTarget "BarCmdTests" */;
			buildPhases = (
				A10000000000000000000092 /* Sources */,
				A10000000000000000000061 /* Frameworks */,
				A10000000000000000000093 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				A10000000000000000000031 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				A10000000000000000000051 /* BarCmdTests */,
			);
			name = BarCmdTests;
			packageProductDependencies = (
				A10000000000000000000023 /* Yams */,
			);
			productName = BarCmdTests;
			productReference = A10000000000000000000011 /* BarCmdTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		A10000000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {
					A10000000000000000000002 = {
						CreatedOnToolsVersion = 16.0;
					};
					A10000000000000000000003 = {
						CreatedOnToolsVersion = 16.0;
						TestTargetID = A10000000000000000000002;
					};
				};
			};
			buildConfigurationList = A10000000000000000000082 /* Build configuration list for PBXProject "BarCmd" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				"zh-Hans",
			);
			mainGroup = A10000000000000000000070;
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				A10000000000000000000024 /* XCRemoteSwiftPackageReference "Yams" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = A10000000000000000000071 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				A10000000000000000000002 /* BarCmd */,
				A10000000000000000000003 /* BarCmdTests */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		A10000000000000000000091 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10000000000000000000093 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		A10000000000000000000090 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10000000000000000000092 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		A10000000000000000000031 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = A10000000000000000000002 /* BarCmd */;
			targetProxy = A10000000000000000000030 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		A100000000000000000000A0 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		A100000000000000000000A1 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
		A100000000000000000000A2 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				AD_HOC_CODE_SIGNING_ALLOWED = YES;
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = BarCmd/Resources/BarCmd.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGNING_REQUIRED = NO;
				COMBINE_HIDPI_IMAGES = YES;
				ENABLE_TESTABILITY = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = BarCmd/Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
				PRODUCT_BUNDLE_IDENTIFIER = com.dorian.barcmd;
				PRODUCT_NAME = BarCmd;
				SWIFT_EMIT_LOC_STRINGS = YES;
			};
			name = Debug;
		};
		A100000000000000000000A3 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				AD_HOC_CODE_SIGNING_ALLOWED = YES;
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = BarCmd/Resources/BarCmd.entitlements;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGNING_REQUIRED = NO;
				COMBINE_HIDPI_IMAGES = YES;
				ENABLE_TESTABILITY = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = BarCmd/Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
				PRODUCT_BUNDLE_IDENTIFIER = com.dorian.barcmd;
				PRODUCT_NAME = BarCmd;
				SWIFT_EMIT_LOC_STRINGS = YES;
			};
			name = Release;
		};
		A100000000000000000000A4 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGNING_REQUIRED = NO;
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = com.dorian.barcmd.tests;
				PRODUCT_NAME = BarCmdTests;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/BarCmd.app/Contents/MacOS/BarCmd";
			};
			name = Debug;
		};
		A100000000000000000000A5 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGNING_REQUIRED = NO;
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = com.dorian.barcmd.tests;
				PRODUCT_NAME = BarCmdTests;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/BarCmd.app/Contents/MacOS/BarCmd";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		A10000000000000000000080 /* Build configuration list for PBXNativeTarget "BarCmd" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A100000000000000000000A2 /* Debug */,
				A100000000000000000000A3 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		A10000000000000000000081 /* Build configuration list for PBXNativeTarget "BarCmdTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A100000000000000000000A4 /* Debug */,
				A100000000000000000000A5 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		A10000000000000000000082 /* Build configuration list for PBXProject "BarCmd" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A100000000000000000000A0 /* Debug */,
				A100000000000000000000A1 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

/* Begin XCRemoteSwiftPackageReference section */
		A10000000000000000000024 /* XCRemoteSwiftPackageReference "Yams" */ = {
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/jpsim/Yams.git";
			requirement = {
				kind = upToNextMajorVersion;
				minimumVersion = 5.1.0;
			};
		};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		A10000000000000000000021 /* Yams */ = {
			isa = XCSwiftPackageProductDependency;
			package = A10000000000000000000024 /* XCRemoteSwiftPackageReference "Yams" */;
			productName = Yams;
		};
		A10000000000000000000023 /* Yams */ = {
			isa = XCSwiftPackageProductDependency;
			package = A10000000000000000000024 /* XCRemoteSwiftPackageReference "Yams" */;
			productName = Yams;
		};
/* End XCSwiftPackageProductDependency section */
	};
	rootObject = A10000000000000000000001 /* Project object */;
}
```

`BarCmd/BarCmd.xcodeproj/xcshareddata/xcschemes/BarCmd.xcscheme` 全文：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000002" BuildableName="BarCmd.app" BlueprintName="BarCmd" ReferencedContainer="container:BarCmd.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables>
         <TestableReference skipped="NO">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000003" BuildableName="BarCmdTests.xctest" BlueprintName="BarCmdTests" ReferencedContainer="container:BarCmd.xcodeproj"/>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000002" BuildableName="BarCmd.app" BlueprintName="BarCmd" ReferencedContainer="container:BarCmd.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000002" BuildableName="BarCmd.app" BlueprintName="BarCmd" ReferencedContainer="container:BarCmd.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
```

- [ ] **Step 4: 编译**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' build
```

Expected: `** BUILD SUCCEEDED **`。菜单栏出现 template `[▶]`，无 Dock 图标。

- [ ] **Step 5: Commit**

```bash
git add BarCmd CLAUDE.md ROADMAP.md README.md docs
git commit -m "$(cat <<'EOF'
feat: 建立 BarCmd Xcode 工程与菜单栏占位

Agent App（LSUIElement）、空 entitlements、图标 C 与 Yams 依赖就位，便于后续按模块提交。
EOF
)"
```

若文档已在仓库中，只 `git add BarCmd`。

---

### Task 2: 模型与路径展开

**Files:**
- Create: `BarCmd/BarCmd/Models/CommandStatus.swift`
- Create: `BarCmd/BarCmd/Models/CommandConfig.swift`
- Create: `BarCmd/BarCmd/Models/CommandRuntime.swift`
- Create: `BarCmd/BarCmd/Models/PathExpand.swift`
- Create: `BarCmd/BarCmdTests/PathExpandTests.swift`
- Modify: `BarCmd/BarCmdTests/BarCmdTests.swift`（可删占位测试）

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum CommandStatus: String, Sendable { case stopped, starting, running, exited }`
  - `struct CommandConfig: Identifiable, Equatable, Codable, Sendable` 字段 `id: UUID`, `name: String`, `command: String`, `cwd: String?`, `env: [String: String]`
  - `struct CommandRuntime: Equatable, Sendable` 字段 `status`, `pid: Int32?`, `pgid: Int32?`, `port: Int?`, `exitCode: Int32?`, `startedAt: Date?`, `removedFromConfig: Bool`（默认 `false`）
  - `enum PathExpand { static func expand(_ path: String?, home: String) -> URL }`

- [ ] **Step 1: 写失败测试**

`BarCmd/BarCmdTests/PathExpandTests.swift`:

```swift
import XCTest
@testable import BarCmd

final class PathExpandTests: XCTestCase {
    let home = "/Users/tester"

    func testNilUsesHome() {
        XCTAssertEqual(PathExpand.expand(nil, home: home).path, home)
    }

    func testTilde() {
        XCTAssertEqual(PathExpand.expand("~", home: home).path, home)
    }

    func testTildeSlash() {
        XCTAssertEqual(PathExpand.expand("~/src", home: home).path, "/Users/tester/src")
    }

    func testAbsoluteUnchanged() {
        XCTAssertEqual(PathExpand.expand("/tmp/work", home: home).path, "/tmp/work")
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/PathExpandTests
```

Expected: FAIL，`PathExpand` 找不到。

- [ ] **Step 3: 最小实现**

`CommandStatus.swift`:

```swift
enum CommandStatus: String, Sendable {
    case stopped, starting, running, exited
}
```

`CommandConfig.swift`:

```swift
import Foundation

struct CommandConfig: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var name: String
    var command: String
    var cwd: String?
    var env: [String: String]

    init(id: UUID, name: String, command: String, cwd: String? = nil, env: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.command = command
        self.cwd = cwd
        self.env = env
    }

    enum CodingKeys: String, CodingKey {
        case id, name, command, cwd, env
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        command = try c.decode(String.self, forKey: .command)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        env = try c.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(command, forKey: .command)
        try c.encodeIfPresent(cwd, forKey: .cwd)
        if !env.isEmpty { try c.encode(env, forKey: .env) }
    }
}
```

`CommandRuntime.swift`:

```swift
import Foundation

struct CommandRuntime: Equatable, Sendable {
    var status: CommandStatus = .stopped
    var pid: Int32?
    var pgid: Int32?
    var port: Int?
    var exitCode: Int32?
    var startedAt: Date?
    var removedFromConfig: Bool = false
}
```

`PathExpand.swift`:

```swift
import Foundation

enum PathExpand {
    static func expand(_ path: String?, home: String = NSHomeDirectory()) -> URL {
        let raw: String
        if let path, !path.isEmpty {
            if path == "~" {
                raw = home
            } else if path.hasPrefix("~/") {
                raw = home + "/" + path.dropFirst(2)
            } else {
                raw = path
            }
        } else {
            raw = home
        }
        return URL(fileURLWithPath: raw)
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/PathExpandTests
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add BarCmd/BarCmd/Models BarCmd/BarCmdTests/PathExpandTests.swift
git commit -m "$(cat <<'EOF'
feat: 加入命令配置/运行时模型与路径展开

YAML 与 UI 共用同一套值类型；cwd 的 ~ 展开可单测，避免启动时写错工作目录。
EOF
)"
```

---

### Task 3: ConfigStore

**Files:**
- Create: `BarCmd/BarCmd/Services/ConfigStore.swift`
- Create: `BarCmd/BarCmdTests/ConfigStoreTests.swift`

**Interfaces:**
- Consumes: `CommandConfig`
- Produces:
  - `struct CommandsFile: Codable { var commands: [CommandConfig] }`
  - `struct ConfigError: Error, LocalizedError { var line: Int?; var message: String }`
  - `final class ConfigStore`：`init(directory: URL)`，`func load() throws -> [CommandConfig]`，`func save(_ configs: [CommandConfig]) throws`，`func lastWrittenHash() -> String?`，`func currentFileHash() throws -> String?`，`var fileURL: URL`，`var backupURL: URL`，`func revealInFinder()`
  - 本任务不做 FSEvents（Task 11）

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
import Yams
@testable import BarCmd

final class ConfigStoreTests: XCTestCase {
    var dir: URL!
    var store: ConfigStore!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = ConfigStore(directory: dir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func testMissingFileLoadsEmptyAndWritesSkeleton() throws {
        let list = try store.load()
        XCTAssertTrue(list.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    func testRoundTrip() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let config = CommandConfig(id: id, name: "DSH", command: "npx dsh web", cwd: "~", env: ["FOO": "bar"])
        try store.save([config])
        let loaded = try store.load()
        XCTAssertEqual(loaded, [config])
        XCTAssertNotNil(store.lastWrittenHash())
        XCTAssertEqual(store.lastWrittenHash(), try store.currentFileHash())
    }

    func testUnknownFieldsIgnored() throws {
        let yaml = """
        commands:
          - id: "22222222-2222-2222-2222-222222222222"
            name: "X"
            command: "echo"
            autoStart: true
        """
        try yaml.write(to: store.fileURL, atomically: true, encoding: .utf8)
        let loaded = try store.load()
        XCTAssertEqual(loaded.first?.name, "X")
        XCTAssertEqual(loaded.first?.env, [:])
    }

    func testInvalidYAMLThrows() throws {
        try "::::".write(to: store.fileURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertTrue(error is ConfigError)
        }
    }

    func testSaveWritesBackup() throws {
        let config = CommandConfig(id: UUID(), name: "A", command: "true")
        try store.save([config])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL.path))
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/ConfigStoreTests
```

Expected: FAIL，`ConfigStore` 找不到。

- [ ] **Step 3: 最小实现**

```swift
import AppKit
import CryptoKit
import Foundation
import Yams

struct CommandsFile: Codable {
    var commands: [CommandConfig]
}

struct ConfigError: Error, LocalizedError {
    var line: Int?
    var message: String
    var errorDescription: String? {
        if let line {
            return "第 \(line) 行：\(message)"
        }
        return message
    }
}

final class ConfigStore {
    let directory: URL
    let fileURL: URL
    let backupURL: URL
    private(set) var lastWrittenHash: String?

    init(directory: URL) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("commands.yaml")
        self.backupURL = directory.appendingPathComponent("commands.yaml.bak")
    }

    convenience init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.init(directory: root.appendingPathComponent("BarCmd", isDirectory: true))
    }

    func load() throws -> [CommandConfig] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try save([])
            return []
        }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        do {
            let file = try YAMLDecoder().decode(CommandsFile.self, from: text)
            return file.commands
        } catch {
            let line = (error as? YamlError).flatMap { _ in nil as Int? }
            throw ConfigError(line: line, message: error.localizedDescription)
        }
    }

    func save(_ configs: [CommandConfig]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = try YAMLEncoder().encode(CommandsFile(commands: configs))
        let temp = directory.appendingPathComponent("commands.yaml.tmp")
        try text.write(to: temp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: fileURL, to: backupURL)
            try FileManager.default.replaceItem(at: fileURL, withItemAt: temp, backupItemName: nil, options: [], resultingItemURL: nil)
        } else {
            try FileManager.default.moveItem(at: temp, to: fileURL)
        }
        lastWrittenHash = try currentFileHash()
        if lastWrittenHash != nil {
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        }
    }

    func currentFileHash() throws -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func lastWrittenHashValue() -> String? { lastWrittenHash }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
```

修正测试：把 `store.lastWrittenHash()` 改成属性 `store.lastWrittenHash`（上面对齐接口用属性）。Task 接口以 **属性 `lastWrittenHash`** 为准，删掉 `lastWrittenHash()` 方法。`save` 的 backup 逻辑保持「成功后 `.bak` 存在」即可：先写 temp，replace 到 `fileURL`，再 copy 到 `.bak`，然后记 hash。

精简后的 `save`：

```swift
func save(_ configs: [CommandConfig]) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let text = try YAMLEncoder().encode(CommandsFile(commands: configs))
    let temp = directory.appendingPathComponent("commands.yaml.tmp")
    try text.write(to: temp, atomically: true, encoding: .utf8)
    if FileManager.default.fileExists(atPath: fileURL.path) {
        try FileManager.default.replaceItem(at: fileURL, withItemAt: temp, backupItemName: nil, options: [], resultingItemURL: nil)
    } else {
        try FileManager.default.moveItem(at: temp, to: fileURL)
    }
    try? FileManager.default.removeItem(at: backupURL)
    try FileManager.default.copyItem(at: fileURL, to: backupURL)
    lastWrittenHash = try currentFileHash()
}
```

- [ ] **Step 4: 跑测试，确认通过**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/ConfigStoreTests
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add BarCmd/BarCmd/Services/ConfigStore.swift BarCmd/BarCmdTests/ConfigStoreTests.swift
git commit -m "$(cat <<'EOF'
feat: 实现 commands.yaml 原子读写与备份

UI 与文件共用同一编解码；写后记 SHA256，给后续 FSEvents 去重用。
EOF
)"
```

---

### Task 4: ANSIStripper 与 LogBuffer

**Files:**
- Create: `BarCmd/BarCmd/Services/ANSIStripper.swift`
- Create: `BarCmd/BarCmd/Services/LogBuffer.swift`
- Create: `BarCmd/BarCmdTests/ANSIStripperTests.swift`
- Create: `BarCmd/BarCmdTests/LogBufferTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum ANSIStripper { static func strip(_ input: String) -> String }`
  - `final class LogBufferStore: @unchecked Sendable`：`func append(id: UUID, line: String)`（内部先 strip），`func lines(id: UUID) -> [String]`，`func clear(id: UUID)`，`func remove(id: UUID)`，`func updates(id: UUID) -> AsyncStream<[String]>`
  - 容量常量 `LogBufferStore.capacity = 10_000`

- [ ] **Step 1: 写失败测试**

`ANSIStripperTests.swift`:

```swift
import XCTest
@testable import BarCmd

final class ANSIStripperTests: XCTestCase {
    func testStripsCSI() {
        let raw = "\u{001B}[32mhello\u{001B}[0m world"
        XCTAssertEqual(ANSIStripper.strip(raw), "hello world")
    }

    func testStripsViteLike() {
        let raw = "\u{001B}[1m\u{001B}[32m  ➜  Local: \u{001B}[0m http://localhost:5173/"
        XCTAssertEqual(ANSIStripper.strip(raw), "  ➜  Local:  http://localhost:5173/")
    }

    func testStripsOSC() {
        let raw = "\u{001B}]8;;http://x\u{0007}link\u{001B}]8;;\u{0007}"
        XCTAssertEqual(ANSIStripper.strip(raw), "link")
    }

    func testPlainUnchanged() {
        XCTAssertEqual(ANSIStripper.strip("ok"), "ok")
    }
}
```

`LogBufferTests.swift`:

```swift
import XCTest
@testable import BarCmd

final class LogBufferTests: XCTestCase {
    func testAppendAndRead() {
        let store = LogBufferStore()
        let id = UUID()
        store.append(id: id, line: "\u{001B}[31ma\u{001B}[0m")
        XCTAssertEqual(store.lines(id: id), ["a"])
    }

    func testRingDropsOldest() {
        let store = LogBufferStore()
        let id = UUID()
        for i in 0..<(LogBufferStore.capacity + 3) {
            store.append(id: id, line: "\(i)")
        }
        let lines = store.lines(id: id)
        XCTAssertEqual(lines.count, LogBufferStore.capacity)
        XCTAssertEqual(lines.first, "3")
        XCTAssertEqual(lines.last, "\(LogBufferStore.capacity + 2)")
    }

    func testClearKeepsSlot() {
        let store = LogBufferStore()
        let id = UUID()
        store.append(id: id, line: "x")
        store.clear(id: id)
        XCTAssertEqual(store.lines(id: id), [])
    }

    func testRemoveDrops() {
        let store = LogBufferStore()
        let id = UUID()
        store.append(id: id, line: "x")
        store.remove(id: id)
        XCTAssertEqual(store.lines(id: id), [])
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/ANSIStripperTests -only-testing:BarCmdTests/LogBufferTests
```

Expected: FAIL

- [ ] **Step 3: 最小实现**

```swift
import Foundation

enum ANSIStripper {
    static func strip(_ input: String) -> String {
        var s = input
        s = s.replacingOccurrences(of: "\u{001B}\\][^\\u{0007}\\u{001B}]*(\\u{0007}|\\u{001B}\\\\)", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        return s
    }
}
```

```swift
import Foundation

final class LogBufferStore: @unchecked Sendable {
    static let capacity = 10_000
    private let lock = NSLock()
    private var storage: [UUID: [String]] = [:]
    private var continuations: [UUID: [UUID: AsyncStream<[String]>.Continuation]] = [:]

    func append(id: UUID, line: String) {
        let cleaned = ANSIStripper.strip(line)
        lock.lock()
        var lines = storage[id] ?? []
        lines.append(cleaned)
        if lines.count > Self.capacity {
            lines.removeFirst(lines.count - Self.capacity)
        }
        storage[id] = lines
        let snapshot = lines
        let conts = continuations[id]?.values
        lock.unlock()
        conts?.forEach { $0.yield(snapshot) }
    }

    func lines(id: UUID) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return storage[id] ?? []
    }

    func clear(id: UUID) {
        lock.lock()
        storage[id] = []
        let conts = continuations[id]?.values
        lock.unlock()
        conts?.forEach { $0.yield([]) }
    }

    func remove(id: UUID) {
        lock.lock()
        storage[id] = nil
        let conts = continuations[id]?.values
        continuations[id] = nil
        lock.unlock()
        conts?.forEach { $0.finish() }
    }

    func updates(id: UUID) -> AsyncStream<[String]> {
        AsyncStream { continuation in
            let token = UUID()
            lock.lock()
            var bag = continuations[id] ?? [:]
            bag[token] = continuation
            continuations[id] = bag
            let initial = storage[id] ?? []
            lock.unlock()
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations[id]?[token] = nil
                self.lock.unlock()
            }
        }
    }
}
```

- [ ] **Step 4: 跑测试，确认通过**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/ANSIStripperTests -only-testing:BarCmdTests/LogBufferTests
```

Expected: PASS。若 OSC 正则过严/过宽，按失败用例改 `ANSIStripper`，不要改测试意图。

- [ ] **Step 5: Commit**

```bash
git add BarCmd/BarCmd/Services/ANSIStripper.swift BarCmd/BarCmd/Services/LogBuffer.swift BarCmd/BarCmdTests/ANSIStripperTests.swift BarCmd/BarCmdTests/LogBufferTests.swift
git commit -m "$(cat <<'EOF'
feat: 日志环形缓冲并在入队前剥 ANSI

避免 Vite/Next 转义码污染窗口；超 10000 行丢最旧，打开窗口可回放。
EOF
)"
```

---

### Task 5: PortDetector（日志正则 + 合并）

**Files:**
- Create: `BarCmd/BarCmd/Services/PortDetector.swift`
- Create: `BarCmd/BarCmd/Services/LsofClient.swift`
- Create: `BarCmd/BarCmdTests/PortDetectorTests.swift`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum PortDetector`：
    - `static func parseLogLine(_ line: String) -> (priority: Int, port: Int)?`
    - `static func merge(logPort: Int?, lsofPorts: [Int], consecutiveEmptyLsof: Int) -> Int?`
  - `struct PortTracker`：`mutating func ingestLogLine(_ line: String) -> Int?`，`var logPort: Int?`，`var logPriority: Int`
  - `enum LsofParser { static func ports(fromStandardOutput output: String) -> [Int] }`
  - `protocol LsofClient: Sendable { func listeningPorts(pids: [Int32]) throws -> [Int] }`
  - 本任务不跑真 `lsof`（Task 10）

优先级（数字越小越高）：`0` URL，`1` listening on，`2` Local:，`3` server running。端口必须 ∈ `[1, 65535]`。

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import BarCmd

final class PortDetectorTests: XCTestCase {
    func testURL127() {
        let hit = PortDetector.parseLogLine("ready at http://127.0.0.1:3080")
        XCTAssertEqual(hit?.port, 3080)
        XCTAssertEqual(hit?.priority, 0)
    }

    func testLocalhostHTTPS() {
        XCTAssertEqual(PortDetector.parseLogLine("https://localhost:5173")?.port, 5173)
    }

    func testListeningOn() {
        XCTAssertEqual(PortDetector.parseLogLine("Listening on port 4000")?.port, 4000)
        XCTAssertEqual(PortDetector.parseLogLine("listening on 4000")?.priority, 1)
    }

    func testViteLocal() {
        XCTAssertEqual(PortDetector.parseLogLine("  ➜  Local:   http://localhost:5173/")?.port, 5173)
        XCTAssertEqual(PortDetector.parseLogLine("  ➜  Local:   http://localhost:5173/")?.priority, 2)
    }

    func testServerRunning() {
        XCTAssertEqual(PortDetector.parseLogLine("Server running on 0.0.0.0:8080")?.port, 8080)
    }

    func testRejectsTimeAndVersion() {
        XCTAssertNil(PortDetector.parseLogLine("12:34:56"))
        XCTAssertNil(PortDetector.parseLogLine("version v1.2.3"))
    }

    func testHigherPriorityOverrides() {
        var tracker = PortTracker()
        XCTAssertEqual(tracker.ingestLogLine("listening on 4000"), 4000)
        XCTAssertEqual(tracker.ingestLogLine("http://127.0.0.1:3080"), 3080)
        XCTAssertEqual(tracker.ingestLogLine("listening on 9000"), 3080)
    }

    func testMergePrefersLsofIntersection() {
        XCTAssertEqual(PortDetector.merge(logPort: 5173, lsofPorts: [5173, 24678], consecutiveEmptyLsof: 0), 5173)
    }

    func testMergeMinUserPort() {
        XCTAssertEqual(PortDetector.merge(logPort: 80, lsofPorts: [24678, 5173], consecutiveEmptyLsof: 0), 5173)
    }

    func testMergeEmptyKeepsLogUntilThree() {
        XCTAssertEqual(PortDetector.merge(logPort: 3080, lsofPorts: [], consecutiveEmptyLsof: 2), 3080)
        XCTAssertNil(PortDetector.merge(logPort: nil, lsofPorts: [], consecutiveEmptyLsof: 3))
    }

    func testLsofParser() {
        let sample = """
        COMMAND   PID USER   FD   TYPE     DEVICE SIZE/OFF NODE NAME
        node    12345 me   23u  IPv4 0x0      0t0  TCP 127.0.0.1:5173 (LISTEN)
        node    12345 me   24u  IPv4 0x0      0t0  TCP *:24678 (LISTEN)
        """
        XCTAssertEqual(Set(LsofParser.ports(fromStandardOutput: sample)), [5173, 24678])
    }
}
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/PortDetectorTests
```

Expected: FAIL

- [ ] **Step 3: 最小实现**

`PortDetector.swift` 实现四个正则，按 0...3 扫描，先命中的（优先级数字小）返回。`PortTracker` 仅当新 priority `<` 当前时覆盖。`merge`：lsof 非空则以 lsof 为准（交集优先，否则 `>= 1024` 最小，否则全局最小）；lsof 空则返回 `logPort`，除非 `logPort == nil && consecutiveEmptyLsof >= 3` 则 nil。

`LsofParser`：用正则 `:(\d+) \(LISTEN\)` 抽端口。

`LsofClient.swift` 本任务只放 protocol：

```swift
protocol LsofClient: Sendable {
    func listeningPorts(pids: [Int32]) throws -> [Int]
}
```

- [ ] **Step 4: 跑测试，确认通过**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/PortDetectorTests
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add BarCmd/BarCmd/Services/PortDetector.swift BarCmd/BarCmd/Services/LsofClient.swift BarCmd/BarCmdTests/PortDetectorTests.swift
git commit -m "$(cat <<'EOF'
feat: 实现日志端口解析与 lsof 合并规则

去掉裸 :数字 兜底，避免把时间戳当端口；多端口时优先日志命中再取最小用户端口。
EOF
)"
```

---

### Task 6: 进程组、启动参数、ProcessManager

**Files:**
- Create: `BarCmd/BarCmd/Services/ProcessControlling.swift`
- Create: `BarCmd/BarCmd/Services/ProcessSpawner.swift`
- Create: `BarCmd/BarCmd/Services/ProcessTree.swift`
- Create: `BarCmd/BarCmd/Services/ProcessManager.swift`
- Create: `BarCmd/BarCmdTests/ProcessSpawnerTests.swift`
- Create: `BarCmd/BarCmdTests/ProcessManagerTests.swift`

**Interfaces:**
- Consumes: `CommandConfig`, `PathExpand`, `ANSIStripper`
- Produces:
  - `protocol ProcessControlling: Sendable`：`func start(config: CommandConfig, cwd: URL, onOutput: @escaping @Sendable (UUID, String) -> Void, onExit: @escaping @Sendable (UUID, Int32) -> Void) throws`，`func stop(id: UUID) async`，`func stopAll() async`，`func runtimeSnapshot(id: UUID) -> (pid: Int32, pgid: Int32)?`
  - `enum ProcessSpawner`：`static func shellExecutable() -> String`，`static func arguments(command: String, env: [String: String], shellName: String) -> [String]`，`static func posixExports(_ env: [String: String]) -> String`
  - `enum ProcessTree`：`static func pids(inGroup pgid: Int32) -> [Int32]`，`static func descendantPIDs(of pid: Int32) -> [Int32]`，`static func send(_ signal: Int32, toGroup pgid: Int32) -> Bool`，`static func send(_ signal: Int32, toPIDs pids: [Int32])`
  - `actor ProcessManager: ProcessControlling`

- [ ] **Step 1: 写失败测试**

`ProcessSpawnerTests.swift`:

```swift
import XCTest
@testable import BarCmd

final class ProcessSpawnerTests: XCTestCase {
    func testZshSourcesZshrcAndExports() {
        let args = ProcessSpawner.arguments(command: "npx dsh web", env: ["FOO": "b\"ar"], shellName: "zsh")
        XCTAssertEqual(args[0], "-l")
        XCTAssertEqual(args[1], "-c")
        XCTAssertTrue(args[2].contains("source \"${ZDOTDIR:-$HOME}/.zshrc\""))
        XCTAssertTrue(args[2].contains("export FOO="))
        XCTAssertTrue(args[2].contains("npx dsh web"))
        XCTAssertFalse(args.contains("-i"))
    }

    func testBashSourcesBashrc() {
        let args = ProcessSpawner.arguments(command: "true", env: [:], shellName: "bash")
        XCTAssertTrue(args[2].contains("source \"$HOME/.bashrc\""))
    }
}
```

`ProcessManagerTests.swift`:

```swift
import XCTest
@testable import BarCmd

final class ProcessManagerTests: XCTestCase {
    func testEchoExitCode() async throws {
        let mgr = ProcessManager()
        let id = UUID()
        let config = CommandConfig(id: id, name: "e", command: "echo hi >&2; echo ok; exit 3")
        let cwd = URL(fileURLWithPath: NSHomeDirectory())
        let lines = Locked<[String]>([])
        let exited = expectation(description: "exit")
        var code: Int32 = 0
        try await mgr.start(config: config, cwd: cwd, onOutput: { _, line in
            lines.value.append(line)
        }, onExit: { _, c in
            code = c
            exited.fulfill()
        })
        await fulfillment(of: [exited], timeout: 10)
        XCTAssertEqual(code, 3)
        let joined = lines.value.joined(separator: "\n")
        XCTAssertTrue(joined.contains("ok"))
        XCTAssertTrue(joined.contains("hi"))
    }

    func testStopSleep() async throws {
        let mgr = ProcessManager()
        let id = UUID()
        let config = CommandConfig(id: id, name: "s", command: "sleep 30")
        let exited = expectation(description: "stopped")
        try await mgr.start(config: config, cwd: URL(fileURLWithPath: NSHomeDirectory()), onOutput: { _, _ in }, onExit: { _, _ in
            exited.fulfill()
        })
        let snap = await mgr.runtimeSnapshot(id: id)
        XCTAssertNotNil(snap?.pid)
        await mgr.stop(id: id)
        await fulfillment(of: [exited], timeout: 8)
        let after = await mgr.runtimeSnapshot(id: id)
        XCTAssertNil(after)
    }
}

final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: T
    init(_ value: T) { storage = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }
}
```

注意：`ProcessManager.start` 若是 actor 方法，测试里用 `try await mgr.start(...)`。接口写成 `async throws` 以便调用侧统一。`ProcessControlling.start` 定为 `async throws`。

- [ ] **Step 2: 跑测试，确认失败**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/ProcessSpawnerTests
```

Expected: FAIL

- [ ] **Step 3: 最小实现**

`ProcessSpawner.arguments` 按架构表拼接。`posixExports`：key 匹配 `^[A-Za-z_][A-Za-z0-9_]*$` 才 export；value 转义 `\ " $ \``。

`ProcessSpawner.launch`（internal）：创建 `Process`，`executableURL = URL(fileURLWithPath: shell)`，`arguments` 如上，`currentDirectoryURL = cwd`，**不要设 `environment`**，`standardInput = FileHandle.nullDevice`，stdout/stderr 同一 `Pipe`，`run()` 后 `setpgid(pid, pid)`，返回 `(process, pid, pgid)`。cwd 不存在则 throw `NSError`。

`ProcessTree`：`proc_listpids(PROC_ALL_PIDS, ...)` + `proc_pidinfo(..., PROC_PIDTBSDINFO, ...)` 读 `pbi_pid / pbi_ppid / pbi_pgid`。`descendantPIDs` BFS 含自身。`send toGroup` 用 `killpg`。`send toPIDs` 用 `kill`。

`ProcessManager`：

- 字典 `id -> (Process, pid, pgid, stopRequested: Bool)`
- `start`：已有 running 则 return；拼 Pipe，`readabilityHandler` 按 `\n` 拆行、`ANSIStripper.strip`、调 `onOutput`；`terminationHandler` 调 `onExit` 并移除字典
- `stop`：若 `pgid == pid` 则 `ProcessTree.send(SIGTERM, toGroup:)`，否则 `send(SIGTERM, toPIDs: descendantPIDs)`；`await` termination 最多 5s（用 `withCheckedContinuation` + handler 或轮询 `process.isRunning`）；仍在则 SIGKILL，再等最多 2s
- `stopAll`：`async let` 并行 stop 所有 id
- `start` 标记 `stopRequested` 供 AppModel 区分 exited/stopped——**ProcessManager 不管 UI 状态**，只保证 `onExit` 在 stop 或自然退出时各到一次。AppModel 用自己的 `stoppingIDs` 区分（Task 7）

`ProcessControlling`：

```swift
protocol ProcessControlling: Sendable {
    func start(
        config: CommandConfig,
        cwd: URL,
        onOutput: @escaping @Sendable (UUID, String) -> Void,
        onExit: @escaping @Sendable (UUID, Int32) -> Void
    ) async throws
    func stop(id: UUID) async
    func stopAll() async
    func runtimeSnapshot(id: UUID) -> (pid: Int32, pgid: Int32)?
}
```

actor 里 `runtimeSnapshot` 必须是 `async` 才能从外面 await。改成：

```swift
func runtimeSnapshot(id: UUID) async -> (pid: Int32, pgid: Int32)?
```

测试与后续 AppModel 一律 `await runtimeSnapshot`。

- [ ] **Step 4: 跑测试，确认通过**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/ProcessSpawnerTests -only-testing:BarCmdTests/ProcessManagerTests
```

Expected: PASS。`sleep` 必须在 8s 内被杀掉，不能靠等满 30s。

- [ ] **Step 5: Commit**

```bash
git add BarCmd/BarCmd/Services/ProcessControlling.swift BarCmd/BarCmd/Services/ProcessSpawner.swift BarCmd/BarCmd/Services/ProcessTree.swift BarCmd/BarCmd/Services/ProcessManager.swift BarCmd/BarCmdTests/ProcessSpawnerTests.swift BarCmd/BarCmdTests/ProcessManagerTests.swift
git commit -m "$(cat <<'EOF'
feat: 在独立进程组中启动 login shell 并按组停止

显式 source zshrc/bashrc 以继承 nvm/conda；stop 走 SIGTERM→5s→SIGKILL，避免只杀掉 npx 外壳。
EOF
)"
```

---

### Task 7: AppModel 状态机

**Files:**
- Create: `BarCmd/BarCmd/App/UserPrompter.swift`
- Create: `BarCmd/BarCmd/App/AppModel.swift`
- Create: `BarCmd/BarCmdTests/AppModelTests.swift`
- Create: `BarCmd/BarCmdTests/Fakes.swift`

**Interfaces:**
- Consumes: `CommandConfig`, `CommandRuntime`, `ConfigStore`, `ProcessControlling`, `LogBufferStore`, `PortDetector`/`PortTracker`
- Produces: `@MainActor @Observable final class AppModel`，方法与架构一致，另加 `func runtime(_ id: UUID) -> CommandRuntime`，`var isQuitting: Bool`，`var loadError: String?`
  - `protocol UserPrompter`：`func confirmStopForEdit(name: String) async -> Bool`，`func confirmStopForDelete(name: String) async -> Bool`，`func confirmDelete(name: String) async -> Bool`，`func confirmQuit(runningCount: Int) async -> Bool`，`func confirmReload() async -> Bool`，`func alert(title: String, message: String) async`

- [ ] **Step 1: 写失败测试**

`Fakes.swift`：`final class FakeProcess: ProcessControlling` 记录 start/stop，用字典模拟 pid，调用 `finish(id:code:)` 触发 `onExit`。`final class FakePrompter: UserPrompter` 用可设的 Bool 返回值。

`AppModelTests.swift` 覆盖：

1. `start`：stopped → starting → running（Fake start 成功后 AppModel 置 running + pid）
2. 自然 `onExit` → `exited`，保留 exitCode，清 pid/port
3. `stop` → `stopped`，清 pid/port/exitCode/startedAt
4. `running` 时再 `start` 不调用 Fake 第二次
5. cwd 不存在：`exited`，`LogBuffer` 有中文错误行
6. `requestEdit` running + prompter false → 仍 running，不打开（返回 false）
7. `requestEdit` running + prompter true → Fake.stop 被调，返回 true，状态 stopped
8. `requestDelete` stopped + confirm true → configs 变空并 `ConfigStore.load` 为空
9. `applyExternalReload`：YAML 删掉 running 的 id → 仍在 configs，`removedFromConfig == true`；stop 后从列表消失且不写回 YAML
10. `hasRunning`（包成 `var runningCount: Int`）在 running 时为 1

AppModel 初始化：

```swift
init(
    store: ConfigStore,
    processes: ProcessControlling,
    logs: LogBufferStore,
    prompter: UserPrompter,
    openLogWindow: @escaping (UUID) -> Void = { _ in }
)
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/AppModelTests
```

Expected: FAIL

- [ ] **Step 3: 最小实现**

`start`：若 status 已是 starting/running 则 return；写 starting；`PathExpand.expand`；若目录不存在，append 日志「工作目录不存在：…」，写 exited；否则 `try await processes.start`，成功后 `runtimeSnapshot` 填 pid/pgid、`startedAt = Date()`、status running。失败则 exited + 日志。

`onOutput`（MainActor）：`logs.append`；对该 id 的 `PortTracker` `ingestLogLine`，更新 `runtime.port`。

`onExit`：若 `stoppingIDs` 含 id → stopped 并清空 pid/port/startedAt/exitCode；否则 exited，清 pid/port，留 exitCode。若 `removedFromConfig`，从 `configs` 删除并 `logs.remove`，不 save（已经不在文件里）。

`stop`：插入 `stoppingIDs`，`await processes.stop`。

`add`/`update`：改 `configs` 后 `store.save(configs.filter { runtimes[$0.id]?.removedFromConfig != true })`。

`requestEdit`：running/starting 则 `confirmStopForEdit`，否 return false；是则 `await stop`，成功 return true。stopped/exited 直接 true。

`requestDelete`：running/starting 则 `confirmStopForDelete`，否 return false；是则 stop。然后 `confirmDelete`（stopped 也要）；是则 remove + save + `logs.remove`。

`requestQuit`：`runningCount == 0` 或 `confirmQuit` 为 true 时，`isQuitting = true`，`await stopAll()`，然后调 `var terminateApp: () -> Void`（默认 `NSApp.terminate(nil)`）。**不要在 AppModel 里再调 terminate 递归**。Quit 的正式路径在 Task 11 的 AppDelegate；这里 `requestQuit` 只设 `NSApp.terminate(nil)` 让 Delegate 接手。因此 `requestQuit` 实现为 `NSApp.terminate(nil)`。测试 10 只测 `runningCount`。

`applyExternalReload`：`let fresh = try store.load()`。对当前 running/starting 且不在 fresh 的 id：保留 config，`removedFromConfig = true`。其余用 fresh 替换。不重启进程。

- [ ] **Step 4: 跑测试，确认通过**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/AppModelTests
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add BarCmd/BarCmd/App/UserPrompter.swift BarCmd/BarCmd/App/AppModel.swift BarCmd/BarCmdTests/AppModelTests.swift BarCmd/BarCmdTests/Fakes.swift
git commit -m "$(cat <<'EOF'
feat: 实现 AppModel 启停与编辑删除闸门

把确认框抽成 UserPrompter，状态机可单测；外部 YAML 删掉运行中命令时先挂起，停止后再消失。
EOF
)"
```

---

### Task 8: Popover 列表与编辑 Sheet

**Files:**
- Create: `BarCmd/BarCmd/Views/MenuBarView.swift`
- Create: `BarCmd/BarCmd/Views/CommandRowView.swift`
- Create: `BarCmd/BarCmd/Views/CommandEditSheet.swift`
- Create: `BarCmd/BarCmd/App/AlertPrompter.swift`
- Modify: `BarCmd/BarCmd/App/BarCmdApp.swift`

**Interfaces:**
- Consumes: `AppModel` 的全部方法与 `configs` / `runtime(_:)`
- Produces: 可点的列表 UI；文案与规格一致

- [ ] **Step 1: 实现 `AlertPrompter`**

用 `NSAlert`：`confirmStopForEdit` 文案「请先停止该命令再编辑」，按钮「取消」「停止并编辑」。删除对应「停止并删除」与「确定删除？」。`confirmQuit`：「有 N 条命令正在运行，退出将停止它们。」「取消」「退出并停止」。`confirmReload`：「配置已更新，是否重载？」。`alert` 单按钮「好」。全部在 MainActor 用 `alert.runModal()`；包进 `async` 用 `await MainActor.run`。

- [ ] **Step 2: 实现三个 View**

`MenuBarView`：宽 420，空状态「还没有命令」。`ForEach(model.configs)` → `CommandRowView`。底栏：＋ 添加命令、📂 打开配置（`model.revealConfig()`）、退出 BarCmd（`NSApp.terminate(nil)`）。`isQuitting` 时 `disabled(true)`。Sheet 绑定 `editing: CommandConfig?`（nil id 表示新建）。

`CommandRowView`：

- 状态点：running 绿、stopped 灰、exited 红、starting 灰点 + 小 `ProgressView`
- 名称 `lineLimit(1)`；`removedFromConfig` 时名称旁「已从配置移除」
- 按钮 ▶ ⏹ 📋 ✎ 🗑（system 符号仅作按钮图标，**菜单栏 App 图标仍用 MenuBarIcon**）
- 副行 command，`.help(command)`
- 状态行：`PID \(pid)`、可点 `:port`（`NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(port)")!)`）、status 文本
- ▶：`stopped/exited` 可用 → `Task { await model.start(id) }`
- ⏹：`starting/running` 可用 → `Task { await model.stop(id) }`
- 📋：`model.openLog(id)`
- ✎：`Task { if await model.requestEdit(id) { open sheet with that config } }`
- 🗑：`Task { _ = await model.requestDelete(id) }`

`CommandEditSheet`：Name / Command 必填；Working Directory；Environment 用多行 `KEY=VALUE`。保存：新建则 `CommandConfig(id: UUID(), ...)` + `model.add`；编辑则 `model.update`。禁用空 name/command。

- [ ] **Step 3: 接线 `BarCmdApp`**

```swift
@main
struct BarCmdApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var model: AppModel

    init() {
        let store = ConfigStore()
        let logs = LogBufferStore()
        let model = AppModel(
            store: store,
            processes: ProcessManager(),
            logs: logs,
            prompter: AlertPrompter()
        )
        _model = State(initialValue: model)
        // AppDelegate 在 Task 11 再接 model；本任务 delegate 可先空类
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .frame(width: 420)
        } label: {
            Image("MenuBarIcon")
        }
        .menuBarExtraStyle(.window)
    }
}
```

本任务先建空 `AppDelegate: NSObject, NSApplicationDelegate {}`，`applicationDidFinishLaunching` 里 `NSApp.setActivationPolicy(.accessory)`。

启动时 `AppModel` `init` 调用 `store.load()`；失败则 `loadError` + 试 `backupURL`；再失败空列表。`loadError` 非空时 `MenuBarView.onAppear` 调 `prompter.alert`。

- [ ] **Step 4: 手动编译运行**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' build
```

Expected: BUILD SUCCEEDED。运行后：添加一条 `echo hello; sleep 2`，能看到 starting → running → exited；编辑/删除 running 的命令会先确认停止。

- [ ] **Step 5: Commit**

```bash
git add BarCmd/BarCmd/Views BarCmd/BarCmd/App/AlertPrompter.swift BarCmd/BarCmd/App/BarCmdApp.swift BarCmd/BarCmd/App/AppDelegate.swift
git commit -m "$(cat <<'EOF'
feat: 接上菜单栏命令列表与编辑表单

五个操作按钮和中文确认框按规格接线，空列表与退出入口可从 Popover 到达。
EOF
)"
```

---

### Task 9: 独立日志窗口

**Files:**
- Create: `BarCmd/BarCmd/Views/LogWindowView.swift`
- Modify: `BarCmd/BarCmd/App/BarCmdApp.swift`
- Modify: `BarCmd/BarCmd/App/AppModel.swift`（`openLog` 调 `openWindow`）

**Interfaces:**
- Consumes: `LogBufferStore.updates`、`AppModel.runtime`
- Produces: `WindowGroup(id: "command-log", for: UUID.self)`

- [ ] **Step 1: 实现 `LogWindowView`**

等宽（`Font.system(.body, design: .monospaced)`），背景 `#1C1C1E`，前景浅灰。`ScrollView` + `LazyVStack(alignment: .leading)` 显示 `lines`。`onChange` 里若用户接近底部则滚到底。工具栏：复制全部（`NSPasteboard`）、清屏（`logs.clear`）、文本 `PID` / `:port` / 时长（`startedAt` 用 `Text(date, style: .timer)`，stopped/exited 显示已结束）。关窗不停进程。

- [ ] **Step 2: 接线窗口**

`BarCmdApp.body` 增加：

```swift
WindowGroup(id: "command-log", for: UUID.self) { $id in
    if let id {
        LogWindowView(commandID: id, model: model)
    }
}
.defaultSize(width: 720, height: 480)
```

`AppModel.openLog` 不能直接拿 `openWindow`。改为：

```swift
var openLogWindow: (UUID) -> Void
func openLog(_ id: UUID) { openLogWindow(id) }
```

在 `MenuBarView`：

```swift
@Environment(\.openWindow) private var openWindow
// onAppear: model.openLogWindow = { openWindow(id: "command-log", value: $0) }
```

同一 UUID 再开应聚焦已有窗口（系统 `openWindow` 默认行为）。

- [ ] **Step 3: 编译并手测**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' build
```

跑一条 `echo line1; echo line2; sleep 5`：点 📋 看到两行；关窗再开仍在；清屏只清 UI；进程不被关窗杀掉。

- [ ] **Step 4: Commit**

```bash
git add BarCmd/BarCmd/Views/LogWindowView.swift BarCmd/BarCmd/App/BarCmdApp.swift BarCmd/BarCmd/App/AppModel.swift BarCmd/BarCmd/Views/MenuBarView.swift
git commit -m "$(cat <<'EOF'
feat: 为每条命令打开独立日志窗口

同一命令复用一个窗口；关窗不停进程，打开时回放环形缓冲。
EOF
)"
```

---

### Task 10: 真 lsof 轮询

**Files:**
- Modify: `BarCmd/BarCmd/Services/LsofClient.swift`
- Modify: `BarCmd/BarCmd/App/AppModel.swift`
- Create: `BarCmd/BarCmdTests/LsofClientTests.swift`

**Interfaces:**
- Consumes: `ProcessTree`, `LsofParser`, `PortDetector.merge`
- Produces: `struct RealLsofClient: LsofClient`，`AppModel` 在 running 时每 2s 轮询

- [ ] **Step 1: 写失败测试**

`LsofClientTests`：对 `RealLsofClient.listeningPorts(pids: [getpid()])` 不崩溃；空 pid 数组返回 `[]`。再测 `LsofParser` 已在 Task 5 覆盖，这里只测「pid 列表拼进 `/usr/sbin/lsof` 参数」。把拼参提成：

```swift
enum LsofCommand {
    static func arguments(pids: [Int32]) -> [String]
}
```

测试：`XCTAssertEqual(LsofCommand.arguments(pids: [10, 20]), ["-nP", "-iTCP", "-sTCP:LISTEN", "-p", "10,20"])`  
空 pid：`arguments` 返回 `nil`，client 返回 `[]` 且不 spawn。

- [ ] **Step 2: 跑测试，确认失败**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/LsofClientTests
```

Expected: FAIL

- [ ] **Step 3: 实现并接入 AppModel**

`RealLsofClient`：`Process` 跑 `/usr/sbin/lsof` + `LsofCommand.arguments`，读 stdout，`LsofParser.ports`。非 0 退出不当作 App 错误，返回 `[]`。

`AppModel`：`start` 成功后为该 id 起 `Task`，每 2s：`snapshot = await processes.runtimeSnapshot`；`pids = ProcessTree.pids(inGroup: pgid)`，空则 `descendantPIDs(of: pid)`；`ports = try lsof.listeningPorts`；`consecutiveEmpty` 累加或清零；`runtime.port = PortDetector.merge(...)`。status 离开 running 时取消 Task。注入 `var lsof: LsofClient = RealLsofClient()`，测试可换成假客户端。

- [ ] **Step 4: 跑测试，确认通过**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/LsofClientTests -only-testing:BarCmdTests/AppModelTests
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add BarCmd/BarCmd/Services/LsofClient.swift BarCmd/BarCmd/App/AppModel.swift BarCmd/BarCmdTests/LsofClientTests.swift BarCmd/BarCmdTests/AppModelTests.swift
git commit -m "$(cat <<'EOF'
feat: 按进程组轮询 lsof 校正展示端口

只查子树 PID，避免 npx 外壳没有监听端口时漏检；与日志提示按已测规则合并。
EOF
)"
```

---

### Task 11: FSEvents 与退出协商

**Files:**
- Modify: `BarCmd/BarCmd/Services/ConfigStore.swift`
- Modify: `BarCmd/BarCmd/App/AppDelegate.swift`
- Modify: `BarCmd/BarCmd/App/AppModel.swift`
- Modify: `BarCmd/BarCmd/App/BarCmdApp.swift`
- Create: `BarCmd/BarCmdTests/ConfigWatchTests.swift`

**Interfaces:**
- Consumes: `ConfigStore.lastWrittenHash` / `currentFileHash`，`AppModel.applyExternalReload` / `stopAll` / `runningCount`
- Produces: `ConfigStore.startWatching(onExternalChange:)`；`AppDelegate.applicationShouldTerminate`

- [ ] **Step 1: 写失败测试**

`ConfigWatchTests`：临时目录 `ConfigStore`，`save` 一次，`startWatching` 用 expectation。再 `save`（哈希相同）→ 1s 内 **不** fulfill。用 `FileHandle` 直接改文件内容为另一份合法 YAML → 300ms 后 fulfill。用 `DispatchSource.makeFileSystemObjectSource` 或 `FSEventStream` 都可以，但必须忽略 hash 未变的事件。

- [ ] **Step 2: 跑测试，确认失败**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test -only-testing:BarCmdTests/ConfigWatchTests
```

Expected: FAIL

- [ ] **Step 3: 实现 watch + terminate**

`startWatching`：对 `directory` 建 `DispatchSource.makeFileSystemObjectSource(fileDescriptor: ..., eventMask: [.write, .rename, .delete], queue: .main)`，事件到来 `DispatchQueue.main.asyncAfter(0.3)` debounce；比较 `currentFileHash` 与 `lastWrittenHash`，不同才 `onExternalChange()`。

AppModel `beginWatching()`：回调里 `Task { if await prompter.confirmReload() { try applyExternalReload() } }`。

`AppDelegate`：

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.beginWatching()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.runningCount == 0 { return .terminateNow }
        let ok = AlertPrompter().confirmQuitSync(runningCount: model.runningCount)
        if !ok { return .terminateCancel }
        model.isQuitting = true
        Task { @MainActor in
            await model.stopAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
```

`UserPrompter` 增加 `func confirmQuitSync(runningCount: Int) -> Bool`（`AlertPrompter` 用 `runModal`）。`applicationShouldTerminate` 必须同步决定 cancel/later，不能 await。把这个同步方法加到 `AlertPrompter`，不必进 protocol。

`BarCmdApp.init` 创建 model 后 `appDelegate.model = model`。注意 `@NSApplicationDelegateAdaptor` 时机：在 `init` 里给 `appDelegate.model` 赋值。

- [ ] **Step 4: 跑测试 + 编译**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test
```

Expected: 全绿。手测：外部改 yaml 弹出重载；有 running 时 Cmd+Q / 退出 弹出确认，确认后进程消失再退。

- [ ] **Step 5: Commit**

```bash
git add BarCmd/BarCmd/Services/ConfigStore.swift BarCmd/BarCmd/App/AppDelegate.swift BarCmd/BarCmd/App/AppModel.swift BarCmd/BarCmd/App/BarCmdApp.swift BarCmd/BarCmd/App/AlertPrompter.swift BarCmd/BarCmd/App/UserPrompter.swift BarCmd/BarCmdTests/ConfigWatchTests.swift
git commit -m "$(cat <<'EOF'
feat: 监听外部 YAML 变更并在退出前停光进程

自己写入用哈希忽略；applicationShouldTerminate 走 terminateLater，避免残留子进程。
EOF
)"
```

---

### Task 12: 全量测试、README、ROADMAP

**Files:**
- Modify: `README.md`
- Modify: `ROADMAP.md`

**Interfaces:**
- Consumes: 已实现的全部行为
- Produces: 使用说明与验证记录

- [ ] **Step 1: 跑全部自动化测试**

```bash
xcodebuild -project BarCmd/BarCmd.xcodeproj -scheme BarCmd -destination 'platform=macOS' test
```

Expected: PASS。失败则修代码，不要改测试迁就。

- [ ] **Step 2: 手动清单（做完才能改 ROADMAP「最近验证」）**

1. `npx @deepseek-ai/dsh web`：启动、日志出 URL、`:port` 打开浏览器、停止后进程与端口消失  
2. 当前 conda/nvm 环境：`node -v` 或 `which npx` 在命令里能找到二进制  
3. 外部编辑 `~/Library/Application Support/BarCmd/commands.yaml` 后重载列表  
4. 有 running 时退出 App，Activity Monitor 里该进程组应消失  
5. 运行中点编辑/删除必须先停  
6. 菜单栏是 template `[▶]`，Dock 无图标  

- [ ] **Step 3: 更新 README 与 ROADMAP**

README 写：Xcode 打开 `BarCmd/BarCmd.xcodeproj` 跑 BarCmd；配置路径；添加一条命令的最短步骤。

ROADMAP：当前阶段改为 MVP 已实现（仅当 Step 1+2 都过）；「最近验证」逐条写过了什么、日期 2026-09-02。未跑过的条目标「待确认」，不要标已完成。

- [ ] **Step 4: Commit**

```bash
git add README.md ROADMAP.md
git commit -m "$(cat <<'EOF'
docs: 补充 BarCmd 使用说明并记录手动验证

自动化测试全绿后才把验证写进 ROADMAP，避免把未跑过的链路标成已完成。
EOF
)"
```

---

## Self-review

**Spec coverage**

| 规格/架构项 | Task |
|-------------|------|
| 菜单栏 Popover + 无 Dock | 1, 8 |
| 图标 C template | 1 |
| YAML 模型 / 原子写 / .bak | 2, 3 |
| 启停、进程组、login shell + source zshrc | 6 |
| stdout/stderr 合并、10k 日志、剥 ANSI | 4, 6, 9 |
| 端口正则 + 进程组 lsof | 5, 10 |
| 编辑/删除先停 | 7, 8 |
| 退出确认并杀进程 | 7, 11 |
| FSEvents 去重重载 | 11 |
| 日志窗口 | 9 |
| 手动 dsh / nvm / YAML / 退出 | 12 |

**未纳入（规格非目标或开放问题）：** autoStart、日志搜索、分组、多实例、设置页、崩溃孤儿扫描、公证。

**类型名：** `runtimeSnapshot` 一律 `async`；`lastWrittenHash` 是属性；`ProcessControlling.start` 是 `async throws`；`LogBufferStore.updates` 是 `AsyncStream<[String]>`。
