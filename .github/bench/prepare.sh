#!/usr/bin/env bash
# Not timed. Same as the Bitrise "Bootstrap + resolve packages" step.
set -eo pipefail
cd "$GITHUB_WORKSPACE"
./bootstrap.sh firefox
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
defaults write com.apple.dt.Xcode ShowBuildOperationDuration YES
xcodebuild -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile \
  -project "$FIREFOX_PROJECT" -scheme "$FIREFOX_SCHEME" -clonedSourcePackagesDirPath "$SPM_DIR"
