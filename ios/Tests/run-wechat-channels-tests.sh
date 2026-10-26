#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d /tmp/videopick-channels-tests.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
simulator="${1:-booted}"
source_dir=DouyinDownLoad
parser="$source_dir/Services/WeChatChannelsParser.swift"

swiftc "$parser" Tests/WeChatChannelsTests.swift -o "$test_dir/parser"
"$test_dir/parser"
swiftc "$parser" "$source_dir/Services/WeChatChannelsService.swift" Tests/WeChatChannelsServiceTests.swift -o "$test_dir/network"
"$test_dir/network"
swiftc "$source_dir/ViewModels/ClipboardAutoDownloadCandidate.swift" "$source_dir/ViewModels/ClipboardAutomationStartupPolicy.swift" Tests/ClipboardAutoDownloadCandidateTests.swift -o "$test_dir/clipboard"
"$test_dir/clipboard"
echo 'PASS: existing clipboard regression tests'
swiftc "$source_dir/Services/DownloadPlatformClassifier.swift" Tests/XiaohongshuURLDetectionTests.swift -o "$test_dir/xhs"
"$test_dir/xhs"
echo 'PASS: existing Xiaohongshu regression tests'

sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
architecture="$(uname -m)"
sim_flags=(-target "${architecture}-apple-ios17.0-simulator" -sdk "$sdk")
xcrun --sdk iphonesimulator swiftc "${sim_flags[@]}" "$parser" \
    "$source_dir/ViewModels/DouyinDownloadViewModel.swift" \
    "$source_dir/ViewModels/ClipboardAutoDownloadCandidate.swift" \
    "$source_dir/ViewModels/ClipboardAutomationStartupPolicy.swift" \
    "$source_dir/Models/DouyinVideoInfo.swift" "$source_dir/Models/DouyinDownloadError.swift" \
    Tests/WeChatChannelsLoginFlowTests.swift -o "$test_dir/login-flow"
xcrun simctl spawn "$simulator" "$test_dir/login-flow"
xcrun --sdk iphonesimulator swiftc "${sim_flags[@]}" "$parser" \
    "$source_dir/Views/YuanbaoLoginView.swift" Tests/YuanbaoReloginTests.swift -o "$test_dir/relogin"
xcrun simctl spawn "$simulator" "$test_dir/relogin"
