#!/usr/bin/env python3
"""Generate the checked-in Xcode project with only Python's standard library.
Run after adding/removing Swift files. No build-time project generator is required.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def uid(key):
    return hashlib.sha1(key.encode()).hexdigest()[:24].upper()


def obj(key, isa, **fields):
    ref = uid(key)
    objects[ref] = {"isa": isa, **fields}
    return ref


def quote(value):
    if isinstance(value, list):
        return "(" + ", ".join(quote(v) for v in value) + ")"
    if isinstance(value, dict):
        return "{" + " ".join(f"{k} = {quote(v)};" for k, v in value.items()) + "}"
    return json.dumps(str(value))


files = {}
for path in sorted(ROOT.rglob("*")):
    if any(p.startswith(".") for p in path.relative_to(ROOT).parts):
        continue
    if path.suffix not in {".swift", ".plist", ".entitlements", ".xcconfig", ".xcprivacy"}:
        continue
    rel = path.relative_to(ROOT).as_posix()
    types = {".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements",
             ".xcconfig": "text.xcconfig", ".xcprivacy": "text.xml"}
    files[rel] = obj("file:" + rel, "PBXFileReference", lastKnownFileType=types[path.suffix], path=rel, sourceTree="<group>")

products = {}
APP, WIDGETS, SHARE, TESTS = "Atlas", "AtlasWidgets", "AtlasShare", "AtlasTests"
EXTENSIONS = (WIDGETS, SHARE)
BUNDLE_IDS = {APP: "ing.nikhil.noodle", WIDGETS: "ing.nikhil.noodle.activity",
              SHARE: "ing.nikhil.noodle.share", TESTS: "ing.nikhil.noodle.tests"}
for name, extension, typ in [(APP, "app", "wrapper.application"), (WIDGETS, "appex", "wrapper.app-extension"),
                             (SHARE, "appex", "wrapper.app-extension"), (TESTS, "xctest", "wrapper.cfbundle")]:
    products[name] = obj("product:" + name, "PBXFileReference", explicitFileType=typ, includeInIndex="0", path=f"{name}.{extension}", sourceTree="BUILT_PRODUCTS_DIR")
product_group = obj("products", "PBXGroup", children=list(products.values()), name="Products", sourceTree="<group>")
main_group = obj("main", "PBXGroup", children=[*files.values(), product_group], sourceTree="<group>")

base = {"SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0",
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "CODE_SIGN_STYLE": "Automatic",
        "TARGETED_DEVICE_FAMILY": "1", "MARKETING_VERSION": "0.1.0", "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES"}
project_configs = []
for configuration in ["Debug", "Release"]:
    settings = {**base, "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O",
                "DEBUG_INFORMATION_FORMAT": "dwarf" if configuration == "Debug" else "dwarf-with-dsym"}
    if configuration == "Debug": settings["ENABLE_TESTABILITY"] = "YES"
    project_configs.append(obj("project:" + configuration, "XCBuildConfiguration", buildSettings=settings, name=configuration))
config_list = obj("project:configs", "XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

def dependency(name):
    proxy = obj("proxy:" + name, "PBXContainerItemProxy", containerPortal=uid("project"), proxyType="1", remoteGlobalIDString=uid("target:" + name), remoteInfo=name)
    return obj("dependency:" + name, "PBXTargetDependency", target=uid("target:" + name), targetProxy=proxy)

targets = []
for name in products:
    sources = []
    for path, ref in files.items():
        included = path.startswith(name + "/") or (name != TESTS and path.startswith("Shared/"))
        if included and path.endswith(".swift"):
            sources.append(obj("build:" + name + path, "PBXBuildFile", fileRef=ref))
    source_phase = obj("sources:" + name, "PBXSourcesBuildPhase", buildActionMask="2147483647", files=sources, runOnlyForDeploymentPostprocessing="0")
    frameworks = obj("frameworks:" + name, "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[], runOnlyForDeploymentPostprocessing="0")
    resources = []
    if name == APP:
        resources.append(obj("privacy", "PBXBuildFile", fileRef=files["Atlas/PrivacyInfo.xcprivacy"]))
    resources_phase = obj("resources:" + name, "PBXResourcesBuildPhase", buildActionMask="2147483647", files=resources, runOnlyForDeploymentPostprocessing="0")
    phases = [source_phase, frameworks, resources_phase]
    deps = []
    if name == APP:
        embedded = [obj("embed:" + ext, "PBXBuildFile", fileRef=products[ext], settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
                    for ext in EXTENSIONS]
        phases.append(obj("embed", "PBXCopyFilesBuildPhase", buildActionMask="2147483647", dstPath="", dstSubfolderSpec="13", files=embedded, name="Embed App Extensions", runOnlyForDeploymentPostprocessing="0"))
        deps.extend(dependency(ext) for ext in EXTENSIONS)
    if name == TESTS: deps.append(dependency(APP))
    configs = []
    for configuration in ["Debug", "Release"]:
        settings = {"PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_IDS[name],
                    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks", "SWIFT_EMIT_LOC_STRINGS": "YES"}
        if name == APP:
            settings.update(INFOPLIST_FILE="Config/Atlas-Info.plist", CODE_SIGN_ENTITLEMENTS="Config/Atlas.entitlements")
        elif name in EXTENSIONS:
            settings.update(INFOPLIST_FILE=f"Config/{name}-Info.plist", CODE_SIGN_ENTITLEMENTS=f"Config/{name}.entitlements",
                            APPLICATION_EXTENSION_API_ONLY="YES", SKIP_INSTALL="YES",
                            LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks")
        else:
            settings.update(GENERATE_INFOPLIST_FILE="YES", TEST_HOST=f"$(BUILT_PRODUCTS_DIR)/{APP}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{APP}", BUNDLE_LOADER="$(TEST_HOST)")
        configs.append(obj(name + configuration, "XCBuildConfiguration", buildSettings=settings,
                           baseConfigurationReference=files["Config/" + configuration + ".xcconfig"], name=configuration))
    configuration_list = obj(name + "configs", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible="0", defaultConfigurationName="Release")
    targets.append(obj("target:" + name, "PBXNativeTarget", buildConfigurationList=configuration_list, buildPhases=phases, buildRules=[], dependencies=deps,
                       name=name, productName=name, productReference=products[name], productType={APP: "com.apple.product-type.application", WIDGETS: "com.apple.product-type.app-extension", SHARE: "com.apple.product-type.app-extension", TESTS: "com.apple.product-type.bundle.unit-test"}[name]))
obj("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600", "TargetAttributes": {
        uid("target:" + APP): {"SystemCapabilities": {"com.apple.Push": {"enabled": "1"}, "com.apple.ApplicationGroups.iOS": {"enabled": "1"},
                                                       "com.apple.Keychain": {"enabled": "1"}, "com.apple.BackgroundModes": {"enabled": "1"}}},
        **{uid("target:" + ext): {"SystemCapabilities": {"com.apple.ApplicationGroups.iOS": {"enabled": "1"}, "com.apple.Keychain": {"enabled": "1"}}}
           for ext in EXTENSIONS}}},
    buildConfigurationList=config_list, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings="0", knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=product_group, projectDirPath="", projectRoot="", targets=targets)
project = ROOT / f"{APP}.xcodeproj"
project.mkdir(exist_ok=True)
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n" + "\n".join(f"{key} = {quote(value)};" for key, value in objects.items()) + f"\n }};\n rootObject = {uid('project')};\n}}\n")
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
app_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:" + APP)}" BuildableName="{APP}.app" BlueprintName="{APP}" ReferencedContainer="container:{APP}.xcodeproj"/>'
test_ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target:" + TESTS)}" BuildableName="{TESTS}.xctest" BlueprintName="{TESTS}" ReferencedContainer="container:{APP}.xcodeproj"/>'
(schemes / f"{APP}.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{app_ref}</BuildActionEntry>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{test_ref}</BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{test_ref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{app_ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print("Generated Atlas.xcodeproj (app, widgets and Live Activity, share extension, tests)")
