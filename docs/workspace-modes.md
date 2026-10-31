# Workspace modes

Both the bottom bar and the left sidebar keep the workspace number visible inside a softly rounded badge,
using the website's solid lavender (`#CBA6F7`) for scrolling and lime (`#CEF058`)
for floating, with plum (`#3F1D68`) and black numbers respectively. Clicking an
inactive workspace selects it. Clicking an active workspace toggles its mode.
On another monitor, selection and mode changes target the workspace by its Niri
ID, rather than its monitor-local index.

Switching modes converts every window on that workspace. Returning to scroll
also tiles windows that were already floating before the change. New windows
and windows arriving from another workspace inherit their destination's mode.
Subsequent manual floating/tiling changes remain possible until the next mode
switch or workspace move. Drag previews respect the destination's mode;
cancellation restores the source window's original floating/tiling state.

Mode changes wait for Niri's acknowledgements and a fresh window snapshot before
updating the workspace display. A failed change attempts to restore the previous window states
and displays an error. Repeated clicks and changes during dragging are ignored.

Choices follow workspace IDs through renumbering and monitor moves. They are
saved atomically in `$XDG_RUNTIME_DIR/pond-workspace-modes-<session>.json` and
survive shell restarts. The session key includes the Niri socket's path and
filesystem identity, so a new compositor session starts in scroll even if its
socket path is reused. Deleted workspaces are removed from the saved choices.

This feature currently supports Niri's scrolling and floating modes. Dwindle
and Hyprland support are deferred.

## Layout parity

Both layouts use the shared workspace presentation in `HorizontalMap.qml`;
`Map.qml` selects its vertical configuration for the sidebar. They share mode
badges and switching, ID-based workspace selection, rounded app icons, native
Niri drag previews, add-app controls outside the selection highlight, collapsed
app-count dots, wheel selection, and themed tooltips. Tooltips sit above the
bottom bar and to the right of the sidebar.

The bottom layout shows one expanded workspace row at a time. The sidebar stacks
workspace rows vertically and scrolls when needed, including horizontal scrolling
for long app rows. Its collapsed layout stacks numbered badges with app dots.
The sidebar reserves its normal or compact width once per toggle, while its
transparent surface stays screen-sized through popup and collapse animations.

Wi-Fi, Bluetooth, audio, settings and collapse controls are available in both
layouts. Bottom controls remain in a row; sidebar controls form a row when
expanded and a five-button column when collapsed. New notification previews use
a separate surface beside the clock on the sidebar and above it on the bottom
bar, without expanding the notification summary.
