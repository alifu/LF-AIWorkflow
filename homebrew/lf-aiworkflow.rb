# Cask template for the alifu/homebrew-tap tap (plan T9.2, T9.3).
# Copy to Casks/lf-aiworkflow.rb in alifu/homebrew-tap. Not notarized: postflight_steps removes the quarantine flag (TD-002).
# Replace the sha256 and version with the output of scripts/build-release.sh (its "cask:" line) after uploading the zip to the GitHub release.
cask "lf-aiworkflow" do
  version "1.0"
  # PLACEHOLDER: replace with the sha256 printed by scripts/build-release.sh for this version.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/alifu/LF-AIWorkflow/releases/download/v#{version}/LF-AIWorkflow-#{version}.zip"
  name "LF-AIWorkflow"
  desc "Notch app that runs AI workflows through Claude Code"
  homepage "https://github.com/alifu/LF-AIWorkflow"

  depends_on macos: :sonoma

  app "LF-AIWorkflow.app"

  # The app is ad-hoc signed and not notarized, so Gatekeeper would block the first launch.
  # {{appdir}} is a DSL template token expanded at install time, not a Ruby method.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/LF-AIWorkflow.app"]
  end

  zap trash: [
    "~/Library/Application Support/LF-AIWorkflow",
    "~/Library/Preferences/com.alifu.LF-AIWorkflow.plist",
  ]
end
