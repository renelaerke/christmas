#!/usr/bin/env python3
"""Generates JuleHygge.xcodeproj (app + "JuleHygge Kamera" camera extension) from the source folders.

The Xcode project is only needed for the camera extension: a system extension must be signed with a
provisioning profile, and Xcode's automatic signing creates those. Re-run this script after adding or
removing source files:  python3 tools/make-xcodeproj.py
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEAM = "87YVYCK9JT"
APP_ID = "dk.julehygge.JuleHygge"
EXT_ID = "dk.julehygge.JuleHygge.Camera"


def uid(name):
    """Stable 24-hex-digit object ID, so regenerating gives the same file."""
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def swift_files(folder):
    return sorted(f for f in os.listdir(os.path.join(ROOT, folder)) if f.endswith(".swift"))


app_sources = swift_files("Sources/JuleHygge")
ext_sources = swift_files("CameraExtension")

objects = []


def obj(oid, body):
    objects.append((oid, body))


# --- files and groups ---------------------------------------------------------------------------
app_file_refs = {f: uid("ref-app-" + f) for f in app_sources}
ext_file_refs = {f: uid("ref-ext-" + f) for f in ext_sources}
for f, r in app_file_refs.items():
    obj(r, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{f}"; sourceTree = "<group>"; }}')
for f, r in ext_file_refs.items():
    obj(r, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{f}"; sourceTree = "<group>"; }}')
for name, kind in [("Info.plist", "text.plist.xml"), ("JuleHygge.entitlements", "text.plist.entitlements")]:
    obj(uid("ref-" + name), f'{{isa = PBXFileReference; lastKnownFileType = {kind}; path = "{name}"; sourceTree = "<group>"; }}')
for name, kind in [("Info.plist", "text.plist.xml"), ("CameraExtension.entitlements", "text.plist.entitlements")]:
    obj(uid("ref-ext-" + name), f'{{isa = PBXFileReference; lastKnownFileType = {kind}; path = "{name}"; sourceTree = "<group>"; }}')

APP_PRODUCT, EXT_PRODUCT = uid("product-app"), uid("product-ext")
obj(APP_PRODUCT, '{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = JuleHygge.app; sourceTree = BUILT_PRODUCTS_DIR; }')
obj(EXT_PRODUCT, f'{{isa = PBXFileReference; explicitFileType = "wrapper.system-extension"; includeInIndex = 0; path = "{EXT_ID}.systemextension"; sourceTree = BUILT_PRODUCTS_DIR; }}')

G_MAIN, G_APP, G_EXT, G_PRODUCTS = uid("group-main"), uid("group-app"), uid("group-ext"), uid("group-products")
obj(G_APP, '{isa = PBXGroup; children = (' + "".join(r + ", " for r in app_file_refs.values()) + '); name = JuleHygge; path = Sources/JuleHygge; sourceTree = "<group>"; }')
obj(G_EXT, '{isa = PBXGroup; children = (' + "".join(r + ", " for r in ext_file_refs.values())
    + uid("ref-ext-Info.plist") + ", " + uid("ref-ext-CameraExtension.entitlements") + ', ); path = CameraExtension; sourceTree = "<group>"; }')
obj(G_PRODUCTS, f'{{isa = PBXGroup; children = ({APP_PRODUCT}, {EXT_PRODUCT}, ); name = Products; sourceTree = "<group>"; }}')
obj(G_MAIN, f'{{isa = PBXGroup; children = ({G_APP}, {G_EXT}, {uid("ref-Info.plist")}, {uid("ref-JuleHygge.entitlements")}, {G_PRODUCTS}, ); sourceTree = "<group>"; }}')

# --- build phases -------------------------------------------------------------------------------
app_build_files = []
for f, r in app_file_refs.items():
    b = uid("build-app-" + f)
    obj(b, f'{{isa = PBXBuildFile; fileRef = {r}; }}')
    app_build_files.append(b)
ext_build_files = []
for f, r in ext_file_refs.items():
    b = uid("build-ext-" + f)
    obj(b, f'{{isa = PBXBuildFile; fileRef = {r}; }}')
    ext_build_files.append(b)
EMBED_BF = uid("build-embed-ext")
obj(EMBED_BF, f'{{isa = PBXBuildFile; fileRef = {EXT_PRODUCT}; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }}')

APP_SOURCES, EXT_SOURCES = uid("phase-app-sources"), uid("phase-ext-sources")
obj(APP_SOURCES, '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + "".join(b + ", " for b in app_build_files) + '); runOnlyForDeploymentPostprocessing = 0; }')
obj(EXT_SOURCES, '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + "".join(b + ", " for b in ext_build_files) + '); runOnlyForDeploymentPostprocessing = 0; }')
EMBED = uid("phase-embed")
obj(EMBED, f'{{isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = "$(SYSTEM_EXTENSIONS_FOLDER_PATH)"; dstSubfolderSpec = 16; files = ({EMBED_BF}, ); name = "Embed System Extensions"; runOnlyForDeploymentPostprocessing = 0; }}')
ICON = uid("phase-icon")
# The icon is drawn beforehand by xcbuild.sh (with the plain Swift Package build): the app built here has a
# restricted entitlement and is killed by macOS if run before it is signed.
icon_script = ('set -e\\nSRC=\\"$PROJECT_DIR/build/JuleHygge.icns\\"\\n'
               'mkdir -p \\"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH\\"\\n'
               'if [ -f \\"$SRC\\" ]; then cp \\"$SRC\\" \\"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/JuleHygge.icns\\"; fi\\n'
               # the one sound file: the recording of geese for the autumn theme (assets/lyd/KILDER.md)
               'cp \\"$PROJECT_DIR/../assets/lyd/gaes-flok.wav\\" \\"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/gaes-flok.wav\\"\\n')
obj(ICON, '{isa = PBXShellScriptBuildPhase; alwaysOutOfDate = 1; buildActionMask = 2147483647; files = (); inputPaths = (); '
    'name = "App icon (drawn by the app)"; outputPaths = (); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; '
    f'shellScript = "{icon_script}"; }}')

# --- targets ------------------------------------------------------------------------------------
common = {
    "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": TEAM, "MACOSX_DEPLOYMENT_TARGET": "14.0",
    "SWIFT_VERSION": "5.0", "ENABLE_HARDENED_RUNTIME": "YES", "GENERATE_INFOPLIST_FILE": "NO", "CODE_SIGN_IDENTITY": '"Apple Development"',
}
app_settings = dict(common, **{
    "PRODUCT_BUNDLE_IDENTIFIER": APP_ID, "PRODUCT_NAME": "JuleHygge", "INFOPLIST_FILE": "Info.plist",
    "CODE_SIGN_ENTITLEMENTS": "JuleHygge.entitlements", "LD_RUNPATH_SEARCH_PATHS": '"@executable_path/../Frameworks"',
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
})
ext_settings = dict(common, **{
    "PRODUCT_BUNDLE_IDENTIFIER": EXT_ID, "PRODUCT_NAME": '"$(PRODUCT_BUNDLE_IDENTIFIER)"', "INFOPLIST_FILE": "CameraExtension/Info.plist",
    "CODE_SIGN_ENTITLEMENTS": "CameraExtension/CameraExtension.entitlements", "SKIP_INSTALL": "YES",
    "LD_RUNPATH_SEARCH_PATHS": '"@executable_path/../Frameworks @executable_path/../../../../Frameworks"',
})
project_settings = {"SDKROOT": "macosx", "ALWAYS_SEARCH_USER_PATHS": "NO", "SWIFT_OPTIMIZATION_LEVEL": '"-O"'}


def config_list(prefix, settings, debug_extra=None):
    ids = []
    for cfg in ["Debug", "Release"]:
        s = dict(settings)
        if cfg == "Debug" and debug_extra:
            s.update(debug_extra)
        body = "".join(f"{k} = {v}; " for k, v in s.items())
        cid = uid(f"cfg-{prefix}-{cfg}")
        obj(cid, f'{{isa = XCBuildConfiguration; buildSettings = {{{body}}}; name = {cfg}; }}')
        ids.append(cid)
    lid = uid(f"cfglist-{prefix}")
    obj(lid, f'{{isa = XCConfigurationList; buildConfigurations = ({ids[0]}, {ids[1]}, ); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
    return lid


APP_T, EXT_T, PROJECT = uid("target-app"), uid("target-ext"), uid("project")
DEP, PROXY = uid("dep-ext"), uid("proxy-ext")
obj(PROXY, f'{{isa = PBXContainerItemProxy; containerPortal = {PROJECT}; proxyType = 1; remoteGlobalIDString = {EXT_T}; remoteInfo = JuleHyggeCamera; }}')
obj(DEP, f'{{isa = PBXTargetDependency; target = {EXT_T}; targetProxy = {PROXY}; }}')
obj(APP_T, f'{{isa = PBXNativeTarget; buildConfigurationList = {config_list("app", app_settings, {"SWIFT_OPTIMIZATION_LEVEL": '"-Onone"'})}; '
    f'buildPhases = ({APP_SOURCES}, {EMBED}, {ICON}, ); buildRules = (); dependencies = ({DEP}, ); name = JuleHygge; '
    f'productName = JuleHygge; productReference = {APP_PRODUCT}; productType = "com.apple.product-type.application"; }}')
obj(EXT_T, f'{{isa = PBXNativeTarget; buildConfigurationList = {config_list("ext", ext_settings)}; buildPhases = ({EXT_SOURCES}, ); '
    f'buildRules = (); dependencies = (); name = JuleHyggeCamera; productName = JuleHyggeCamera; productReference = {EXT_PRODUCT}; '
    f'productType = "com.apple.product-type.system-extension"; }}')
obj(PROJECT, f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 2600; }}; '
    f'buildConfigurationList = {config_list("project", project_settings)}; compatibilityVersion = "Xcode 14.0"; developmentRegion = da; '
    f'hasScannedForEncodings = 0; knownRegions = (da, Base, ); mainGroup = {G_MAIN}; productRefGroup = {G_PRODUCTS}; '
    f'projectDirPath = ""; projectRoot = ""; targets = ({APP_T}, {EXT_T}, ); }}')

out = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n"
for oid, body in sorted(objects):
    out += f"\t\t{oid} = {body};\n"
out += f"\t}};\n\trootObject = {PROJECT};\n}}\n"
os.makedirs(os.path.join(ROOT, "JuleHygge.xcodeproj"), exist_ok=True)
with open(os.path.join(ROOT, "JuleHygge.xcodeproj", "project.pbxproj"), "w") as f:
    f.write(out)
print(f"JuleHygge.xcodeproj: {len(app_sources)} app files, {len(ext_sources)} extension files")
