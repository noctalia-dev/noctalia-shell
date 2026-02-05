"""Wayland protocol client implementation

python-wayland - https://github.com/sde1000/python-wayland
MIT License - Copyright (c) 2016 Stephen Early
"""

from . import protocol as wayland_protocol
import os
import socket
import select
import struct
import array
import io

class ServerDisconnected(Exception):
    """The server disconnected unexpectedly"""
    pass

class NoXDGRuntimeDir(Exception):
    """The XDG_RUNTIME_DIR environment variable is not set"""
    pass

class ProtocolError(Exception):
    """The server sent data that could not be decoded"""
    pass

class UnknownObjectError(Exception):
    """The server sent an event for an object we don't know about"""
    def __init__(self, oid):
        self.oid = oid
    def __str__(self):
        return "UnknownObjectError({})".format(self.oid)

class DisplayError(Exception):
    """The server sent a fatal error event

    This error can be raised during dispatching of the default queue.
    """
    def __init__(self, obj, code, codestr, message):
        self.obj = obj
        self.code = code
        self.codestr = codestr
        self.message = message
    def __str__(self):
        return "DisplayError({}, {} (\"{}\"), {})".format(
            self.obj, self.code, self.codestr, self.message)

class _Display:
    """Additional methods for wl_display interface proxy

    The wl_display proxy class obtained by loading the Wayland
    protocol XML file needs to be augmented with some additional
    methods to function as a full Wayland protocol client.
    """
    def __init__(self, name_or_fd=None):
        self._f = None
        self._oids = iter(range(1, 0xff000000))
        self._reusable_oids = []
        self._default_queue = []
        super(_Display, self).__init__(self, self._get_new_oid(),
                                       self._default_queue, 1)
        if hasattr(name_or_fd, 'fileno'):
            self._f = name_or_fd
            self.log.info("connected to existing fd %d", self._f)
        else:
            xdg_runtime_dir = os.getenv('XDG_RUNTIME_DIR')
            if not xdg_runtime_dir:
                raise NoXDGRuntimeDir()
            if not name_or_fd:
                display = os.getenv('WAYLAND_DISPLAY')
                if not display:
                    display = "wayland-0"
            else:
                display = name_or_fd
            if display.startswith('/'):
                path = display
            else:
                path = os.path.join(xdg_runtime_dir, display)
            self._f = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0)
            self._f.connect(path)
            self.log.info("connected to %s", path)

        self._f.setblocking(0)

        # Partial event left from last read
        self._read_partial_event = b''
        self._incoming_fds = []

        self.objects = {self.oid: self}
        self._send_queue = []

        self.dispatcher['delete_id'] = self._delete_id
        self.silence['delete_id'] = True
        self.dispatcher['error'] = self._error_event

    def __del__(self):
        self.disconnect()

    def disconnect(self):
        """Disconnect from the server.

        Closes the socket.  After calling this method, all further
        calls to this proxy or any other proxies on the connection
        will fail.
        """
        if self._f:
            self._f.close()
            self._f = None

    def get_fd(self):
        """Get the file descriptor number of the server connection.

        This can be used in calls to select(), poll(), etc. to wait
        for events from the server.
        """
        return self._f.fileno()

    def _get_new_oid(self):
        if self._reusable_oids:
            return self._reusable_oids.pop()
        return next(self._oids)

    def _delete_id(self, display, id_):
        self.log.info("server deleted %s", self.objects.get(id_, id_))
        if id_ in self.objects:
            self.objects[id_].oid = None
            del self.objects[id_]
        if id_ < 0xff000000:
            self._reusable_oids.append(id_)

    def _error_event(self, *args):
        objs, (code, message) = args[:-2],args[-2:]
        raise DisplayError(str(objs), str(code), "", str(message))

    def _queue_request(self, r, fds=[]):
        self.log.debug("queueing to send: %s with fds %s", r, fds)
        self._send_queue.append((r, fds))

    def flush(self):
        """Send buffered requests to the display server.

        Will send as many requests as possible to the display server.
        Will not block; if sendmsg() would block, will leave events in
        the queue.

        Returns True if the queue was emptied.
        """
        while self._send_queue:
            b, fds = self._send_queue.pop(0)
            try:
                self._f.sendmsg([b], [(socket.SOL_SOCKET, socket.SCM_RIGHTS,
                                       array.array("i", fds))])
                for fd in fds:
                    os.close(fd)
            except socket.error as e:
                if e.errno == 11:
                    # Would block.  Return the data to the head of the queue
                    # and try again later!
                    self.log.debug("flush would block; returning data to queue")
                    self._send_queue.insert(0, (b, fds))
                    return
                raise
        return True

    def recv(self):
        """Receive as much data as is available.

        Returns True if any data was received.  Will not block.
        """
        data = None
        try:
            fds = array.array("i")
            data, ancdata, msg_flags, address = self._f.recvmsg(
                4096, socket.CMSG_SPACE(16 * fds.itemsize))
            for cmsg_level, cmsg_type, cmsg_data in ancdata:
                if (cmsg_level == socket.SOL_SOCKET and
                    cmsg_type == socket.SCM_RIGHTS):
                    fds.frombytes(cmsg_data[
                        :len(cmsg_data) - (len(cmsg_data) % fds.itemsize)])
            self._incoming_fds.extend(fds)
            if data:
                self._decode(data)
                return True
            else:
                raise ServerDisconnected()
        except socket.error as e:
            if e.errno == 11:
                # No data available; would otherwise block
                return
            raise

    def dispatch(self):
        """Dispatch the default event queue.

        If the queue is empty, block until events are available and
        dispatch them.
        """
        self.flush()
        while not self._default_queue:
            select.select([self._f], [], [])
            self.recv()
        self.dispatch_pending()

    def dispatch_pending(self, queue=None):
        """Dispatch pending events in an event queue.

        If queue is None, dispatches from the default event queue.
        Will not read from the server connection.
        """
        if not queue:
            queue = self._default_queue
        while queue:
            e = queue.pop(0)
            if isinstance(e, Exception):
                raise e
            proxy, event, args = e
            proxy.dispatch_event(event, args)

    def roundtrip(self):
        """Send a sync request to the server and wait for the reply.

        Events are read from the server and dispatched if they are on
        the default event queue.  This call blocks until the "done"
        event on the wl_callback generated by the sync request has
        been dispatched.
        """
        ready = False
        def set_ready(callback, x):
            nonlocal ready
            ready = True
        l = self.sync()
        l.dispatcher['done'] = set_ready
        while not ready:
            self.dispatch()

    def _decode(self, data):
        # There may be partial event data already received; add to it
        # if it's there
        if self._read_partial_event:
            data = self._read_partial_event + data
        while len(data) >= 8:
            oid, sizeop = struct.unpack("II", data[0 : 8])

            size = sizeop >> 16
            op = sizeop & 0xffff

            if len(data) < size:
                self.log.debug("partial event received: %d byte event, "
                               "%d bytes available", size, len(data))
                break

            argdata = io.BytesIO(data[8 : size])
            data = data [size : ]

            obj = self.objects.get(oid, None)
            if obj:
                with argdata:
                    e = obj._unmarshal_event(op, argdata, self._incoming_fds)
                    self.log.debug(
                        "queueing event: %s(%d) %s %s",
                        e[0].interface.name, e[0].oid, e[1].name, e[2])
                    obj.queue.append(e)
            else:
                self._default_queue.append(UnknownObjectError(oid))
        self._read_partial_event = data

def MakeDisplay(protocol):
    """Create a Display class from a Wayland protocol definition

    Args:
        protocol: a wayland.protocol.Protocol instance containing a
        core Wayland protocol definition.

    Returns:
        A Display proxy class built from the specified protocol.
    """
    class Display(_Display, protocol['wl_display'].client_proxy_class):
        pass
    return Display
