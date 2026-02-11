#!/usr/bin/env python3
"""
LabWC Workspace Helper for Noctalia Shell

This script connects to LabWC's ext-workspace-v1 protocol and outputs
workspace state as JSON for the LabwcService to consume.

Usage:
    labwc-workspace-helper.py [--activate WORKSPACE_ID]

Output format (JSON lines):
    {"type": "state", "workspaces": [...], "groups": [...]}
    {"type": "error", "message": "..."}
"""

import sys
import os
import json
import argparse
import struct
import signal

# Add vendor directory to path
# Script is at: Scripts/python/src/compositor/
# Vendor is at: Scripts/python/vendor/
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VENDOR_DIR = os.path.realpath(os.path.join(SCRIPT_DIR, '..', '..', 'vendor'))
sys.path.insert(0, VENDOR_DIR)

from wayland import protocol as wp
from wayland.client import MakeDisplay, ServerDisconnected, NoXDGRuntimeDir

# Protocol XML paths
PROTOCOLS_DIR = os.path.join(VENDOR_DIR, 'wayland', 'protocols')
EXT_WORKSPACE_XML = os.path.join(PROTOCOLS_DIR, 'ext-workspace-v1.xml')


def find_wayland_xml():
    """Find wayland.xml using XDG_DATA_DIRS"""
    # Get XDG_DATA_DIRS, falling back to standard paths
    xdg_data_dirs = os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share')

    for data_dir in xdg_data_dirs.split(':'):
        wayland_xml = os.path.join(data_dir, 'wayland', 'wayland.xml')
        if os.path.exists(wayland_xml):
            return wayland_xml

    # Fallback to common paths if not found in XDG_DATA_DIRS
    fallback_paths = [
        '/usr/share/wayland/wayland.xml',
        '/usr/local/share/wayland/wayland.xml',
    ]
    for path in fallback_paths:
        if os.path.exists(path):
            return path

    return None


WAYLAND_XML = find_wayland_xml()


class WorkspaceState:
    """Tracks the current state of all workspaces"""

    def __init__(self):
        self.workspaces = {}  # oid -> workspace data
        self.groups = {}  # oid -> group data
        self.outputs = {}  # oid -> output data
        self.pending_activate = None

    def to_json(self):
        """Convert current state to JSON-serializable dict"""
        ws_list = []
        for oid, ws in self.workspaces.items():
            ws_list.append({
                'id': ws.get('id', str(oid)),
                'oid': oid,
                'name': ws.get('name', ''),
                'state': ws.get('state', 0),
                'isActive': bool(ws.get('state', 0) & 1),  # active bit
                'isUrgent': bool(ws.get('state', 0) & 2),  # urgent bit
                'isHidden': bool(ws.get('state', 0) & 4),  # hidden bit
                'coordinates': ws.get('coordinates', []),
                'groupOid': ws.get('group_oid'),
                'capabilities': ws.get('capabilities', 0),
            })

        group_list = []
        for oid, grp in self.groups.items():
            group_list.append({
                'oid': oid,
                'outputs': list(grp.get('outputs', set())),
                'workspaces': list(grp.get('workspaces', set())),
                'capabilities': grp.get('capabilities', 0),
            })

        return {
            'type': 'state',
            'workspaces': ws_list,
            'groups': group_list,
        }


class LabwcWorkspaceClient:
    """Client for LabWC's ext-workspace-v1 protocol"""

    def __init__(self):
        self.state = WorkspaceState()
        self.display = None
        self.registry = None
        self.workspace_manager = None
        self.running = True
        self.ext_workspace_protocol = None

    def output_json(self, data):
        """Output JSON to stdout and flush"""
        print(json.dumps(data), flush=True)

    def output_state(self):
        """Output current workspace state as JSON"""
        self.output_json(self.state.to_json())

    def output_error(self, message):
        """Output error message as JSON"""
        self.output_json({'type': 'error', 'message': message})

    def connect(self):
        """Connect to Wayland display and bind to protocols"""
        try:
            # Load protocols
            base_protocol = wp.Protocol(WAYLAND_XML)
            self.ext_workspace_protocol = wp.Protocol(EXT_WORKSPACE_XML, base_protocol)

            # Create display and connect
            Display = MakeDisplay(base_protocol)
            self.display = Display()

            # Get registry
            self.registry = self.display.get_registry()
            self.registry.dispatcher['global'] = self._on_global
            self.registry.dispatcher['global_remove'] = self._on_global_remove

            # Do initial roundtrip to get globals
            self.display.roundtrip()

            if not self.workspace_manager:
                self.output_error('ext_workspace_manager_v1 not available - LabWC 0.8.3+ required')
                return False

            # Do another roundtrip to get initial workspace state
            self.display.roundtrip()

            return True

        except NoXDGRuntimeDir:
            self.output_error('XDG_RUNTIME_DIR not set')
            return False
        except FileNotFoundError as e:
            self.output_error(f'Protocol file not found: {e}')
            return False
        except Exception as e:
            self.output_error(f'Failed to connect: {e}')
            return False

    def _on_global(self, registry, name, interface, version):
        """Handle registry global event"""
        if interface == 'ext_workspace_manager_v1':
            iface = self.ext_workspace_protocol['ext_workspace_manager_v1']
            self.workspace_manager = registry.bind(name, iface, version)
            self._setup_workspace_manager()
        elif interface == 'wl_output':
            iface = self.ext_workspace_protocol['wl_output']
            output = registry.bind(name, iface, min(version, 4))
            self.state.outputs[output.oid] = {'name': None}
            output.dispatcher['name'] = lambda o, n: self._on_output_name(o, n)
            output.dispatcher['done'] = lambda o: None

    def _on_global_remove(self, registry, name):
        """Handle registry global_remove event"""
        pass

    def _on_output_name(self, output, name):
        """Handle output name event"""
        if output.oid in self.state.outputs:
            self.state.outputs[output.oid]['name'] = name

    def _setup_workspace_manager(self):
        """Setup workspace manager event handlers"""
        self.workspace_manager.dispatcher['workspace_group'] = self._on_workspace_group
        self.workspace_manager.dispatcher['workspace'] = self._on_workspace
        self.workspace_manager.dispatcher['done'] = self._on_done
        self.workspace_manager.dispatcher['finished'] = self._on_finished

    def _on_workspace_group(self, manager, group):
        """Handle new workspace group"""
        self.state.groups[group.oid] = {
            'outputs': set(),
            'workspaces': set(),
            'capabilities': 0,
        }

        group.dispatcher['capabilities'] = lambda g, c: self._on_group_capabilities(g, c)
        group.dispatcher['output_enter'] = lambda g, o: self._on_group_output_enter(g, o)
        group.dispatcher['output_leave'] = lambda g, o: self._on_group_output_leave(g, o)
        group.dispatcher['workspace_enter'] = lambda g, w: self._on_group_workspace_enter(g, w)
        group.dispatcher['workspace_leave'] = lambda g, w: self._on_group_workspace_leave(g, w)
        group.dispatcher['removed'] = lambda g: self._on_group_removed(g)

    def _on_group_capabilities(self, group, capabilities):
        """Handle group capabilities event"""
        if group.oid in self.state.groups:
            self.state.groups[group.oid]['capabilities'] = capabilities

    def _on_group_output_enter(self, group, output):
        """Handle output entering group"""
        if group.oid in self.state.groups and output:
            output_name = self.state.outputs.get(output.oid, {}).get('name', str(output.oid))
            self.state.groups[group.oid]['outputs'].add(output_name)

    def _on_group_output_leave(self, group, output):
        """Handle output leaving group"""
        if group.oid in self.state.groups and output:
            output_name = self.state.outputs.get(output.oid, {}).get('name', str(output.oid))
            self.state.groups[group.oid]['outputs'].discard(output_name)

    def _on_group_workspace_enter(self, group, workspace):
        """Handle workspace entering group"""
        if group.oid in self.state.groups and workspace:
            self.state.groups[group.oid]['workspaces'].add(workspace.oid)
            if workspace.oid in self.state.workspaces:
                self.state.workspaces[workspace.oid]['group_oid'] = group.oid

    def _on_group_workspace_leave(self, group, workspace):
        """Handle workspace leaving group"""
        if group.oid in self.state.groups and workspace:
            self.state.groups[group.oid]['workspaces'].discard(workspace.oid)
            if workspace.oid in self.state.workspaces:
                self.state.workspaces[workspace.oid]['group_oid'] = None

    def _on_group_removed(self, group):
        """Handle group removal"""
        if group.oid in self.state.groups:
            del self.state.groups[group.oid]

    def _on_workspace(self, manager, workspace):
        """Handle new workspace"""
        self.state.workspaces[workspace.oid] = {
            'id': None,
            'name': '',
            'state': 0,
            'coordinates': [],
            'group_oid': None,
            'capabilities': 0,
            'handle': workspace,
        }

        workspace.dispatcher['id'] = lambda w, i: self._on_workspace_id(w, i)
        workspace.dispatcher['name'] = lambda w, n: self._on_workspace_name(w, n)
        workspace.dispatcher['coordinates'] = lambda w, c: self._on_workspace_coordinates(w, c)
        workspace.dispatcher['state'] = lambda w, s: self._on_workspace_state(w, s)
        workspace.dispatcher['capabilities'] = lambda w, c: self._on_workspace_capabilities(w, c)
        workspace.dispatcher['removed'] = lambda w: self._on_workspace_removed(w)

    def _on_workspace_id(self, workspace, id_str):
        """Handle workspace id event"""
        if workspace.oid in self.state.workspaces:
            self.state.workspaces[workspace.oid]['id'] = id_str

    def _on_workspace_name(self, workspace, name):
        """Handle workspace name event"""
        if workspace.oid in self.state.workspaces:
            self.state.workspaces[workspace.oid]['name'] = name

    def _on_workspace_coordinates(self, workspace, coords_bytes):
        """Handle workspace coordinates event"""
        if workspace.oid in self.state.workspaces:
            # Parse array of uint32
            coords = []
            if coords_bytes:
                for i in range(0, len(coords_bytes), 4):
                    if i + 4 <= len(coords_bytes):
                        coords.append(struct.unpack('I', coords_bytes[i:i+4])[0])
            self.state.workspaces[workspace.oid]['coordinates'] = coords

    def _on_workspace_state(self, workspace, state):
        """Handle workspace state event"""
        if workspace.oid in self.state.workspaces:
            self.state.workspaces[workspace.oid]['state'] = state

    def _on_workspace_capabilities(self, workspace, capabilities):
        """Handle workspace capabilities event"""
        if workspace.oid in self.state.workspaces:
            self.state.workspaces[workspace.oid]['capabilities'] = capabilities

    def _on_workspace_removed(self, workspace):
        """Handle workspace removal"""
        if workspace.oid in self.state.workspaces:
            del self.state.workspaces[workspace.oid]

    def _on_done(self, manager):
        """Handle done event - all state updates are complete"""
        self.output_state()

    def _on_finished(self, manager):
        """Handle finished event - manager is being destroyed"""
        self.running = False

    def activate_workspace(self, workspace_id):
        """Request activation of a workspace by ID or name"""
        for oid, ws in self.state.workspaces.items():
            ws_id = ws.get('id') or ws.get('name') or str(oid)
            if ws_id == workspace_id or ws.get('name') == workspace_id:
                handle = ws.get('handle')
                if handle:
                    handle.activate()
                    self.workspace_manager.commit()
                    self.display.flush()
                    return True
        return False

    def run(self, activate_workspace=None):
        """Main event loop"""
        if not self.connect():
            return 1

        # Handle activation request
        if activate_workspace:
            # Do multiple roundtrips to ensure workspace state is populated
            for _ in range(5):
                self.display.roundtrip()
                if self.state.workspaces:
                    break

            if self.activate_workspace(activate_workspace):
                self.display.roundtrip()
            else:
                self.output_error(f'Workspace not found: {activate_workspace}')
            return 0

        # Setup signal handlers
        def handle_signal(signum, frame):
            self.running = False
        signal.signal(signal.SIGTERM, handle_signal)
        signal.signal(signal.SIGINT, handle_signal)

        # Output initial state
        self.output_state()

        # Event loop
        try:
            while self.running:
                self.display.dispatch()
        except ServerDisconnected:
            self.output_error('Server disconnected')
            return 1
        except KeyboardInterrupt:
            pass

        return 0


def main():
    parser = argparse.ArgumentParser(
        description='LabWC workspace helper for Noctalia Shell'
    )
    parser.add_argument(
        '--activate', '-a',
        metavar='WORKSPACE',
        help='Activate a workspace by ID or name and exit'
    )

    args = parser.parse_args()

    # Check for required protocol files
    if not WAYLAND_XML or not os.path.exists(WAYLAND_XML):
        print(json.dumps({
            'type': 'error',
            'message': 'Wayland protocol file not found. Check XDG_DATA_DIRS or install wayland-devel.'
        }), flush=True)
        return 1

    if not os.path.exists(EXT_WORKSPACE_XML):
        print(json.dumps({
            'type': 'error',
            'message': f'ext-workspace protocol file not found: {EXT_WORKSPACE_XML}'
        }), flush=True)
        return 1

    client = LabwcWorkspaceClient()
    return client.run(activate_workspace=args.activate)


if __name__ == '__main__':
    sys.exit(main())
