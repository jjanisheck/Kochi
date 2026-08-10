#!/usr/bin/env python3
"""Add the `Kochi-iOS` app target to app/Kochi.xcodeproj.

The iOS app compiles the same sources as the macOS app, swapping the entry
point: `KochiApp.swift` (AppKit window + menu-bar item) is replaced by
`KochiApp_iOS.swift`, and `Views/KochiMC1View.swift` is iOS-only.

Idempotent: re-running after the target exists is a no-op.
"""

import os
import re
import sys
from pathlib import Path

# Signing identity is not baked in — nobody should inherit someone else's from a
# checked-out project. Set these in your environment before running, or leave them
# and pick your team in Xcode's Signing & Capabilities afterwards.
#
#   KOCHI_DEVELOPMENT_TEAM=ABCDE12345 KOCHI_BUNDLE_ID=com.you.kochi.ios \
#       python3 scripts/add-ios-target.py
DEVELOPMENT_TEAM = os.environ.get("KOCHI_DEVELOPMENT_TEAM", "")
BUNDLE_ID = os.environ.get("KOCHI_BUNDLE_ID", "com.example.kochiapp.ios")

ROOT = Path(__file__).resolve().parent.parent
PBX = ROOT / "app" / "Kochi.xcodeproj" / "project.pbxproj"

IOS_TARGET = "1B0000020"
IOS_PRODUCT = "1B0000000"
IOS_SOURCES = "1B0000022"
IOS_RESOURCES = "1B0000023"
IOS_FRAMEWORKS = "1B0000019"
IOS_CONFLIST = "1B0000021"
IOS_DEBUG = "1B0000028"
IOS_RELEASE = "1B0000029"

# New source files, added as file references in this run.
MC1_VIEW_REF = "1BMC1V001"
MC1_VIEW_BUILD = "1BMC1V002"
IOS_APP_REF = "1BIOSAPP01"
IOS_APP_BUILD = "1BIOSAPP02"

# macOS-only sources, left out of the iOS target.
MAC_ONLY_SOURCE_COMMENTS = {
    "KochiApp.swift in Sources",          # AppKit @main + menu-bar delegate
    "ContentView.swift in Sources",       # the desktop layout
    "TranscriptionSelfTest.swift in Sources",  # headless CLI self-test
}


def section(text, name):
    start = text.index(f"/* Begin {name} section */")
    end = text.index(f"/* End {name} section */")
    return start, end


def main():
    text = PBX.read_text()

    if IOS_TARGET in text:
        print("Kochi-iOS target already present — nothing to do.")
        return 0

    # ---- 1. map every macOS build file to its fileRef ------------------------
    bf_start, bf_end = section(text, "PBXBuildFile")
    build_files = {}  # buildFileID -> (comment, fileRefID, extra)
    for m in re.finditer(
        r"^\t\t(\S+) /\* (.+?) \*/ = \{isa = PBXBuildFile; fileRef = (\S+)( /\* .*? \*/)?; \};$",
        text[bf_start:bf_end],
        re.M,
    ):
        build_files[m.group(1)] = (m.group(2), m.group(3), m.group(4) or "")

    def phase_ids(phase_id):
        """The build-file IDs listed in a given build phase, in order."""
        block = re.search(
            r"\t\t" + phase_id + r" /\* \w+ \*/ = \{.*?files = \((.*?)\);",
            text,
            re.S,
        ).group(1)
        return re.findall(r"^\t\t\t\t(\S+) /\*", block, re.M)

    mac_sources = phase_ids("1A0000022")
    mac_resources = phase_ids("1A0000023")

    # ---- 2. mint an iOS PBXBuildFile per shared source / resource -----------
    new_build_lines = []
    ios_source_ids = []
    ios_resource_ids = []
    counter = 1

    def mint(orig_id, bucket):
        nonlocal counter
        comment, file_ref, ref_comment = build_files[orig_id]
        new_id = f"1B{counter:06d}I"
        counter += 1
        new_build_lines.append(
            f"\t\t{new_id} /* {comment} */ = {{isa = PBXBuildFile; "
            f"fileRef = {file_ref}{ref_comment}; }};"
        )
        bucket.append((new_id, comment))

    for bid in mac_sources:
        comment = build_files[bid][0]
        if comment in MAC_ONLY_SOURCE_COMMENTS:
            continue
        mint(bid, ios_source_ids)
    for bid in mac_resources:
        mint(bid, ios_resource_ids)

    # The two iOS-only sources.
    new_build_lines.append(
        f"\t\t{MC1_VIEW_BUILD} /* KochiMC1View.swift in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {MC1_VIEW_REF} /* KochiMC1View.swift */; }};"
    )
    new_build_lines.append(
        f"\t\t{IOS_APP_BUILD} /* KochiApp_iOS.swift in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {IOS_APP_REF} /* KochiApp_iOS.swift */; }};"
    )
    ios_source_ids.append((MC1_VIEW_BUILD, "KochiMC1View.swift in Sources"))
    ios_source_ids.append((IOS_APP_BUILD, "KochiApp_iOS.swift in Sources"))

    text = text[:bf_end] + "\n".join(new_build_lines) + "\n" + text[bf_end:]

    # ---- 3. file references -------------------------------------------------
    fr_start, fr_end = section(text, "PBXFileReference")
    new_refs = [
        f'\t\t{MC1_VIEW_REF} /* KochiMC1View.swift */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; name = KochiMC1View.swift; '
        f'path = KochiMC1View.swift; sourceTree = "<group>"; }};',
        f'\t\t{IOS_APP_REF} /* KochiApp_iOS.swift */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; name = KochiApp_iOS.swift; '
        f'path = KochiApp_iOS.swift; sourceTree = "<group>"; }};',
        f'\t\t{IOS_PRODUCT} /* Kochi-iOS.app */ = {{isa = PBXFileReference; '
        f'explicitFileType = wrapper.application; includeInIndex = 0; '
        f'path = "Kochi-iOS.app"; sourceTree = BUILT_PRODUCTS_DIR; }};',
    ]
    text = text[:fr_end] + "\n".join(new_refs) + "\n" + text[fr_end:]

    # ---- 4. groups: show the new sources, and the new product ---------------
    text = text.replace(
        "\t\t\t\t0AF10005000000000000DEFA /* ThemeImage.swift */,\n",
        "\t\t\t\t0AF10005000000000000DEFA /* ThemeImage.swift */,\n"
        f"\t\t\t\t{MC1_VIEW_REF} /* KochiMC1View.swift */,\n",
        1,
    )
    text = text.replace(
        "\t\t\t\t1A0000000 /* Kochi.app */,\n",
        "\t\t\t\t1A0000000 /* Kochi.app */,\n"
        f'\t\t\t\t{IOS_PRODUCT} /* Kochi-iOS.app */,\n',
        1,
    )
    # KochiApp_iOS.swift sits beside KochiApp.swift at the group root.
    text = text.replace(
        "\t\t\t\t1A0000002 /* KochiApp.swift */,\n",
        "\t\t\t\t1A0000002 /* KochiApp.swift */,\n"
        f"\t\t\t\t{IOS_APP_REF} /* KochiApp_iOS.swift */,\n",
        1,
    )

    # ---- 5. build phases ----------------------------------------------------
    def files_block(entries):
        return "".join(f"\t\t\t\t{i} /* {c} */,\n" for i, c in entries)

    fw_start, fw_end = section(text, "PBXFrameworksBuildPhase")
    # No explicit framework links: Swift's module imports auto-link AVFoundation,
    # AVKit, Speech and CoreML on iOS.
    ios_fw = (
        f"\t\t{IOS_FRAMEWORKS} /* Frameworks */ = {{\n"
        "\t\t\tisa = PBXFrameworksBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
    )
    text = text[:fw_end] + ios_fw + text[fw_end:]

    rs_start, rs_end = section(text, "PBXResourcesBuildPhase")
    ios_rs = (
        f"\t\t{IOS_RESOURCES} /* Resources */ = {{\n"
        "\t\t\tisa = PBXResourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"{files_block(ios_resource_ids)}"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
    )
    text = text[:rs_end] + ios_rs + text[rs_end:]

    sr_start, sr_end = section(text, "PBXSourcesBuildPhase")
    ios_sr = (
        f"\t\t{IOS_SOURCES} /* Sources */ = {{\n"
        "\t\t\tisa = PBXSourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"{files_block(ios_source_ids)}"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
    )
    text = text[:sr_end] + ios_sr + text[sr_end:]

    # ---- 6. native target ---------------------------------------------------
    nt_start, nt_end = section(text, "PBXNativeTarget")
    ios_target = (
        f'\t\t{IOS_TARGET} /* Kochi-iOS */ = {{\n'
        "\t\t\tisa = PBXNativeTarget;\n"
        f'\t\t\tbuildConfigurationList = {IOS_CONFLIST} /* Build configuration list for PBXNativeTarget "Kochi-iOS" */;\n'
        "\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{IOS_SOURCES} /* Sources */,\n"
        f"\t\t\t\t{IOS_FRAMEWORKS} /* Frameworks */,\n"
        f"\t\t\t\t{IOS_RESOURCES} /* Resources */,\n"
        "\t\t\t);\n"
        "\t\t\tbuildRules = (\n"
        "\t\t\t);\n"
        "\t\t\tdependencies = (\n"
        "\t\t\t);\n"
        '\t\t\tname = "Kochi-iOS";\n'
        '\t\t\tproductName = "Kochi-iOS";\n'
        f'\t\t\tproductReference = {IOS_PRODUCT} /* Kochi-iOS.app */;\n'
        '\t\t\tproductType = "com.apple.product-type.application";\n'
        "\t\t};\n"
    )
    text = text[:nt_end] + ios_target + text[nt_end:]

    # ---- 7. register the target with the project ----------------------------
    text = text.replace(
        "\t\t\t\t\t1A0000020 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t};\n",
        "\t\t\t\t\t1A0000020 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t};\n"
        f"\t\t\t\t\t{IOS_TARGET} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 27.0;\n\t\t\t\t\t}};\n",
        1,
    )
    text = text.replace(
        "\t\t\ttargets = (\n\t\t\t\t1A0000020 /* KochiApp */,\n\t\t\t);",
        "\t\t\ttargets = (\n\t\t\t\t1A0000020 /* KochiApp */,\n"
        f"\t\t\t\t{IOS_TARGET} /* Kochi-iOS */,\n\t\t\t);",
        1,
    )

    # ---- 8. build configurations -------------------------------------------
    def ios_config(cfg_id, name):
        return (
            f"\t\t{cfg_id} /* {name} */ = {{\n"
            "\t\t\tisa = XCBuildConfiguration;\n"
            "\t\t\tbuildSettings = {\n"
            "\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n"
            "\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;\n"
            "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
            "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
            f"\t\t\t\tDEVELOPMENT_TEAM = \"{DEVELOPMENT_TEAM}\";\n"
            "\t\t\t\tENABLE_PREVIEWS = YES;\n"
            "\t\t\t\tGENERATE_INFOPLIST_FILE = YES;\n"
            "\t\t\t\tINFOPLIST_FILE = KochiApp/Info.plist;\n"
            "\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Kochi;\n"
            "\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;\n"
            "\t\t\t\tINFOPLIST_KEY_UIStatusBarStyle = UIStatusBarStyleDarkContent;\n"
            "\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;\n"
            "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 27.0;\n"
            "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n"
            '\t\t\t\t\t"$(inherited)",\n'
            '\t\t\t\t\t"@executable_path/Frameworks",\n'
            "\t\t\t\t);\n"
            "\t\t\t\tMARKETING_VERSION = 1.0;\n"
            f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};\n"
            '\t\t\t\tPRODUCT_NAME = "Kochi-iOS";\n'
            '\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";\n'
            "\t\t\t\tSUPPORTS_MACCATALYST = NO;\n"
            "\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;\n"
            '\t\t\t\tSWIFT_OBJC_BRIDGING_HEADER = "KochiApp/Kochi-Bridging-Header.h";\n'
            "\t\t\t\tSWIFT_VERSION = 5.0;\n"
            "\t\t\t\tTARGETED_DEVICE_FAMILY = 1;\n"
            "\t\t\t};\n"
            f"\t\t\tname = {name};\n"
            "\t\t};\n"
        )

    bc_start, bc_end = section(text, "XCBuildConfiguration")
    text = (
        text[:bc_end]
        + ios_config(IOS_DEBUG, "Debug")
        + ios_config(IOS_RELEASE, "Release")
        + text[bc_end:]
    )

    cl_start, cl_end = section(text, "XCConfigurationList")
    ios_list = (
        f'\t\t{IOS_CONFLIST} /* Build configuration list for PBXNativeTarget "Kochi-iOS" */ = {{\n'
        "\t\t\tisa = XCConfigurationList;\n"
        "\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{IOS_DEBUG} /* Debug */,\n"
        f"\t\t\t\t{IOS_RELEASE} /* Release */,\n"
        "\t\t\t);\n"
        "\t\t\tdefaultConfigurationIsVisible = 0;\n"
        "\t\t\tdefaultConfigurationName = Release;\n"
        "\t\t};\n"
    )
    text = text[:cl_end] + ios_list + text[cl_end:]

    PBX.write_text(text)
    print(f"Added Kochi-iOS: {len(ios_source_ids)} sources, {len(ios_resource_ids)} resources.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
