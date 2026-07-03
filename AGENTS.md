# Git History

- Never amend, rebase, squash, or otherwise rewrite a commit that has been pushed or otherwise left the machine. Once a commit is published, make a new follow-up commit for any fixes.
- It is acceptable to amend small mistakes only while the commit is still purely local and has not been pushed, shared, or used as the basis for a pull request.

# App Build And Run

- For the Poppy macOS app, use `dinggy run --platform macos --project app/Poppy.xcodeproj --scheme Poppy` to build and launch.
- Do not run direct `xcodebuild` commands for normal build/run validation in this repo.
- Do not use AppleScript, `osascript`, or other GUI automation hacks to test window behavior. If runtime window behavior needs verification, ask the user to test it.
