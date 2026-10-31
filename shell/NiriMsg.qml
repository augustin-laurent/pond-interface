pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Pond.Screenshot as Screenshot

Singleton {
  id: root

  property var workspaces: []
  property var keyboardLayouts: []
  property int keyboardLayoutIndex: 0
  signal keyboardLayoutSwitched
  property bool overviewOpen: false
  property var dragOrigin: null
  property bool _workspaceLauncherOpen: false
  property var _windows: ({})
  property var _appInfoCache: ({})
  property ListModel workspaceRows: ListModel {}
  property var workspaceModes: ({})
  property bool workspaceDragActive: false
  readonly property bool workspaceModeBusy: !_modesReady || _modeTransition !== null
  property bool _modesReady: false
  property bool _haveWorkspaces: false
  property var _modeTransition: null
  property var _pendingWindowModes: ({})
  property var _modeQueryDone: null
  property var _suppressLauncherWorkspace: null

  function workspaceMode(id) { return workspaceModes[id] === "floating" ? "floating" : "scroll"; }

  function _modeAction(id, floating) {
    return floating ? { MoveWindowToFloating: { id: id } } : { MoveWindowToTiling: { id: id } };
  }

  function _reportWorkspaceModeError(messageId) {
    console.warn("Pond workspace mode:", messageId);
    Quickshell.execDetached(["notify-send", "--app-name=Pond", "--icon=dialog-error",
        qsTrId("pond.workspace_layout"), qsTrId(messageId)]);
  }

  // The socket's filesystem identity distinguishes compositor sessions even if
  // a later compositor reuses the same socket path/PID.
  Process {
    id: modeSession
    command: ["python3", Quickshell.shellDir + "/workspace-mode-session.py",
        Quickshell.env("NIRI_SOCKET"), Quickshell.env("XDG_RUNTIME_DIR")]
    running: true
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const state = JSON.parse(text);
          modeFile.path = state.path;
          root.workspaceModes = state.modes;
          root._modesReady = true;
          if (state.error) root._reportWorkspaceModeError(state.error);
          root._pruneWorkspaceModes();
          root._recompute();
          modeReconcile.restart();
        } catch (error) { console.warn("Loading workspace modes:", error); }
      }
    }
    onExited: {
      if (!root._modesReady) {
        root._modesReady = true;
        root._reportWorkspaceModeError("pond.workspace_layout_restore_failed");
        modeReconcile.restart();
      }
    }
  }

  FileView {
    id: modeFile
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onSaveFailed: root._reportWorkspaceModeError("pond.workspace_layout_save_failed")
  }

  function _saveWorkspaceModes() {
    if (modeFile.path) modeFile.setText(JSON.stringify({ modes: workspaceModes }));
  }

  function _pruneWorkspaceModes() {
    if (!_modesReady || !_haveWorkspaces) return;
    const next = {};
    for (const workspace of workspaces)
      if (workspaceModes[workspace.id] === "floating") next[workspace.id] = "floating";
    if (JSON.stringify(next) !== JSON.stringify(workspaceModes)) {
      workspaceModes = next;
      _saveWorkspaceModes();
    }
  }

  function cycleWorkspaceMode(workspaceId) {
    const workspace = workspaces.find(w => w.id === workspaceId);
    if (!workspace || !workspace.isActive || workspaceModeBusy || workspaceDragActive || dragOrigin || _moveDone)
      return false;
    const floating = workspaceMode(workspaceId) !== "floating";
    const snapshot = Object.values(_windows).filter(w => w.workspaceId === workspaceId)
        .map(w => ({ id: w.id, workspaceId: w.workspaceId, isFloating: w.isFloating }));
    _modeTransition = { workspaceId: workspaceId, floating: floating, snapshot: snapshot };
    const actions = [];
    if (!workspace.isFocused) {
      _suppressLauncherWorkspace = workspaceId;
      launcherSuppression.restart();
      actions.push({ FocusWorkspace: { reference: { Id: workspaceId } } });
    }
    for (const window of snapshot)
      if (window.isFloating !== floating) actions.push(_modeAction(window.id, floating));
    return _move(actions, success => {
      if (!success) { _recoverWorkspaceMode(); return; }
      _queryModeWindows(windows => {
        const transition = _modeTransition;
        if (!windows || !workspaces.some(w => w.id === transition.workspaceId)
            || transition.snapshot.some(before => windows.some(w => w.id === before.id
                && w.workspaceId === transition.workspaceId && w.isFloating !== transition.floating))) {
          _recoverWorkspaceMode();
          return;
        }
        const next = Object.assign({}, workspaceModes);
        if (transition.floating) next[transition.workspaceId] = "floating";
        else delete next[transition.workspaceId];
        workspaceModes = next;
        _modeTransition = null;
        _saveWorkspaceModes();
        _recompute();
        modeReconcile.restart();
      });
    });
  }

  function _recoverWorkspaceMode() {
    _queryModeWindows(windows => {
      const transition = _modeTransition;
      const current = windows || Object.values(_windows);
      const actions = transition.snapshot.filter(before => current.some(w => w.id === before.id
          && w.workspaceId === transition.workspaceId && w.isFloating !== before.isFloating))
          .map(before => _modeAction(before.id, before.isFloating));
      // Try every surviving window, even if one closes during recovery.
      _move(actions, success => {
        _queryModeWindows(restored => {
          _modeTransition = null;
          _reportWorkspaceModeError("pond.workspace_layout_change_failed");
          _recompute();
          modeReconcile.restart();
        });
      }, true);
    });
  }

  function _queryModeWindows(done) {
    _modeQueryDone = done;
    modeQueryTimeout.restart();
    modeQuery.connected = true;
  }

  function _finishModeQuery(windows) {
    const done = _modeQueryDone;
    _modeQueryDone = null;
    modeQueryTimeout.stop();
    modeQuery.connected = false;
    if (windows) {
      // The action socket can finish before the event-stream process delivers
      // its notifications. Use the confirmed snapshot for the next click too.
      const next = {};
      for (const window of windows) {
        const old = _windows[window.id];
        if (!old || old.workspaceId !== window.workspaceId)
          _pendingWindowModes[window.id] = window.workspaceId;
        next[window.id] = window;
      }
      _windows = next;
    }
    if (done) done(windows);
  }

  Socket {
    id: modeQuery
    path: Quickshell.env("NIRI_SOCKET")
    onConnectedChanged: {
      if (connected) { write(JSON.stringify("Windows") + "\n"); flush(); }
      else if (root._modeQueryDone) root._finishModeQuery(null);
    }
    onError: root._finishModeQuery(null)
    parser: SplitParser {
      onRead: line => {
        try {
          const windows = JSON.parse(line).Ok.Windows;
          root._finishModeQuery(Array.isArray(windows) ? windows.map(w => root._mapWindow(w)) : null);
        } catch (error) { root._finishModeQuery(null); }
      }
    }
  }
  Timer { id: modeQueryTimeout; interval: 1500; onTriggered: root._finishModeQuery(null) }
  Timer { id: launcherSuppression; interval: 1500; onTriggered: root._suppressLauncherWorkspace = null }
  Timer { id: modeReconcile; interval: 0; onTriggered: root._applyPendingWindowModes() }
  onWorkspaceDragActiveChanged: if (!workspaceDragActive) modeReconcile.restart()

  function _applyPendingWindowModes() {
    if (workspaceModeBusy || workspaceDragActive || dragOrigin || _moveDone) return;
    const actions = [];
    for (const id of Object.keys(_pendingWindowModes)) {
      const window = _windows[id];
      if (!window || window.workspaceId !== _pendingWindowModes[id]) {
        delete _pendingWindowModes[id];
        continue;
      }
      if (!workspaces.some(w => w.id === window.workspaceId)) continue;
      delete _pendingWindowModes[id];
      const floating = workspaceMode(window.workspaceId) === "floating";
      if (window.isFloating !== floating) actions.push(_modeAction(window.id, floating));
    }
    if (actions.length) _move(actions, success => {
      if (!success) _reportWorkspaceModeError("pond.workspace_layout_window_failed");
    }, true);
  }
  readonly property string focusedOutputName: {
    for (const workspace of workspaces) {
      if (workspace.isFocused)
        return String(workspace.output || "");
    }
    return "";
  }
  function focusWindow(id) {
    Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(id)]);
  }

  function focusWorkspace(index) {
    if (index === undefined || index < 0)
      return;
    Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(index)]);
  }

  function focusWorkspaceById(id) {
    if (workspaceModeBusy || !workspaces.some(w => w.id === id)) return false;
    return _move([{ FocusWorkspace: { reference: { Id: id } } }], success => {});
  }

  function openLauncher(workspaceId) {
    if (workspaceModeBusy) return;
    const workspace = workspaces.find(workspace => workspace.id === workspaceId);
    if (!workspace) return;
    _move(workspace.isFocused ? [] : [{ FocusWorkspace: { reference: { Id: workspaceId } } }], success => {
      if (success) Quickshell.execDetached(["vicinae", "open"]);
    });
  }

  function moveWindow(id, workspaceId, slot, done) {
    if (workspaceModeBusy) return false;
    const actions = _windowMoveActions(id, workspaceId, slot);
    return actions !== null && _move(actions, done);
  }

  function _windowMoveActions(id, workspaceId, slot, floatingOverride) {
    const window = _windows[id];
    if (!window || !workspaces.some(w => w.id === workspaceId))
      return null;
    const actions = [];
    if (window.workspaceId !== workspaceId)
      actions.push({ MoveWindowToWorkspace: { window_id: id,
        reference: { Id: workspaceId }, focus: false } });
    const floating = floatingOverride === undefined ? workspaceMode(workspaceId) === "floating" : floatingOverride;
    if (floating) {
      if (!window.isFloating) actions.push(_modeAction(id, true));
      actions.push({ FocusWindow: { id: id } });
      return actions;
    }
    if (window.isFloating)
      actions.push({ MoveWindowToTiling: { id: id } });
    else if (window.workspaceId === workspaceId && Object.values(_windows).filter(w =>
        w.workspaceId === workspaceId && !w.isFloating
        && _layoutPos(w)[0] === _layoutPos(window)[0]).length > 1)
      actions.push({ ConsumeOrExpelWindowRight: { id: id } });
    actions.push({ FocusWindow: { id: id } }, { MoveColumnToIndex: { index: slot + 1 } });
    return actions;
  }

  function windowExists(id) { return _windows[id] !== undefined; }

  function showWindowOverview(id, done) {
    if (workspaceModeBusy) return false;
    const window = _windows[id];
    const workspace = workspaces.find(w => w.id === window?.workspaceId);
    if (!workspace || dragOrigin || _moveDone) return false;
    dragOrigin = Object.assign({}, window, { workspaceName: workspace.name,
      overviewOpen: overviewOpen, stackSize: Object.values(_windows).filter(w =>
        w.workspaceId === window.workspaceId && !w.isFloating
        && _layoutPos(w)[0] === _layoutPos(window)[0]).length });
    const actions = [{ FocusWindow: { id: id } }];
    // Keep the source workspace available if its last window is previewed elsewhere.
    if (!workspace.name)
      actions.push({ SetWorkspaceName: { workspace: { Id: workspace.id },
        name: "pond-drag-" + Quickshell.processId + "-" + workspace.id } });
    actions.push({ OpenOverview: {} });
    return _move(actions, done);
  }

  function finishWindowDrag(restore, done) {
    const origin = dragOrigin;
    if (!origin) return false;
    const actions = restore && windowExists(origin.id)
        ? _windowMoveActions(origin.id, origin.workspaceId,
            Math.max(0, _layoutPos(origin)[0] - 1), origin.isFloating) : [];
    if (!actions) return false;
    if (restore && windowExists(origin.id)) {
      if (!origin.isFloating && origin.stackSize > 1) {
        actions.push({ ConsumeOrExpelWindowRight: { id: origin.id } });
        for (let row = origin.stackSize; row > _layoutPos(origin)[1]; row--)
          actions.push({ MoveWindowUp: {} });
      }
    }
    if (!origin.workspaceName)
      actions.push({ UnsetWorkspaceName: { reference: { Id: origin.workspaceId } } });
    actions.push(origin.overviewOpen ? { OpenOverview: {} } : { CloseOverview: {} });
    return _move(actions, success => {
      // Preview movements are not independent arrivals; cancellation must also
      // preserve a manually floating/tiled source window's original exception.
      delete _pendingWindowModes[origin.id];
      dragOrigin = null;
      _recompute();
      done(success);
    });
  }

  function moveWorkspace(id, targetId, done) {
    if (workspaceModeBusy) return false;
    const target = workspaces.find(w => w.id === targetId);
    if (!target || !workspaces.some(w => w.id === id && w.output === target.output))
      return false;
    return _move([{ MoveWorkspaceToIndex: { reference: { Id: id }, index: target.idx } }], done);
  }

  property var _moveActions: []
  property var _moveDone: null
  property bool _moveContinueOnError: false
  property bool _moveHadError: false

  function _move(actions, done, continueOnError) {
    if (_moveDone)
      return false;
    _moveActions = actions;
    _moveDone = done;
    _moveContinueOnError = !!continueOnError;
    _moveHadError = false;
    moveTimeout.restart();
    moveSocket.connected = true;
    return true;
  }

  function _nextMoveAction() {
    if (_moveActions.length === 0) {
      _finishMove(!_moveHadError);
      return;
    }
    moveTimeout.restart();
    moveSocket.write(JSON.stringify({ Action: _moveActions.shift() }) + "\n");
    moveSocket.flush();
  }

  function _finishMove(success) {
    const done = _moveDone;
    _moveDone = null;
    _moveActions = [];
    moveTimeout.stop();
    moveSocket.connected = false;
    if (done)
      done(success);
    modeReconcile.restart();
  }

  Socket {
    id: moveSocket
    path: Quickshell.env("NIRI_SOCKET")
    onConnectedChanged: {
      if (connected) root._nextMoveAction();
      else if (root._moveDone) root._finishMove(false);
    }
    onError: root._finishMove(false)
    parser: SplitParser {
      onRead: line => {
        try {
          const reply = JSON.parse(line);
          if (reply.Err && !root._moveContinueOnError) root._finishMove(false);
          else {
            if (reply.Err) root._moveHadError = true;
            root._nextMoveAction();
          }
        } catch (error) { root._finishMove(false); }
      }
    }
  }

  Timer {
    id: moveTimeout
    interval: 1500
    onTriggered: root._finishMove(false)
  }

  function appMatches(appId, appName, desktopEntry) {
    function normalize(value) {
      return String(value || "").toLowerCase().replace(/\.desktop$/, "").replace(/[^a-z0-9]+/g, "");
    }
    const wanted = desktopEntry || appName;
    if (!appId || !wanted) return false;
    const entry = DesktopEntries.heuristicLookup(appId);
    const target = DesktopEntries.heuristicLookup(wanted);
    if (entry && target) return entry.id === target.id;
    return [appId, entry?.id, entry?.name].some(value => normalize(value) === normalize(wanted));
  }

  function focusApp(appName, desktopEntry) {
    const window = Object.values(_windows).find(w => appMatches(w.appId, appName, desktopEntry));
    if (window) focusWindow(window.id);
    return !!window;
  }

  Process {
    id: stream
    command: ["niri", "msg", "-j", "event-stream"]
    running: true
    stdout: SplitParser {
      onRead: line => {
        try {
          root._handleEvent(JSON.parse(line));
        } catch (e) {
          console.log("pond: bad event line:", e);
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim()) console.warn("Pond Niri event stream:", text.trim())
    }
    onExited: restartTimer.start()
  }

  Timer {
    id: restartTimer
    interval: 1500
    onTriggered: stream.running = true
  }

  function _handleEvent(ev) {
    if (ev.KeyboardLayoutsChanged) {
      keyboardLayouts = ev.KeyboardLayoutsChanged.keyboard_layouts.names;
      keyboardLayoutIndex = ev.KeyboardLayoutsChanged.keyboard_layouts.current_idx;
      return;
    } else if (ev.KeyboardLayoutSwitched) {
      keyboardLayoutIndex = ev.KeyboardLayoutSwitched.idx;
      keyboardLayoutSwitched();
      return;
    } else if (ev.ScreenshotCaptured) {
      Screenshot.State.receive(ev.ScreenshotCaptured.path, focusedOutputName);
      return;
    } else if (ev.OverviewOpenedOrClosed) {
      overviewOpen = ev.OverviewOpenedOrClosed.is_open;
    } else if (ev.WorkspacesChanged) {
      const list = ev.WorkspacesChanged.workspaces.map(w => ({
        id: w.id, idx: w.idx, name: w.name || "", output: w.output || "",
        activeWindowId: w.active_window_id,
        isActive: !!w.is_active, isFocused: !!w.is_focused, isUrgent: !!w.is_urgent
      }));
      list.sort((a, b) => {
        const outputOrder = a.output.localeCompare(b.output);
        return outputOrder !== 0 ? outputOrder : a.idx - b.idx;
      });
      workspaces = list;
      _haveWorkspaces = true;
      _pruneWorkspaceModes();
      modeReconcile.restart();
    } else if (ev.WorkspaceActivated) {
      const a = ev.WorkspaceActivated;
      const target = workspaces.find(w => w.id === a.id);
      workspaces = workspaces.map(w => Object.assign({}, w, {
        isActive: target && w.output === target.output ? w.id === a.id : w.isActive,
        isFocused: a.focused ? w.id === a.id : w.isFocused
      }));
      const suppressLauncher = a.id === _suppressLauncherWorkspace;
      if (suppressLauncher && a.focused) {
        _suppressLauncherWorkspace = null;
        launcherSuppression.stop();
      }
      if (a.focused && target && !target.isFocused && !dragOrigin && !overviewOpen
          && !suppressLauncher && !_modeTransition
          && !Object.values(_windows).some(w => w.workspaceId === a.id)) {
        _workspaceLauncherOpen = true;
        Quickshell.execDetached(["vicinae", "open"]);
      }
    } else if (ev.WorkspaceActiveWindowChanged) {
      const a = ev.WorkspaceActiveWindowChanged;
      workspaces = workspaces.map(w => w.id === a.workspace_id
          ? Object.assign({}, w, { activeWindowId: a.active_window_id }) : w);
    } else if (ev.WindowsChanged) {
      const wins = {};
      for (const w of ev.WindowsChanged.windows)
        wins[w.id] = _mapWindow(w);
      _windows = wins;
    } else if (ev.WindowOpenedOrChanged) {
      const w = _mapWindow(ev.WindowOpenedOrChanged.window);
      const old = _windows[w.id];
      if (w.isFocused)
        delete _unread[w.id];
      else if (_isAgent(w) && old && _isWorking(old.title) && !_isWorking(w.title))
        _unread[w.id] = true;
      const wins = Object.assign({}, _windows);
      if (w.isFocused)
        for (const id in wins) wins[id] = Object.assign({}, wins[id], { isFocused: false });
      wins[w.id] = w;
      _windows = wins;
      if (!old || old.workspaceId !== w.workspaceId) {
        _pendingWindowModes[w.id] = w.workspaceId;
        modeReconcile.restart();
      }
    } else if (ev.WindowClosed) {
      const wins = Object.assign({}, _windows);
      delete wins[ev.WindowClosed.id];
      _windows = wins;
    } else if (ev.WindowFocusChanged) {
      const focused = ev.WindowFocusChanged.id;
      delete _unread[focused];
      const wins = {};
      for (const id in _windows)
        wins[id] = Object.assign({}, _windows[id], { isFocused: _windows[id].id === focused });
      _windows = wins;
    } else if (ev.WindowLayoutsChanged) {
      const wins = Object.assign({}, _windows);
      let orderChanged = false;
      for (const ch of ev.WindowLayoutsChanged.changes) {
        const id = Array.isArray(ch) ? ch[0] : ch.id;
        const layout = Array.isArray(ch) ? ch[1] : ch.layout;
        if (!wins[id]) continue;
        const before = _layoutPos(wins[id]);
        const updated = Object.assign({}, wins[id], {layout: layout});
        const after = _layoutPos(updated);
        if (before[0] !== after[0] || before[1] !== after[1]) orderChanged = true;
        wins[id] = updated;
      }
      _windows = wins;
      if (!orderChanged) return;
    } else {
      return;
    }
    const focusedWorkspace = workspaces.find(w => w.isFocused);
    if (_workspaceLauncherOpen && (overviewOpen || (focusedWorkspace
        && Object.values(_windows).some(w => w.workspaceId === focusedWorkspace.id)))) {
      _workspaceLauncherOpen = false;
      Quickshell.execDetached(["vicinae", "close"]);
    }
    _recompute();
  }

  function _mapWindow(w) {
    return {
      id: w.id, workspaceId: w.workspace_id, title: w.title || "",
      isFocused: !!w.is_focused,
      isFloating: w.is_floating, layout: w.layout, appId: w.app_id || ""
    };
  }

  property var _unread: ({})

  // Claude Code titles are "◐ "/"◑ " while working, "✳ " idle; Codex prefixes a
  // braille spinner while working. Fish on Pond has " - ", bash/zsh has "@"
  // & every other kitty title is considered idle Codex.
  // This is obviously a dumb hack. Should fix & add support for more stuff.
  function _isWorking(title) { return /^[\u2800-\u28ff\u25d0\u25d1] /.test(title); }
  // Codex blinks between these markers while input or approval is pending.
  function _needsAttention(title) { return /^\[\s*[!.]\s*\](?:\s|$)/.test(title); }
  function _isAgent(w) {
    return w.appId === "kitty" && w.title !== ""
        && (_needsAttention(w.title) || /^[\u2800-\u28ff\u25d0\u25d1\u2733] /.test(w.title)
            || !/ - \S+$|@/.test(w.title));
  }

  function _appInfo(appId) {
    if (_appInfoCache[appId])
      return _appInfoCache[appId];
    const lower = appId.toLowerCase();
    const entry = appId && (DesktopEntries.heuristicLookup(appId)
           || DesktopEntries.byId(appId)
           || DesktopEntries.byId(lower)
           || DesktopEntries.heuristicLookup(lower));
    const iconName = entry?.icon || lower;
    const info = {
      iconName: iconName,
      iconSource: entry && !Quickshell.hasThemeIcon(iconName) && _hicolorIcon(iconName)
          || Quickshell.iconPath(iconName, "application-x-executable")
    };
    if (entry)
      _appInfoCache[appId] = info;
    return info;
  }

  function _hicolorIcon(name) {
    const dataHome = Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share";
    const dataDirs = (Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":");
    for (const dir of [dataHome, ...dataDirs]) {
      for (const size of ["scalable", "512x512", "256x256", "128x128", "64x64", "48x48"]) {
        const path = dir + "/icons/hicolor/" + size + "/apps/" + name
            + (size === "scalable" ? ".svg" : ".png");
        if (Quickshell.iconPath(path, true))
          return "file://" + path;
      }
    }
    return "";
  }

  function _wsIdxOf(wsId) {
    for (const ws of workspaces)
      if (ws.id === wsId) return ws.idx;
    return 999;
  }

  function _layoutPos(w) {
    return w.layout && w.layout.pos_in_scrolling_layout
      ? w.layout.pos_in_scrolling_layout : [999, 999];
  }

  function _compareWindows(a, b) {
    const ws = _wsIdxOf(a.workspaceId) - _wsIdxOf(b.workspaceId);
    if (ws !== 0) return ws;
    const ap = _layoutPos(a), bp = _layoutPos(b);
    if (ap[0] !== bp[0]) return ap[0] - bp[0];
    if (ap[1] !== bp[1]) return ap[1] - bp[1];
    return a.id - b.id;
  }

  function _recompute() {
    // The drag's source delegate and drop slots must survive live window moves.
    if (dragOrigin) return;
    // Annotate workspace occupancy for the sidebar.
    const occupied = {};
    for (const id in _windows) {
        occupied[_windows[id].workspaceId] = true;
    }
    let changed = false;
    const anno = workspaces.map(w => {
      const has = !!occupied[w.id];
      if (has !== w.hasWindows) changed = true;
      return Object.assign({}, w, { hasWindows: has });
    });
    if (changed) workspaces = anno;

    const list = [];
    for (const id in _windows) {
        list.push(_windows[id]);
    }
    list.sort(_compareWindows);

    const windowsByWorkspace = {};
    for (const w of list) {
      if (!windowsByWorkspace[w.workspaceId])
        windowsByWorkspace[w.workspaceId] = [];
      windowsByWorkspace[w.workspaceId].push(w);
    }

    // Include every occupied workspace and exactly one creation workspace per
    // output. An already-selected empty workspace is the creation row; only
    // append a trailing empty workspace when every selected row is occupied.
    const byOutput = {};
    for (const ws of anno) {
      const outputName = ws.output || "";
      if (!byOutput[outputName])
        byOutput[outputName] = [];
      byOutput[outputName].push(ws);
    }

    const included = {};
    const creationRows = {};
    for (const outputName in byOutput) {
      const outputWorkspaces = byOutput[outputName];
      let anchorIndex = 0;
      let selectedEmpty = null;
      for (const ws of outputWorkspaces) {
        if (ws.hasWindows || ws.isActive || ws.isFocused)
          anchorIndex = Math.max(anchorIndex, ws.idx);
        if (ws.hasWindows || ws.isActive || ws.isFocused)
          included[ws.id] = true;
        if (!ws.hasWindows && (ws.isActive || ws.isFocused)
            && (!selectedEmpty || ws.isFocused))
          selectedEmpty = ws;
      }

      let creationWorkspace = selectedEmpty;
      if (!creationWorkspace) {
        for (const ws of outputWorkspaces) {
          if (!ws.hasWindows && ws.idx > anchorIndex
              && (!creationWorkspace || ws.idx < creationWorkspace.idx))
            creationWorkspace = ws;
        }
      }
      if (!creationWorkspace) {
        for (const ws of outputWorkspaces) {
          if (!ws.hasWindows && !included[ws.id]) {
            creationWorkspace = ws;
            break;
          }
        }
      }
      if (creationWorkspace) {
        included[creationWorkspace.id] = true;
        creationRows[creationWorkspace.id] = true;
      }
    }

    const rows = [];
    const rowOrdinals = {};
    const workspaceNumbers = {};
    for (const ws of anno) {
      if (!included[ws.id])
        continue;

      const wsWindows = windowsByWorkspace[ws.id] || [];
      const windowRecords = [];

      for (const w of wsWindows) {
        const info = _appInfo(w.appId);
        const agent = _isAgent(w);
        windowRecords.push({
          winId: w.id,
          iconName: info.iconName,
          iconSource: agent ? "" : info.iconSource,
          dotState: !agent ? "" : _needsAttention(w.title) ? "attention"
              : _isWorking(w.title) ? "working" : _unread[w.id] ? "unread" : "read",
          loaderVariant: w.id % 4 + 1
        });
      }

      const outputName = ws.output || "";
      const rowOrdinal = rowOrdinals[outputName] || 0;
      rowOrdinals[outputName] = rowOrdinal + 1;
      const creationRow = !!creationRows[ws.id];
      const numberedRow = !creationRow || ws.isActive || ws.isFocused;
      let workspaceNumber = 0;
      if (numberedRow) {
        workspaceNumber = (workspaceNumbers[outputName] || 0) + 1;
        workspaceNumbers[outputName] = workspaceNumber;
      }

      rows.push({
        workspaceId: ws.id,
        workspaceIndex: ws.idx,
        outputName: outputName,
        isActive: !!ws.isActive,
        layoutMode: workspaceMode(ws.id),
        isCreationRow: creationRow,
        outputHasWindows: byOutput[outputName].some(workspace => workspace.hasWindows),
        activeWindowId: ws.activeWindowId ?? -1,
        windowsJson: JSON.stringify(windowRecords),
        sidebarRowOrdinal: rowOrdinal,
        sidebarWorkspaceNumber: workspaceNumber
      });
    }

    _syncModel(workspaceRows, rows, "workspaceId");
  }

  function _syncModel(model, desired, identityKey) {
    for (let i = 0; i < desired.length; i++) {
      const d = desired[i];
      let j = -1;
      for (let s = i; s < model.count; s++) {
        if (model.get(s)[identityKey] === d[identityKey]) { j = s; break; }
      }
      if (j === -1) {
        model.insert(i, d);
        continue;
      }
      if (j !== i)
        model.move(j, i, 1);
      const cur = model.get(i);
      for (const key of Object.keys(d))
        if (cur[key] !== d[key])
          model.setProperty(i, key, d[key]);
    }
    while (model.count > desired.length)
      model.remove(model.count - 1);
  }
}
