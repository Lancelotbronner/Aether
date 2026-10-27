---
name: xcode-mcp-vcproj-schemes
description: The xcode MCP server now works with Aether's single-file project.xcproj (fixed 2026-10-26); call XcodeListWorkspaces first for the workspaceIdentifier
type: project
category: mcp_experience
keywords:
  - "xcode MCP server schemes"
  - "XcodeListWorkspaces workspaceIdentifier"
  - "project.xcproj virtual schemes"
  - "windowtab workspace identifier"
usage_scenarios:
  - "User asks to build/run/test via the xcode MCP server"
  - "xcode MCP tool reports Unknown workspace identifier"
---

The xcode MCP server (BuildProject, RunProject, XcodeListSchemes, …)
**works** with Aether's single-file `Aether.xcodeproj` (project.xcproj,
Xcode 26+ virtual schemes). Verified 2026-10-26: `XcodeListSchemes`
returns all 6 schemes (Aether active, AetherKit, AetherTests, Cartograph,
CoreAether, Tests).

**Why:** an earlier version (observed 2026-10-12) reported
"The workspace has no schemes" for this project; the server was since
updated by the user.

**How to apply:** the raw project path is *not* accepted as
`workspaceIdentifier` ("Unknown workspace identifier"). First call
`XcodeListWorkspaces` (no args) to get the current identifier (format
`windowtab-<random>` — likely changes when Xcode restarts), then pass it
to other xcode tools. Fall back to
`xcodebuild -project Aether.xcodeproj -scheme Aether -destination 'platform=macOS' build`
only if the MCP tools fail.
