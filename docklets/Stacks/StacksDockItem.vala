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

using Plank;

namespace Docky {
  /**
   * La pila en el dock.
   *
   * - El ícono es la carpeta («Display as Folder») o los últimos archivos
   *   apilados («Display as Stack»), y se rehace cuando cambia la carpeta.
   * - El clic abre el contenido como abanico, cuadrícula o lista.
   * - El clic derecho trae el menú del Dock de macOS: Sort by, Display as,
   *   View content as, Options y Open «carpeta», con sus marcas.
   */
  public class StacksDockItem : DockletItem {
    /**
     * En «Automatic», hasta cuántos archivos cabe el abanico; con más, la
     * cuadrícula. macOS decide según el espacio; esto se le parece.
     */
    const int FAN_MAX = 12;

    /**
     * Cuántos archivos se dibujan apilados en el ícono.
     */
    const int STACK_DEPTH = 3;

    Gee.ArrayList<StacksEntry> entries = new Gee.ArrayList<StacksEntry> ();
    FileMonitor? monitor = null;
    uint reload_timer = 0U;
    StacksPopup? popup = null;
    Gtk.Menu? list_menu = null;

    StacksPreferences prefs {
      get { return (StacksPreferences) Prefs; }
    }

    public StacksDockItem.with_dockitem_file (GLib.File file)
    {
      GLib.Object (Prefs: new StacksPreferences.with_file (file));
    }

    construct
    {
      prefs.notify.connect (handle_prefs_changed);
      watch_folder ();
      reload ();
    }

    ~StacksDockItem ()
    {
      prefs.notify.disconnect (handle_prefs_changed);
      stop_watching ();
      if (reload_timer > 0U) {
        GLib.Source.remove (reload_timer);
        reload_timer = 0U;
      }
      close_popups ();
    }

    [CCode (instance_pos = -1)]
    void handle_prefs_changed (GLib.Object o, ParamSpec p) {
      if (p.name == "Folder") {
        watch_folder ();
        reload ();
      } else if (p.name == "StackSortBy" || p.name == "DisplayAs") {
        reload ();
      }
    }

    void watch_folder () {
      stop_watching ();
      try {
        monitor = prefs.get_folder ().monitor_directory (FileMonitorFlags.WATCH_MOVES);
        monitor.changed.connect (handle_folder_changed);
      } catch (Error e) {
        warning ("Stacks: no se puede vigilar '%s': %s", prefs.get_folder ().get_uri (), e.message);
      }
    }

    void stop_watching () {
      if (monitor != null) {
        monitor.changed.disconnect (handle_folder_changed);
        monitor.cancel ();
        monitor = null;
      }
    }

    void handle_folder_changed (File f, File? other, FileMonitorEvent event) {
      // Una descarga dispara muchos eventos seguidos: se espera a que pare.
      if (reload_timer > 0U)
        GLib.Source.remove (reload_timer);
      reload_timer = GLib.Timeout.add (400, () => {
        reload_timer = 0U;
        reload ();
        return false;
      });
    }

    void reload () {
      var folder = prefs.get_folder ();
      entries = StacksEntry.load (folder);
      StacksEntry.sort (entries, prefs.StackSortBy);

      Text = folder.get_basename ();
      Icon = DrawingService.get_icon_from_file (folder) ?? "folder";
      Count = entries.size;
      CountVisible = false;

      reset_icon_buffer ();
    }

    /**
     * «Display as Stack»: los últimos archivos uno encima del otro, el más
     * nuevo arriba, cada uno un poco más arriba que el de abajo. Sin archivos,
     * o con «Display as Folder», el ícono de la carpeta.
     */
    protected override void draw_icon (Surface surface) {
      if (prefs.DisplayAs == StacksDisplayAs.FOLDER || entries.size == 0) {
        base.draw_icon (surface);
        return;
      }

      unowned Cairo.Context cr = surface.Context;
      var size = int.min (surface.Width, surface.Height);
      var depth = int.min (STACK_DEPTH, entries.size);
      var item_size = (int) (size * 0.82);
      var step = (size - item_size) / (double) int.max (1, STACK_DEPTH - 1);

      for (var i = depth - 1; i >= 0; i--) {
        var pixbuf = DrawingService.load_icon (entries[i].icon, item_size, item_size);
        var x = (size - pixbuf.width) / 2.0;
        // El de abajo de la pila (i alto) queda más abajo.
        var y = size - item_size - (depth - 1 - i) * step + (item_size - pixbuf.height) / 2.0;
        Gdk.cairo_set_source_pixbuf (cr, pixbuf, x, y);
        cr.paint ();
      }
    }

    protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time) {
      if (button != PopupButton.LEFT)
        return AnimationType.NONE;

      if (entries.size == 0) {
        open_folder ();
        return AnimationType.BOUNCE;
      }

      var view = prefs.ViewAs;
      if (view == StacksViewAs.AUTOMATIC)
        view = entries.size <= FAN_MAX ? StacksViewAs.FAN : StacksViewAs.GRID;

      if (view == StacksViewAs.LIST)
        show_list ();
      else
        show_popup (view);

      return AnimationType.NONE;
    }

    void show_popup (StacksViewAs view) {
      unowned DockController? controller = get_dock ();
      if (controller == null)
        return;

      close_popups ();
      popup = new StacksPopup (controller, this, prefs.get_folder (), entries,
                               view == StacksViewAs.FAN ? StacksPopupMode.FAN : StacksPopupMode.GRID);
      popup.closed.connect (() => { popup = null; });
      popup.present_over_item ();
    }

    /**
     * «View content as List»: un menú con cada archivo; las carpetas se abren
     * como submenú, como en macOS.
     */
    void show_list () {
      unowned DockController? controller = get_dock ();
      if (controller == null)
        return;

      close_popups ();
      list_menu = new Gtk.Menu ();
      list_menu.attach_to_widget (controller.window, null);
      fill_list_menu (list_menu, entries, 0);
      list_menu.append (new Gtk.SeparatorMenuItem ());
      var open_item = new Gtk.MenuItem.with_label (_("Open in Files"));
      open_item.activate.connect (open_folder);
      list_menu.append (open_item);

      Helpers.popup_docklet_menu (controller, this, list_menu);
    }

    static void fill_list_menu (Gtk.Menu menu, Gee.ArrayList<StacksEntry> items, int level) {
      foreach (var entry in items) {
        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
        box.pack_start (new Gtk.Image.from_pixbuf (DrawingService.load_icon (entry.icon, 16, 16)), false, false, 0);
        var label = new Gtk.Label (entry.name);
        label.xalign = 0;
        label.ellipsize = Pango.EllipsizeMode.MIDDLE;
        label.max_width_chars = 40;
        box.pack_start (label, true, true, 0);

        var item = new Gtk.MenuItem ();
        item.add (box);

        if (entry.is_directory && level < 3) {
          var sub = new Gtk.Menu ();
          var sub_entries = StacksEntry.load (entry.file);
          StacksEntry.sort (sub_entries, StacksSortBy.NAME);
          if (sub_entries.size == 0) {
            var empty = new Gtk.MenuItem.with_label (_("Empty"));
            empty.sensitive = false;
            sub.append (empty);
          } else {
            fill_list_menu (sub, sub_entries, level + 1);
          }
          item.set_submenu (sub);
        } else {
          var file = entry.file;
          item.activate.connect (() => { open_file (file); });
        }

        menu.append (item);
      }
    }

    void close_popups () {
      if (popup != null) {
        popup.close_now ();
        popup = null;
      }
      if (list_menu != null) {
        list_menu.destroy ();
        list_menu = null;
      }
    }

    public static void open_file (GLib.File file) {
      try {
        AppInfo.launch_default_for_uri (file.get_uri (), null);
      } catch (Error e) {
        warning ("Stacks: no se pudo abrir '%s': %s", file.get_uri (), e.message);
      }
    }

    public void open_folder () {
      open_file (prefs.get_folder ());
    }

    /**
     * El menú del clic derecho, el del Dock de macOS (c17), con sus marcas.
     */
    public override Gee.ArrayList<Gtk.MenuItem> get_menu_items () {
      var items = new Gee.ArrayList<Gtk.MenuItem> ();

      items.add (new TitledSeparatorMenuItem.no_line (_("Sort by")));
      add_radio_group (items, {
        _("Name"), _("Date Added"), _("Date Modified"), _("Date Created"), _("Kind")
      }, (int) prefs.StackSortBy, (i) => { prefs.StackSortBy = (StacksSortBy) i; });

      items.add (new TitledSeparatorMenuItem (_("Display as")));
      add_radio_group (items, { _("Folder"), _("Stack") },
                       (int) prefs.DisplayAs, (i) => { prefs.DisplayAs = (StacksDisplayAs) i; });

      items.add (new TitledSeparatorMenuItem (_("View content as")));
      add_radio_group (items, { _("Fan"), _("Grid"), _("List"), _("Automatic") },
                       (int) prefs.ViewAs, (i) => { prefs.ViewAs = (StacksViewAs) i; });

      items.add (new Gtk.SeparatorMenuItem ());

      var options = new Gtk.MenuItem.with_label (_("Options"));
      var options_menu = new Gtk.Menu ();
      var show_in_files = new Gtk.MenuItem.with_label (_("Show in Files"));
      show_in_files.activate.connect (open_folder);
      options_menu.append (show_in_files);
      options.set_submenu (options_menu);
      items.add (options);

      items.add (new Gtk.SeparatorMenuItem ());

      var open_item = new Gtk.MenuItem.with_label (_("Open “%s”").printf (prefs.get_folder ().get_basename ()));
      open_item.activate.connect (open_folder);
      items.add (open_item);

      return items;
    }

    delegate void RadioChosen (int index);

    static void add_radio_group (Gee.ArrayList<Gtk.MenuItem> items, string[] labels, int active, owned RadioChosen chosen) {
      // CheckMenuItem con draw_as_radio: el check de macOS, y no deja dos
      // marcados porque cada uno solo enciende el suyo.
      for (var i = 0; i < labels.length; i++) {
        var item = new Gtk.CheckMenuItem.with_label (labels[i]);
        item.draw_as_radio = true;
        item.active = (i == active);
        var index = i;
        item.toggled.connect (() => {
          if (item.active && index != active)
            chosen (index);
        });
        items.add (item);
      }
    }
  }
}
