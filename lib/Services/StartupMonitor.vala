//
// Copyright (C) 2026 Plank Reloaded Developers
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

namespace Plank
{
	/**
	 * Listens on the root window for freedesktop startup-notification messages
	 * (_NET_STARTUP_INFO_BEGIN / _NET_STARTUP_INFO, 20 bytes per client message,
	 * "new:", "change:" and "remove:" with ID=, NAME=, ICON=, WMCLASS=…) and turns
	 * them into signals.
	 */
	public class StartupMonitor : GLib.Object
	{
		public signal void started (string id, string name, string icon, string wm_class);
		public signal void ended (string id);

		static StartupMonitor? instance = null;

		public static unowned StartupMonitor get_default ()
		{
			if (instance == null)
				instance = new StartupMonitor ();
			return instance;
		}

		X.Atom begin_atom;
		X.Atom continue_atom;
		// The message being assembled, per sender window
		Gee.HashMap<ulong, string> buffers = new Gee.HashMap<ulong, string> ();
		// Who sent each "new:" (the launcher's own window): only that sender can end it. The window manager also
		// completes sequences it tracks, and that early "remove:" must not stop the bounce of a still-opening app.
		Gee.HashMap<string, ulong> senders = new Gee.HashMap<string, ulong> ();

		StartupMonitor ()
		{
			begin_atom = Gdk.X11.get_xatom_by_name ("_NET_STARTUP_INFO_BEGIN");
			continue_atom = Gdk.X11.get_xatom_by_name ("_NET_STARTUP_INFO");
			var root = Gdk.get_default_root_window ();
			root.set_events (root.get_events () | Gdk.EventMask.PROPERTY_CHANGE_MASK);
			// global filter: the message carries the launcher's own window id, not the root, so a root-only filter never sees it
			gdk_window_add_filter (null, (Gdk.FilterFunc) xevent_filter);
		}


		[CCode (instance_pos = -1)]
		Gdk.FilterReturn xevent_filter (Gdk.XEvent gdk_xevent, Gdk.Event gdk_event)
		{
			X.Event* xevent = (X.Event*) gdk_xevent;
			if (xevent.type != X.EventType.ClientMessage)
				return Gdk.FilterReturn.CONTINUE;

			var type = xevent.xclient.message_type;
			if (type != begin_atom && type != continue_atom)
				return Gdk.FilterReturn.CONTINUE;
			if (xevent.xclient.format != 8)
				return Gdk.FilterReturn.CONTINUE;

			ulong sender = (ulong) xevent.xclient.window;
			string text = (type == begin_atom || !buffers.has_key (sender)) ? "" : buffers.get (sender);

			var chunk = new StringBuilder ();
			bool complete = false;
			for (int i = 0; i < 20; i++) {
				char c = xevent.xclient.b[i];
				if (c == '\0') {
					complete = true;
					break;
				}
				chunk.append_c (c);
			}
			text += chunk.str;

			if (complete) {
				buffers.unset (sender);
				handle_message (text, sender);
			} else if (text.length > 8192) {
				buffers.unset (sender);
			} else {
				buffers.set (sender, text);
			}

			return Gdk.FilterReturn.CONTINUE;
		}

		/**
		 * Parses «new: ID="x" NAME="y" ICON="z" WMCLASS="c"» (values may be quoted, with backslash escapes).
		 */
		void handle_message (string message, ulong sender)
		{
			debug ("StartupMonitor: %s", message);
			int colon = message.index_of_char (':');
			if (colon < 0)
				return;
			var command = message.substring (0, colon).strip ();
			var fields = new Gee.HashMap<string, string> ();

			var rest = message.substring (colon + 1);
			int i = 0;
			while (i < rest.length) {
				while (i < rest.length && rest[i] == ' ')
					i++;
				int eq = rest.index_of_char ('=', i);
				if (eq < 0)
					break;
				var key = rest.substring (i, eq - i);
				i = eq + 1;
				var value = new StringBuilder ();
				if (i < rest.length && rest[i] == '"') {
					i++;
					while (i < rest.length && rest[i] != '"') {
						if (rest[i] == '\\' && i + 1 < rest.length)
							i++;
						value.append_c (rest[i]);
						i++;
					}
					i++;
				} else {
					while (i < rest.length && rest[i] != ' ') {
						value.append_c (rest[i]);
						i++;
					}
				}
				fields.set (key, value.str);
			}

			var id = fields.has_key ("ID") ? fields.get ("ID") : "";
			if (id == "")
				return;

			if (command == "new") {
				senders.set (id, sender);
				started (id, fields.has_key ("NAME") ? fields.get ("NAME") : "",
				         fields.has_key ("ICON") ? fields.get ("ICON") : "",
				         fields.has_key ("WMCLASS") ? fields.get ("WMCLASS") : "");
			} else if (command == "remove") {
				if (senders.has_key (id) && senders.get (id) != sender) {
					warning ("StartupMonitor: ignoring remove of %s from another sender", id);
					return;
				}
				senders.unset (id);
				ended (id);
			}
		}
	}
}
