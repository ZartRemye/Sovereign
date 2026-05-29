#!/usr/bin/env python3
"""Generate Sovereign.xcodeproj from existing source files.
Produces a valid pbxproj in canonical Xcode format."""

import hashlib, os, re
from pathlib import Path
from collections import OrderedDict

PROJECT_ROOT = Path("/Users/zart/编程/first-cc/Sovereign")
SOURCES_DIR = PROJECT_ROOT / "Sources" / "SovereignMac"
TESTS_DIR = PROJECT_ROOT / "Tests" / "SovereignMacTests"
XCODEPROJ = PROJECT_ROOT / "Sovereign.xcodeproj"

# ── UUID generation ────────────────────────────────────────────────────────
_COUNTER = [0]

def _next_id():
    _COUNTER[0] += 1
    return hashlib.md5(str(_COUNTER[0]).encode()).hexdigest()[:24].upper()

def _file_id(relpath):
    return hashlib.md5(("f:" + relpath).encode()).hexdigest()[:24].upper()

def _build_id(relpath):
    return hashlib.md5(("b:" + relpath).encode()).hexdigest()[:24].upper()

# ── Pre-assign well-known IDs ──────────────────────────────────────────────
ROOT_OBJ       = _next_id()
MAIN_GROUP     = _next_id()
PRODUCTS_GROUP = _next_id()

APP_TARGET     = _next_id()
TEST_TARGET    = _next_id()

APP_PROD_REF   = _next_id()
TEST_PROD_REF  = _next_id()

APP_SRC_PHASE  = _next_id()
APP_FRM_PHASE  = _next_id()
APP_RES_PHASE  = _next_id()
TEST_SRC_PHASE = _next_id()
TEST_FRM_PHASE = _next_id()
TEST_RES_PHASE = _next_id()

APP_CFG_LIST   = _next_id()
TEST_CFG_LIST  = _next_id()
PROJ_CFG_LIST  = _next_id()

APP_DBG_CFG    = _next_id()
APP_REL_CFG    = _next_id()
TEST_DBG_CFG   = _next_id()
TEST_REL_CFG   = _next_id()
PROJ_DBG_CFG   = _next_id()
PROJ_REL_CFG   = _next_id()

INFO_PLIST_REF   = _next_id()
ENTITLEMENTS_REF = _next_id()
INFO_PLIST_BF    = _next_id()
ENTITLEMENTS_BF  = _next_id()

APP_DEP = _next_id()
PROXY_ID = _next_id()


# ── pbxproj value formatting ───────────────────────────────────────────────
# Characters that force quoting in OpenStep plist
_RE_NEEDS_QUOTE = re.compile(r'[ \t\n(){};,"<>@#+]|/\*|//')

def _pbx_val(v):
    """Format a single value for pbxproj inline dict."""
    if isinstance(v, bool):
        return "YES" if v else "NO"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return str(int(v)) if v == int(v) else str(v)
    if isinstance(v, str):
        if v == "":
            return '""'
        if v == "YES" or v == "NO":
            return v
        if _RE_NEEDS_QUOTE.search(v):
            return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
        return v
    if isinstance(v, list):
        if not v:
            return "()"
        items = ", ".join(_pbx_val(i) for i in v)
        return "(" + items + ")"
    if isinstance(v, dict):
        return _pbx_inline_dict(v)
    return str(v)

def _pbx_inline_dict(d):
    """Serialize a dict as inline {key = value; key = value; ...}."""
    parts = []
    for k, v in d.items():
        parts.append(f"{k} = {_pbx_val(v)};")
    return "{" + " ".join(parts) + "}"

def _pbx_comment(path):
    """Generate a file comment from a path."""
    return f" /* {path} */"


# ── File scanning ──────────────────────────────────────────────────────────
def scan_files(base, prefix):
    files = []
    for root, dirs, filenames in os.walk(base):
        for fn in sorted(filenames):
            if fn.endswith(".swift"):
                full = Path(root) / fn
                rel = str(full.relative_to(PROJECT_ROOT))
                inner = str(full.relative_to(base).parent)
                parts = inner.split(os.sep) if inner != "." else []
                files.append((rel, parts, fn))
    return files

app_files = scan_files(SOURCES_DIR, "Sources/SovereignMac")
test_files = scan_files(TESTS_DIR, "Tests/SovereignMacTests")


# ── Group tree ─────────────────────────────────────────────────────────────
def build_tree(files):
    root = {"files": [], "subs": OrderedDict()}
    for relpath, parts, fn in files:
        node = root
        for p in parts:
            node = node["subs"].setdefault(p, {"files": [], "subs": OrderedDict()})
        node["files"].append((relpath, fn))
    return root


# ── Serialize pbxproj ──────────────────────────────────────────────────────
def serialize(objs):
    lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};",
             "\tobjectVersion = 56;", "\tobjects = {", ""]

    # Group objects by type for section comments
    sections = OrderedDict()
    for uuid, obj in objs.items():
        isa = obj["isa"]
        sections.setdefault(isa, []).append(uuid)

    section_names = {
        "PBXBuildFile": "PBXBuildFile section",
        "PBXFileReference": "PBXFileReference section",
        "PBXGroup": "PBXGroup section",
        "PBXNativeTarget": "PBXNativeTarget section",
        "PBXProject": "PBXProject section",
        "PBXSourcesBuildPhase": "PBXSourcesBuildPhase section",
        "PBXFrameworksBuildPhase": "PBXFrameworksBuildPhase section",
        "PBXResourcesBuildPhase": "PBXResourcesBuildPhase section",
        "PBXContainerItemProxy": "PBXContainerItemProxy section",
        "PBXTargetDependency": "PBXTargetDependency section",
        "XCBuildConfiguration": "XCBuildConfiguration section",
        "XCConfigurationList": "XCConfigurationList section",
    }

    for isa, uuids in sections.items():
        name = section_names.get(isa, f"{isa} section")
        lines.append(f"/* Begin {name} */")
        for uid in uuids:
            obj = objs[uid]
            # For file references, add a comment with the file name
            comment = ""
            if obj.get("path") and isa in ("PBXFileReference", "PBXBuildFile"):
                comment = _pbx_comment(obj["path"])
            lines.append(f"\t\t{uid}{comment} = {_pbx_inline_dict(obj)};")
        lines.append(f"/* End {name} */")
        lines.append("")

    lines.append("\t};")
    lines.append(f"\trootObject = {ROOT_OBJ} /* Project object */;")
    lines.append("}")
    return "\n".join(lines) + "\n"


# ── Generate objects ───────────────────────────────────────────────────────
def gen_objects():
    objs = OrderedDict()

    # -- File references --
    for rel, _, _ in app_files:
        fid = _file_id(rel)
        objs[fid] = {
            "isa": "PBXFileReference",
            "lastKnownFileType": "sourcecode.swift",
            "path": str(Path(rel).relative_to("Sources/SovereignMac")),
            "sourceTree": "<group>",
        }

    for rel, _, _ in test_files:
        fid = _file_id(rel)
        objs[fid] = {
            "isa": "PBXFileReference",
            "lastKnownFileType": "sourcecode.swift",
            "path": str(Path(rel).relative_to("Tests/SovereignMacTests")),
            "sourceTree": "<group>",
        }

    # Info.plist & entitlements — handled via build settings, not build phases
    objs[INFO_PLIST_REF] = {
        "isa": "PBXFileReference",
        "lastKnownFileType": "text.plist.xml",
        "path": "Info.plist",
        "sourceTree": "<group>",
    }
    objs[ENTITLEMENTS_REF] = {
        "isa": "PBXFileReference",
        "lastKnownFileType": "text.plist.entitlements",
        "path": "SovereignMac.entitlements",
        "sourceTree": "<group>",
    }

    objs[APP_PROD_REF] = {
        "isa": "PBXFileReference",
        "explicitFileType": "wrapper.application",
        "includeInIndex": "0",
        "path": "Sovereign.app",
        "sourceTree": "BUILT_PRODUCTS_DIR",
    }
    objs[TEST_PROD_REF] = {
        "isa": "PBXFileReference",
        "explicitFileType": "wrapper.cfbundle",
        "includeInIndex": "0",
        "path": "SovereignMacTests.xctest",
        "sourceTree": "BUILT_PRODUCTS_DIR",
    }

    # -- Build files --
    for rel, _, _ in app_files:
        objs[_build_id(rel)] = {"isa": "PBXBuildFile", "fileRef": _file_id(rel)}

    for rel, _, _ in test_files:
        objs[_build_id(rel)] = {"isa": "PBXBuildFile", "fileRef": _file_id(rel)}


    # -- Groups --
    def make_group(tree, name=None, path=None):
        gid = _next_id()
        children = []
        for relpath, _ in tree["files"]:
            children.append(_file_id(relpath))
        for subname, subtree in tree["subs"].items():
            sub_id, _ = make_group(subtree, name=subname)
            children.append(sub_id)
        entry = {"isa": "PBXGroup", "children": children, "sourceTree": "<group>"}
        if name:
            entry["name"] = name
        if path:
            entry["path"] = path
        objs[gid] = entry
        return gid, children

    app_tree = build_tree(app_files)
    app_group_id, app_children = make_group(app_tree, name="SovereignMac", path="Sources/SovereignMac")
    app_children.append(INFO_PLIST_REF)
    app_children.append(ENTITLEMENTS_REF)
    objs[app_group_id]["children"] = app_children

    test_tree = build_tree(test_files)
    test_group_id, test_children = make_group(test_tree, name="SovereignMacTests", path="Tests/SovereignMacTests")
    objs[test_group_id]["children"] = test_children

    objs[PRODUCTS_GROUP] = {
        "isa": "PBXGroup",
        "children": [APP_PROD_REF, TEST_PROD_REF],
        "name": "Products",
        "sourceTree": "<group>",
    }

    objs[MAIN_GROUP] = {
        "isa": "PBXGroup",
        "children": [app_group_id, test_group_id, PRODUCTS_GROUP],
        "sourceTree": "<group>",
    }

    # -- Build phases --
    objs[APP_SRC_PHASE] = {
        "isa": "PBXSourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": [_build_id(rel) for rel, _, _ in app_files],
        "runOnlyForDeploymentPostprocessing": 0,
    }
    objs[APP_FRM_PHASE] = {
        "isa": "PBXFrameworksBuildPhase",
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0,
    }
    objs[APP_RES_PHASE] = {
        "isa": "PBXResourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0,
    }

    objs[TEST_SRC_PHASE] = {
        "isa": "PBXSourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": [_build_id(rel) for rel, _, _ in test_files],
        "runOnlyForDeploymentPostprocessing": 0,
    }
    objs[TEST_FRM_PHASE] = {
        "isa": "PBXFrameworksBuildPhase",
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0,
    }
    objs[TEST_RES_PHASE] = {
        "isa": "PBXResourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0,
    }

    # -- Target dependency --
    objs[PROXY_ID] = {
        "isa": "PBXContainerItemProxy",
        "containerPortal": ROOT_OBJ,
        "proxyType": 1,
        "remoteGlobalIDString": APP_TARGET,
        "remoteInfo": "Sovereign",
    }
    objs[APP_DEP] = {
        "isa": "PBXTargetDependency",
        "target": APP_TARGET,
        "targetProxy": PROXY_ID,
    }

    # -- Targets --
    objs[APP_TARGET] = {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": APP_CFG_LIST,
        "buildPhases": [APP_SRC_PHASE, APP_FRM_PHASE, APP_RES_PHASE],
        "buildRules": [],
        "dependencies": [],
        "name": "Sovereign",
        "productName": "Sovereign",
        "productReference": APP_PROD_REF,
        "productType": "com.apple.product-type.application",
    }
    objs[TEST_TARGET] = {
        "isa": "PBXNativeTarget",
        "buildConfigurationList": TEST_CFG_LIST,
        "buildPhases": [TEST_SRC_PHASE, TEST_FRM_PHASE, TEST_RES_PHASE],
        "buildRules": [],
        "dependencies": [APP_DEP],
        "name": "SovereignMacTests",
        "productName": "SovereignMacTests",
        "productReference": TEST_PROD_REF,
        "productType": "com.apple.product-type.bundle.unit-test",
    }

    # -- Configuration lists --
    objs[APP_CFG_LIST] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [APP_DBG_CFG, APP_REL_CFG],
        "defaultConfigurationIsVisible": 0,
        "defaultConfigurationName": "Release",
    }
    objs[TEST_CFG_LIST] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [TEST_DBG_CFG, TEST_REL_CFG],
        "defaultConfigurationIsVisible": 0,
        "defaultConfigurationName": "Release",
    }
    objs[PROJ_CFG_LIST] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": [PROJ_DBG_CFG, PROJ_REL_CFG],
        "defaultConfigurationIsVisible": 0,
        "defaultConfigurationName": "Release",
    }

    # -- Build configurations --
    app_base = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CODE_SIGN_ENTITLEMENTS": "Sources/SovereignMac/SovereignMac.entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "COMBINE_HIDPI_IMAGES": "YES",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": "",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "YES",
        "INFOPLIST_FILE": "Sources/SovereignMac/Info.plist",
        "INFOPLIST_KEY_LSUIElement": "YES",
        "INFOPLIST_KEY_NSHumanReadableCopyright": "",
        "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.kylaan.sovereign",
        "PRODUCT_NAME": "Sovereign",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
    }

    objs[APP_DBG_CFG] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": {**app_base, **{
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_TESTABILITY": "YES",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
        }},
        "name": "Debug",
    }
    objs[APP_REL_CFG] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": {**app_base, **{
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
            "ENABLE_NS_ASSERTIONS": "NO",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
        }},
        "name": "Release",
    }

    test_base = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CODE_SIGN_STYLE": "Automatic",
        "GENERATE_INFOPLIST_FILE": "YES",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.kylaan.sovereign.tests",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "SWIFT_VERSION": "5.0",
    }

    objs[TEST_DBG_CFG] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": {**test_base, **{
            "BUNDLE_LOADER": "$(TEST_HOST)",
            "DEBUG_INFORMATION_FORMAT": "dwarf",
            "ENABLE_TESTABILITY": "YES",
            "GCC_OPTIMIZATION_LEVEL": "0",
            "ONLY_ACTIVE_ARCH": "YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
            "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Sovereign.app/Contents/MacOS/Sovereign",
        }},
        "name": "Debug",
    }
    objs[TEST_REL_CFG] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": {**test_base, **{
            "BUNDLE_LOADER": "$(TEST_HOST)",
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
            "ENABLE_NS_ASSERTIONS": "NO",
            "SWIFT_COMPILATION_MODE": "wholemodule",
            "SWIFT_OPTIMIZATION_LEVEL": "-O",
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Sovereign.app/Contents/MacOS/Sovereign",
        }},
        "name": "Release",
    }

    proj_base = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
        "MACOSX_DEPLOYMENT_TARGET": "14.0",
        "SDKROOT": "macosx",
        "SWIFT_VERSION": "5.0",
    }

    objs[PROJ_DBG_CFG] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": dict(proj_base),
        "name": "Debug",
    }
    objs[PROJ_REL_CFG] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": dict(proj_base),
        "name": "Release",
    }

    # -- Project root --
    objs[ROOT_OBJ] = {
        "isa": "PBXProject",
        "attributes": {
            "BuildIndependentTargetsInParallel": "YES",
            "LastSwiftUpdateCheck": "1620",
            "LastUpgradeCheck": "1620",
            "TargetAttributes": {
                APP_TARGET: {"CreatedOnToolsVersion": "16.2"},
                TEST_TARGET: {"CreatedOnToolsVersion": "16.2", "TestTargetID": APP_TARGET},
            },
        },
        "buildConfigurationList": PROJ_CFG_LIST,
        "compatibilityVersion": "Xcode 15.0",
        "developmentRegion": "en",
        "hasScannedForEncodings": 0,
        "knownRegions": ["en", "Base", "zh-Hans"],
        "mainGroup": MAIN_GROUP,
        "productRefGroup": PRODUCTS_GROUP,
        "projectDirPath": "",
        "projectRoot": "",
        "targets": [APP_TARGET, TEST_TARGET],
    }

    return objs


# ── Static files ───────────────────────────────────────────────────────────
INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>Sovereign</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Kylaan. All rights reserved.</string>
</dict>
</plist>
"""

ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
"""


# ── Scheme template ─────────────────────────────────────────────────────────
SCHEME_TEMPLATE = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1620"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{APP_TARGET}"
               BuildableName = "Sovereign.app"
               BlueprintName = "Sovereign"
               ReferencedContainer = "container:Sovereign.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "NO"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TEST_TARGET}"
               BuildableName = "SovereignMacTests.xctest"
               BlueprintName = "SovereignMacTests"
               ReferencedContainer = "container:Sovereign.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TEST_TARGET}"
               BuildableName = "SovereignMacTests.xctest"
               BlueprintName = "SovereignMacTests"
               ReferencedContainer = "container:Sovereign.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{APP_TARGET}"
            BuildableName = "Sovereign.app"
            BlueprintName = "Sovereign"
            ReferencedContainer = "container:Sovereign.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{APP_TARGET}"
            BuildableName = "Sovereign.app"
            BlueprintName = "Sovereign"
            ReferencedContainer = "container:Sovereign.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''


# ── Main ───────────────────────────────────────────────────────────────────
def main():
    print("Generating Xcode project...")

    XCODEPROJ.mkdir(exist_ok=True)

    objs = gen_objects()
    pbxproj = serialize(objs)
    (XCODEPROJ / "project.pbxproj").write_text(pbxproj)
    print(f"  ✓ project.pbxproj ({len(objs)} objects, {len(app_files)} app + {len(test_files)} test sources)")

    (SOURCES_DIR / "Info.plist").write_text(INFO_PLIST)
    print(f"  ✓ Sources/SovereignMac/Info.plist")

    (SOURCES_DIR / "SovereignMac.entitlements").write_text(ENTITLEMENTS)
    print(f"  ✓ Sources/SovereignMac/SovereignMac.entitlements")

    # Write scheme
    scheme_dir = XCODEPROJ / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme_content = SCHEME_TEMPLATE.format(APP_TARGET=APP_TARGET, TEST_TARGET=TEST_TARGET)
    (scheme_dir / "Sovereign.xcscheme").write_text(scheme_content)
    print(f"  ✓ xcshareddata/xcschemes/Sovereign.xcscheme")

    print(f"\nProject ready. Open with:\n  open {XCODEPROJ}")


if __name__ == "__main__":
    main()
