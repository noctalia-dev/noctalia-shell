"""Wayland protocol parser and wire protocol implementation

python-wayland - https://github.com/sde1000/python-wayland
MIT License - Copyright (c) 2016 Stephen Early
"""

import xml.etree.ElementTree as ET
import struct
import os
import logging

def _description(d):
    assert d.tag == "description"
    return d.text, d.get('summary')

class NullArgumentException(Exception):
    """None was passed where a value was expected"""
    pass

class DeletedProxyException(Exception):
    """A request was made on an object that has already been deleted"""
    pass

class DuplicateInterfaceName(Exception):
    """A duplicate interface name was detected.

    A protocol file specified an interface name that already exists.
    """
    pass

class ClientProxy:
    """Abstract base class for a proxy to an interface.

    Classes are derived from this for each interface in a protocol.
    Instances of these classes correspond to objects in the Wayland
    connection.  Each class has a method for each request defined in
    the interface, and deals with despatching events received for the
    object.

    Useful attributes:

    interface (class attribute): the Interface this class is a proxy
    for

    display: the wl_display this instance is connected to

    oid: the object ID of this instance

    version: the version of this object

    dispatcher: dictionary mapping event names to callback functions

    silence: dictionary of event names that will not be logged
    """

    def __init__(self, display, oid, queue, version):
        self.display = display
        self.oid = oid
        self.queue = queue
        self.version = version
        self.dispatcher = {}
        self.silence = {}
        self.destroyed = False
        self.log = logging.getLogger(__name__ + "." + self.interface.name)

    def _marshal_request(self, request, *args):
        # args is a tuple when called; we make it a list so it's mutable,
        # because args are consumed in the 'for' loop
        args = list(args)
        al = []
        rval = None
        fl = []
        for a in request.args:
            b, r, fds = a.marshal_for_request(args, self)
            al.append(b)
            fl = fl + fds
            rval = rval or r
        assert len(args) == 0
        al = bytes().join(al)
        b = struct.pack('II', self.oid, ((len(al) + 8) << 16) | request.opcode)
        self.display._queue_request(b + al, fl)
        return rval

    def _unmarshal_event(self, opcode, argdata, fd_source):
        event = self.interface.events_by_number[opcode]
        args = []
        for arg in event.args:
            v = arg.unmarshal_from_event(argdata, fd_source, self)
            args.append(v)
        return (self, event, args)

    def set_queue(self, new_queue):
        # Sets the queue for events received from this object
        self.queue = new_queue

    def dispatch_event(self, event, args):
        if self.destroyed:
            self.log.info("ignore   event %s(%d).%s%s on destroyed proxy",
                          self.interface.name,
                          self.oid, event.name, args)
            return
        f = self.dispatcher.get(event.name, None)
        if f:
            if event.name not in self.silence:
                self.log.info("dispatch event %s(%d).%s%s",
                              self.interface.name,
                              self.oid, event.name, args)
            f(self, *args)
        else:
            if event.name not in self.silence:
                self.log.info("ignore   event %s(%d).%s%s",
                              self.interface.name,
                              self.oid, event.name, args)

    def __str__(self):
        return "{}({})".format(self.interface.name, self.oid)

    def __repr__(self):
        return str(self)

class Arg:
    """An argument to a request or event.

    The request or event this argument belongs to is accessible using
    the "parent" attribute.

    Has a name, type, optional description, and optional summary.

    If this argument creates a new object, the interface for the new
    object is accessible as the "interface" attribute.

    If the argument may be null (None), the "allow_null" attribute is
    True.
    """
    def __init__(self, parent, arg):
        self.parent = parent

        self.name = arg.get('name')
        self.type = arg.get('type')

        self.description = None
        self.summary = arg.get('summary', None)
        self.allow_null = (arg.get('allow-null', None) == "true")

        for c in arg:
            if c.tag == "description":
                self.description, self.summary = _description(c)

    def marshal(self, args):
        """Marshal the argument.

        Implement this when marshalling for requests and events is the
        same operation.

        args is the list of arguments still to marshal; this call
        removes the appropriate number of items from args.

        The return value is a tuple of (bytes, optional return value,
        list of fds to send).
        """
        raise RuntimeError

    def unmarshal(self, argdata, fd_source):
        """Unmarshal the argument.

        Implement this when unmarshalling from requests and events is
        the same operation.

        argdata is a file-like object providing access to the
        remaining marshalled arguments; this call will consume the
        appropriate number of bytes from this source

        fd_source is an iterator object supplying fds that have been
        received over the connection

        The return value is the value of the argument.
        """
        raise RuntimeError

    def marshal_for_request(self, args, proxy):
        """Marshal the argument

        args is the list of arguments still to marshal; this call
        removes the appropriate number of items from args

        proxy is the interface proxy class instance being used for the
        call.

        The return value is a tuple of (bytes, optional return value,
        list of fds to send)
        """
        return self.marshal(args)

    def unmarshal_from_event(self, argdata, fd_source, proxy):
        """Unmarshal the argument

        argdata is a file-like object providing access to the
        remaining marshalled arguments; this call will consume the
        appropriate number of bytes from this source

        fd_source is an iterator object supplying fds that have been
        received over the connection

        proxy is the interface proxy class instance being used for the
        event.

        The return value is the value of the argument
        """
        return self.unmarshal(argdata, fd_source)

class Arg_int(Arg):
    """Signed 32-bit integer argument"""

    def marshal(self, args):
        v = args.pop(0)
        return struct.pack('i', v), None, []

    def unmarshal(self, argdata, fd_source):
        (v, ) = struct.unpack("i", argdata.read(4))
        return v

class Arg_uint(Arg):
    """Unsigned 32-bit integer argument"""

    def marshal(self, args):
        v = args.pop(0)
        return struct.pack('I', v), None, []

    def unmarshal(self, argdata, fd_source):
        (v, ) = struct.unpack("I", argdata.read(4))
        return v

class Arg_new_id(Arg):
    """Newly created object argument"""

    def __init__(self, parent, arg):
        super(Arg_new_id, self).__init__(parent, arg)
        self.interface = arg.get('interface', None)
        if isinstance(parent, Event):
            assert self.interface

    def marshal_for_request(self, args, proxy):
        nid = proxy.display._get_new_oid()
        if self.interface:
            # The interface type is part of the argument, and the
            # version of the newly created object is the same as the
            # version of the proxy.
            npc = self.parent.interface.protocol[self.interface]\
                                       .client_proxy_class
            version = proxy.version
            b = struct.pack('I', nid)
        else:
            # The interface and version are supplied by the caller,
            # and the argument is marshalled as string,uint32,uint32
            interface = args.pop(0)
            version = args.pop(0)
            npc = interface.client_proxy_class
            iname = interface.name.encode('utf-8')
            parts = (struct.pack('I',len(iname)+1),
                     iname,
                     b'\x00'*(4-(len(iname) % 4)),
                     struct.pack('II',version,nid))
            b = b''.join(parts)
        new_proxy = npc(proxy.display, nid, proxy.display._default_queue,
                        version)
        proxy.display.objects[nid] = new_proxy
        return b, new_proxy, []

    def unmarshal_from_event(self, argdata, fd_source, proxy):
        assert self.interface
        (nid, ) = struct.unpack("I", argdata.read(4))
        npc = self.parent.interface.protocol[self.interface].client_proxy_class
        new_proxy = npc(proxy.display, nid, proxy.display._default_queue,
                        proxy.version)
        proxy.display.objects[nid] = new_proxy
        return new_proxy

class Arg_string(Arg):
    """String argument"""

    def marshal(self, args):
        v = args.pop(0)
        if v is None:
            if self.allow_null:
                return struct.pack('I', 0), None, []
            raise NullArgumentException()
        estr = v.encode('utf-8')
        parts = (struct.pack('I',len(estr)+1),
                 estr,
                 b'\x00'*(4-(len(estr) % 4)))
        return b''.join(parts), None, []

    def unmarshal(self, argdata, fd_source):
        # The length includes the terminating null byte
        (l, ) = struct.unpack("I", argdata.read(4))
        if l == 0:
            return None
        l = l-1
        s = argdata.read(l).decode('utf-8')
        argdata.read(4 - (l % 4))
        return s

class Arg_object(Arg):
    """Existing object argument"""

    def marshal(self, args):
        v = args.pop(0)
        if v:
            oid = v.oid
        else:
            if self.allow_null:
                oid = 0
            else:
                raise NullArgumentException()
        return struct.pack("I", oid), None, []

    def unmarshal_from_event(self, argdata, fd_source, proxy):
        (v, ) = struct.unpack("I", argdata.read(4))
        if v == 0:
            return None
        return proxy.display.objects.get(v, None)

class Arg_fd(Arg):
    """File descriptor argument"""

    def marshal(self, args):
        v = args.pop(0)
        fd = os.dup(v)
        return b'', None, [fd]

    def unmarshal(self, argdata, fd_source):
        return fd_source.pop(0)

class Arg_fixed(Arg):
    """Signed 24.8 decimal number argument"""

    def marshal(self, args):
        v = args.pop(0)
        if isinstance(v, int):
            m = v << 8
        else:
            m = (int(v) << 8) + int((v % 1.0) * 256)
        return struct.pack("i",m), None, []

    def unmarshal(self, argdata, fd_source):
        b = argdata.read(4)
        (m, ) = struct.unpack("i",b)
        return float(m >> 8) + ((m & 0xff) / 256.0)

class Arg_array(Arg):
    """Array argument"""

    def marshal(self, args):
        v = args.pop(0)
        if v is None:
            if self.allow_null:
                return struct.pack('I', 0), None, []
            raise NullArgumentException()
        # v should be bytes
        parts = (struct.pack('I',len(v)),
                 v,
                 b'\x00'*(3 - ((len(v) - 1) % 4)) if len(v) > 0 else b'')
        return b''.join(parts), None, []

    def unmarshal(self, argdata, fd_source):
        (l, ) = struct.unpack("I", argdata.read(4))
        if l == 0:
            return b''
        v = argdata.read(l)
        pad = 3 - ((l - 1) % 4)
        if pad:
            argdata.read(pad)
        return v

def _make_arg(parent, tag):
    t = tag.get("type")
    c = "Arg_" + tag.get("type")
    return globals()[c](parent, tag)

class Request:
    """A request on an interface.

    Requests have a name, optional type (to indicate whether the
    request destroys the object), optional "since version of
    interface", optional description, and optional summary.

    If a request has an argument of type "new_id" then the request
    creates a new object; the Interface for this new object is
    accessible as the "creates" attribute.
    """
    def __init__(self, interface, opcode, request):
        self.interface = interface
        self.opcode = opcode
        assert request.tag == "request"

        self.name = request.get('name')
        self.type = request.get('type', None)
        self.since = int(request.get('since', 1))

        self.is_destructor = (self.type == "destructor")

        self.description = None
        self.summary = None

        self.creates = None

        self.args = []

        for c in request:
            if c.tag == "description":
                self.description, self.summary = _description(c)
            elif c.tag == "arg":
                a = _make_arg(self, c)
                if a.type == "new_id":
                    self.creates = a.interface
                self.args.append(a)

    def __str__(self):
        return "{}.{}".format(self.interface.name,self.name)

    def invoke(self, proxy, *args):
        """Invoke this request on a client proxy."""
        if not proxy.oid:
            proxy.log.warning("request %s on deleted %s proxy",
                              self.name, proxy.interface.name)
            raise DeletedProxyException
        if proxy.destroyed:
            proxy.log.info("request %s.%s%s on destroyed object; ignoring",
                           proxy, self.name, args)
            return
        if proxy.version < self.since:
            proxy.log.error(
                "request %s.%s%s only exists from version %s, but proxy is "
                "version %s", proxy, self.name, args, self.since,
                proxy.version)
            return
        r = proxy._marshal_request(self, *args)
        if r:
            proxy.log.info(
                "request %s.%s%s -> %s", proxy, self.name, args, r)
        else:
            proxy.log.info("request %s.%s%s", proxy, self.name, args)
        if self.is_destructor:
            proxy.destroyed = True
            proxy.log.info(
                "%s proxy destroyed by destructor request %s%s",
                proxy, self.name, args)
        return r

class Event:
    """An event on an interface.

    Events have a number (which depends on the order in which they are
    declared in the protocol XML file), name, optional "since version
    of interface", optional description, optional summary, and a
    number of arguments.
    """
    def __init__(self, interface, event, number):
        self.interface = interface
        assert event.tag == "event"

        self.name = event.get('name')
        self.number = number
        self.since = int(event.get('since', 1))
        self.args = []
        self.description = None
        self.summary = None

        for c in event:
            if c.tag == "description":
                self.description, self.summary = _description(c)
            elif c.tag == "arg":
                self.args.append(_make_arg(self, c))

    def __str__(self):
        return "{}::{}".format(self.interface, self.name)

class Entry:
    """An entry in an enumeration.

    Has a name, integer value, optional description, optional summary,
    and optional "since version of interface".
    """

    def __init__(self, enum, entry):
        self.enum = enum
        assert entry.tag == "entry"

        self.name = entry.get('name')
        self.value = int(entry.get('value'), base=0)
        self.description = None
        self.summary = entry.get('summary', None)
        self.since = int(entry.get('since', 1))

        for c in entry:
            if c.tag == "description":
                self.description, self.summary = _description(c)

class Enum:
    """An enumeration declared in an interface.

    Enumerations have a name, optional "since version of interface",
    option description, optional summary, and a number of entries.

    The entries are accessible by name in the dictionary available
    through the "entries" attribute.  Further, if the Enum instance is
    accessed as a dictionary then if a string argument is used it
    returns the integer value of the corresponding entry, and if an
    integer argument is used it returns the name of the corresponding
    entry.
    """
    def __init__(self, interface, enum):
        self.interface = interface
        assert enum.tag == "enum"

        self.name = enum.get('name')
        self.since = int(enum.get('since', 1))
        self.entries = {}
        self.description = None
        self.summary = None
        self._values = {}
        self._names = {}

        for c in enum:
            if c.tag == "description":
                self.description, self.summary = _description(c)
            elif c.tag == "entry":
                e = Entry(self, c)
                self.entries[e.name] = e
                self._values[e.name] = e.value
                self._names[e.value] = e.name

    def __getitem__(self, i):
        if isinstance(i, int):
            return self._names.get(i)
        return self._values.get(i)

class Interface:
    """A Wayland protocol interface.

    Wayland interfaces have a name and version, plus a number of
    requests, events and enumerations.  Optionally they have a
    description.

    The name and version are accessible as the "name" and "version"
    attributes.

    The requests and enums are accessible as dictionaries as the
    "requests" and "enums" attributes.  The events are accessible by
    name as a dictionary as the "events_by_name" attribute, and by
    number as a list as the "events_by_number" attribute.

    A client proxy class for this interface is available as the
    "client_proxy_class" attribute; instances of this class have
    methods corresponding to the requests, and deal with dispatching
    the events.
    """

    def __init__(self, protocol, interface):
        self.protocol = protocol
        assert interface.tag == "interface"

        self.name = interface.get('name')
        self.version = int(interface.get('version'))
        assert self.version > 0
        self.description = None
        self.summary = None
        self.requests = {}
        self.events_by_name = {}
        self.events_by_number = []
        self.enums = {}

        for c in interface:
            if c.tag == "description":
                self.description, self.summary = _description(c)
            elif c.tag == "request":
                e = Request(self, len(self.requests), c)
                self.requests[e.name] = e
            elif c.tag == "event":
                e = Event(self, c, len(self.events_by_number))
                self.events_by_name[e.name] = e
                self.events_by_number.append(e)
            elif c.tag == "enum":
                e = Enum(self, c)
                self.enums[e.name] = e

        def client_proxy_request(x):
            def call_request(*args):
                return x.invoke(*args)
            return call_request
        d = {
            '__doc__': self.description,
            'interface': self,
        }
        for r in self.requests.values():
            d[r.name] = client_proxy_request(r)
        self.client_proxy_class = type(
            str(self.name + '_client_proxy'), (ClientProxy,), d)

    def __str__(self):
        return self.name

    def __repr__(self):
        return "Interface('{}', {})".format(self.name, self.version)

class Protocol:
    """A Wayland protocol.

    A Wayland connection will often have multiple Wayland protocols
    running over it: the core protocol, plus a number of other
    protocols that add completely new functionality or extend the
    functionality of some other protocol.

    See https://cgit.freedesktop.org/wayland/wayland-protocols for the
    current collection of Wayland protocols.

    This Protocol class corresponds to one protocol XML file.  These
    contain one or more interfaces, which are accessible in this class
    via the "interfaces" attribute which is a dictionary keyed by
    interface name.  Once instantiated this class should be treated as
    immutable, with the only exception being that interfaces of
    "child" protocols that are loaded with this class instance as an
    ancestor will be added to the "interfaces" dictionary.

    As a shortcut, accessing an instance of this class through
    __getitem__ (for example wayland['wl_display']) will access the
    interfaces dictionary.

    The copyright notice from the XML file, if present, is accessible
    as the "copyright" attribute.
    """
    def __init__(self, file, parent=None):
        """Load a Wayland protocol file.

        Args:
            file: a filename or file object containing an XML Wayland
            protocol description

            parent: a Protocol object containing interfaces that are
            referred to by name in the XML protocol description
        """
        tree = ET.parse(file)

        protocol = tree.getroot()
        assert protocol.tag == "protocol"

        self.copyright = None
        if parent:
            self.interfaces = parent.interfaces
        else:
            self.interfaces = {}

        self.name = protocol.get('name')

        for c in protocol:
            if c.tag == "copyright":
                self.copyright = c.text
            elif c.tag == "interface":
                i = Interface(self, c)
                if i.name in self.interfaces:
                    raise DuplicateInterfaceName(i.name)
                self.interfaces[i.name] = i

    def __getitem__(self, x):
        return self.interfaces.__getitem__(x)
