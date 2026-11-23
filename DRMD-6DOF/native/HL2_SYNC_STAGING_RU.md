# Abaddon HL2-native source staging

This branch is anchored to GMod/Windows gameplay main d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d and adds ONLY the disjoint native HL2 Source SDK overlay from feat/abaddon-native-flight at 5849463a3d3417a16d3cb98e32f8b13e83557bb9.

This is not a completed port, a validated merged gameplay branch, or a replacement for the second agent's changes. It is a content-preserving staging branch intended for selective integration.

Source is located at DRMD-6DOF/native/hl2, with the related map build helper at DRMD-6DOF/tools/build_native_flightlab.py. Valve SDK binaries are not included; build using the pinned SDK in the source README.

Important: the native-flight branch ALSO contains a divergent reactor line with GMod Lua and maps, which are not merged into this staging branch. The full branch deltas (including reactor files) and exact merge/conflict matrix are shipped in the separate Abaddon-Agent2-HL2-SYNC-2026-11-23.zip release. The second agent MUST merge those changes and its own existing commits independently via the non-destructive sync instructions. Do not cherry-pick the staging commit as proof that integration is finished.

Handoff release: https://github.com/terminaldetector/RayLight-/releases/tag/abaddon-agent2-hl2-sync-2026-11-23
