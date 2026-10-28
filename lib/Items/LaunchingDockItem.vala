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
	 * A dock item for an application that has been asked to start (a startup-notification "new:" message)
	 * and has no window yet: it shows the application icon bouncing, like macOS does, until its first
	 * window appears or the launcher says it is done. It gives up at two minutes.
	 */
	public class LaunchingDockItem : DockItem
	{
		const int64 GIVE_UP_US = 120 * 1000000;

		public string StartupId { get; construct; }

		/**
		 * The WM_CLASS (res_class), lower case, of the windows the application will open.
		 */
		public string WmClass { get; construct; }

		public LaunchingDockItem (string startup_id, string name, string icon, string wm_class)
		{
			GLib.Object (Prefs: new DockItemPreferences (), StartupId: startup_id, WmClass: wm_class.down ());
			Text = name;
			if (icon.has_prefix ("/")) {
				try {
					ForcePixbuf = new Gdk.Pixbuf.from_file_at_size (icon, 256, 256);
				} catch (Error e) {
					warning ("LaunchingDockItem: no pude leer el ícono '%s': %s", icon, e.message);
				}
			} else if (icon != "") {
				Icon = icon;
			}
			if (ForcePixbuf == null && Icon == "")
				Icon = "application-x-executable";
		}

		construct
		{
			Indicator = IndicatorState.NONE;
			LaunchBounceStart = GLib.get_monotonic_time ();
		}

		/**
		 * Starts the bounce (to be called once the item is in the dock): the renderer only animates while it is asked to redraw.
		 */
		public void start ()
		{
			LaunchBounceStart = GLib.get_monotonic_time ();
			needs_redraw ();
			// The item is not part of the rendered items until the dock has handled its addition, so the first redraw
			// may find nothing to animate; keep asking while it bounces (the renderer stops its frame clock otherwise).
			Gdk.threads_add_timeout (250, () => {
				if (!is_launching ())
					return false;
				needs_redraw ();
				return true;
			});
		}

		/**
		 * Ends the bounce (the application opened its window or the launcher gave up).
		 */
		public void stop ()
		{
			LaunchBounceStart = 0;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool is_launching ()
		{
			if (LaunchBounceStart == 0)
				return false;
			if (GLib.get_monotonic_time () - LaunchBounceStart > GIVE_UP_US) {
				LaunchBounceStart = 0;
				return false;
			}
			return true;
		}

		/**
		 * {@inheritDoc}
		 */
		protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time)
		{
			return AnimationType.NONE;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool can_be_removed ()
		{
			return false;
		}

		/**
		 * {@inheritDoc}
		 */
		public override bool is_valid ()
		{
			return true;
		}
	}
}
