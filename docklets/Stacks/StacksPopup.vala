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
  public enum StacksPopupMode {
    FAN,
    GRID
  }

  /**
   * El contenido de la pila abierto encima de su ícono, como en macOS.
   *
   * FAN: un arco que sube desde el ícono y se curva a la derecha, con el
   * nombre de cada archivo en una pastilla a la izquierda; arriba de todo,
   * «Open in Files» (o cuántos más hay, si no caben).
   *
   * GRID: un panel oscuro translúcido con el nombre de la carpeta arriba,
   * los íconos con su nombre debajo, una flecha que apunta al ícono del dock
   * y «Open in Files» al pie. Si no caben, se desplaza con la rueda.
   *
   * Se cierra con un clic fuera, con Esc o al abrir un archivo. La animación
   * de apertura del abanico no se imita.
   */
  public class StacksPopup : Gtk.Window {
    public signal void closed ();

    const int FAN_ICON = 52;
    const int FAN_STEP = 60;
    const int FAN_MAX = 12;
    const double FAN_RADIUS = 1100.0;
    const int FAN_LABEL_GAP = 10;

    const int GRID_ICON = 64;
    const int GRID_CELL_W = 104;
    const int GRID_CELL_H = 104;
    const int GRID_PAD = 16;
    const int GRID_TITLE_H = 40;
    const int GRID_FOOTER_H = 34;
    const int ARROW = 12;
    const int MARGIN = 8;

    class Cell {
      public StacksEntry? entry;
      public string label;
      public Gdk.Pixbuf icon;
      public Gdk.Rectangle icon_rect;
      public Gdk.Rectangle hit;
      public Gdk.Rectangle label_rect;
    }

    unowned DockController controller;
    unowned DockItem item;
    GLib.File folder;
    Gee.ArrayList<StacksEntry> entries;
    StacksPopupMode mode;

    Gee.ArrayList<Cell> cells = new Gee.ArrayList<Cell> ();
    int hovered = -1;
    int width_px = 0;
    int height_px = 0;
    // Dónde queda el ícono del dock, en coordenadas de la ventana.
    int anchor_x = 0;
    // Cuadrícula: desplazamiento vertical y alto visible del contenido.
    int scroll = 0;
    int max_scroll = 0;
    int grid_view_h = 0;
    Gdk.Rectangle footer_rect;
    bool grabbed = false;
    bool closing = false;

    public StacksPopup (DockController controller, DockItem item, GLib.File folder,
                        Gee.ArrayList<StacksEntry> entries, StacksPopupMode mode) {
      Object (type: Gtk.WindowType.POPUP);
      this.controller = controller;
      this.item = item;
      this.folder = folder;
      this.entries = entries;
      this.mode = mode;

      app_paintable = true;
      decorated = false;
      resizable = false;
      skip_taskbar_hint = true;
      skip_pager_hint = true;
      var visual = get_screen ().get_rgba_visual ();
      if (visual != null)
        set_visual (visual);

      add_events (Gdk.EventMask.POINTER_MOTION_MASK | Gdk.EventMask.BUTTON_PRESS_MASK
                  | Gdk.EventMask.BUTTON_RELEASE_MASK | Gdk.EventMask.SCROLL_MASK
                  | Gdk.EventMask.SMOOTH_SCROLL_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK
                  | Gdk.EventMask.KEY_PRESS_MASK);
    }

    /**
     * Arma el contenido, se pone encima del ícono y toma el puntero y el
     * teclado para saber cuándo se hace clic fuera.
     */
    public void present_over_item () {
      if (mode == StacksPopupMode.FAN)
        layout_fan ();
      else
        layout_grid ();

      set_size_request (width_px, height_px);
      resize (width_px, height_px);

      // El ícono en pantalla: su región en la ventana del dock más la posición
      // de esa ventana.
      unowned PositionManager pm = controller.position_manager;
      var rect = pm.get_hover_region_for_element (item);
      var dock = pm.get_dock_window_region ();
      var icon_center_x = dock.x + rect.x + rect.width / 2;
      var icon_top_y = dock.y + rect.y;

      var monitor = pm.get_monitor_geometry ();
      var x = icon_center_x - anchor_x;
      var y = icon_top_y - height_px - MARGIN;
      // Que no se salga del monitor; la flecha sigue apuntando al ícono.
      var clamped = x.clamp (monitor.x + MARGIN, monitor.x + monitor.width - width_px - MARGIN);
      anchor_x += x - clamped;
      x = clamped;
      move (x, int.max (monitor.y + MARGIN, y));

      show_all ();
      grab_input ();
    }

    void grab_input () {
      var window = get_window ();
      if (window == null)
        return;
      var seat = get_display ().get_default_seat ();
      var status = seat.grab (window, Gdk.SeatCapabilities.ALL, true, null, null, null);
      grabbed = (status == Gdk.GrabStatus.SUCCESS);
      if (!grabbed)
        warning ("Stacks: no se pudo tomar el puntero (%d)", (int) status);
    }

    public void close_now () {
      if (closing)
        return;
      closing = true;
      if (grabbed) {
        get_display ().get_default_seat ().ungrab ();
        grabbed = false;
      }
      closed ();
      destroy ();
    }

    // ── Abanico ─────────────────────────────────────────────────────────────

    void layout_fan () {
      cells.clear ();
      var shown = int.min (FAN_MAX, entries.size);
      var label_w = 0;

      // De abajo (pegado al dock) hacia arriba.
      for (var i = 0; i < shown; i++) {
        var cell = new Cell ();
        cell.entry = entries[i];
        cell.label = entries[i].name;
        cell.icon = DrawingService.load_icon (entries[i].icon, FAN_ICON, FAN_ICON);
        cells.add (cell);
        label_w = int.max (label_w, text_width (cell.label));
      }

      var top = new Cell ();
      top.entry = null;
      top.label = entries.size > shown
                  ? _("%d More in Files").printf (entries.size - shown)
                  : _("Open in Files");
      top.icon = DrawingService.load_icon ("folder-open;;folder;;go-next", FAN_ICON, FAN_ICON);
      cells.add (top);
      label_w = int.max (label_w, text_width (top.label));

      label_w = int.min (label_w + 20, 320);
      var max_dx = (int) Math.ceil (fan_dx ((cells.size - 1) * FAN_STEP));
      var base_x = MARGIN + label_w + FAN_LABEL_GAP;

      width_px = base_x + FAN_ICON + max_dx + MARGIN;
      height_px = cells.size * FAN_STEP + MARGIN;
      anchor_x = base_x + FAN_ICON / 2;

      for (var i = 0; i < cells.size; i++) {
        var cell = cells[i];
        var h = i * FAN_STEP;
        var dx = (int) Math.round (fan_dx (h));
        var icon_x = base_x + dx;
        var icon_y = height_px - FAN_STEP - h + (FAN_STEP - FAN_ICON) / 2;
        cell.icon_rect = { icon_x, icon_y, FAN_ICON, FAN_ICON };

        var lw = int.min (text_width (cell.label) + 20, label_w);
        cell.label_rect = { icon_x - FAN_LABEL_GAP - lw, icon_y + FAN_ICON / 2 - 12, lw, 24 };
        cell.hit = { cell.label_rect.x, icon_y, icon_x + FAN_ICON - cell.label_rect.x, FAN_ICON };
      }
    }

    /**
     * Cuánto se corre a la derecha un ícono del abanico a una altura dada:
     * un arco de círculo grande, como el de macOS.
     */
    static double fan_dx (double h) {
      return FAN_RADIUS - Math.sqrt (FAN_RADIUS * FAN_RADIUS - h * h);
    }

    // ── Cuadrícula ──────────────────────────────────────────────────────────

    void layout_grid () {
      cells.clear ();
      var n = entries.size;
      var cols = ((int) Math.ceil (Math.sqrt (n * 1.6))).clamp (3, 7);
      cols = int.min (cols, int.max (1, n));
      var rows = (int) Math.ceil (n / (double) cols);

      var monitor = controller.position_manager.get_monitor_geometry ();
      var max_rows = int.max (1, (int) ((monitor.height * 0.62 - GRID_TITLE_H - GRID_FOOTER_H - ARROW) / GRID_CELL_H));
      var visible_rows = int.min (rows, max_rows);

      grid_view_h = visible_rows * GRID_CELL_H;
      max_scroll = int.max (0, rows * GRID_CELL_H - grid_view_h);
      width_px = GRID_PAD * 2 + cols * GRID_CELL_W;
      height_px = GRID_TITLE_H + grid_view_h + GRID_FOOTER_H + ARROW;
      anchor_x = width_px / 2;

      for (var i = 0; i < n; i++) {
        var cell = new Cell ();
        cell.entry = entries[i];
        cell.label = entries[i].name;
        cell.icon = DrawingService.load_icon (entries[i].icon, GRID_ICON, GRID_ICON);
        var col = i % cols;
        var row = i / cols;
        var cx = GRID_PAD + col * GRID_CELL_W;
        var cy = GRID_TITLE_H + row * GRID_CELL_H;
        cell.hit = { cx + 2, cy + 2, GRID_CELL_W - 4, GRID_CELL_H - 4 };
        cell.icon_rect = { cx + (GRID_CELL_W - GRID_ICON) / 2, cy + 6, GRID_ICON, GRID_ICON };
        cell.label_rect = { cx + 4, cy + 6 + GRID_ICON + 4, GRID_CELL_W - 8, 28 };
        cells.add (cell);
      }

      var footer_label = _("Open in Files");
      var fw = text_width (footer_label) + 24;
      footer_rect = { width_px - GRID_PAD - fw, GRID_TITLE_H + grid_view_h + 6, fw, GRID_FOOTER_H - 12 };
    }

    // ── Dibujo ──────────────────────────────────────────────────────────────

    public override bool draw (Cairo.Context cr) {
      cr.save ();
      cr.set_operator (Cairo.Operator.CLEAR);
      cr.paint ();
      cr.restore ();

      if (mode == StacksPopupMode.FAN)
        draw_fan (cr);
      else
        draw_grid (cr);

      return true;
    }

    void draw_fan (Cairo.Context cr) {
      for (var i = 0; i < cells.size; i++) {
        var cell = cells[i];
        var hot = (i == hovered);

        // La pastilla del nombre.
        rounded_rect (cr, cell.label_rect.x, cell.label_rect.y, cell.label_rect.width, cell.label_rect.height, 6);
        if (hot)
          cr.set_source_rgba (0.04, 0.52, 1.0, 0.95);
        else
          cr.set_source_rgba (0.12, 0.12, 0.13, 0.85);
        cr.fill ();
        draw_text (cr, cell.label, cell.label_rect, Pango.Alignment.CENTER, false, 1);

        Gdk.cairo_set_source_pixbuf (cr, cell.icon,
                                     cell.icon_rect.x + (FAN_ICON - cell.icon.width) / 2.0,
                                     cell.icon_rect.y + (FAN_ICON - cell.icon.height) / 2.0);
        cr.paint_with_alpha (hot ? 1.0 : 0.96);
      }
    }

    void draw_grid (Cairo.Context cr) {
      var body_h = height_px - ARROW;

      // El panel con su flecha hacia el ícono del dock.
      panel_path (cr, 0.5, 0.5, width_px - 1, body_h - 1, 12, anchor_x);
      cr.set_source_rgba (0.16, 0.16, 0.17, 0.90);
      cr.fill_preserve ();
      cr.set_source_rgba (1, 1, 1, 0.14);
      cr.set_line_width (1);
      cr.stroke ();

      Gdk.Rectangle title = { GRID_PAD, 0, width_px - 2 * GRID_PAD, GRID_TITLE_H };
      draw_text (cr, folder.get_basename (), title, Pango.Alignment.CENTER, true, 1);

      cr.save ();
      cr.rectangle (0, GRID_TITLE_H, width_px, grid_view_h);
      cr.clip ();
      cr.translate (0, -scroll);
      for (var i = 0; i < cells.size; i++) {
        var cell = cells[i];
        if (i == hovered) {
          rounded_rect (cr, cell.hit.x, cell.hit.y, cell.hit.width, cell.hit.height, 8);
          cr.set_source_rgba (1, 1, 1, 0.13);
          cr.fill ();
        }
        Gdk.cairo_set_source_pixbuf (cr, cell.icon,
                                     cell.icon_rect.x + (GRID_ICON - cell.icon.width) / 2.0,
                                     cell.icon_rect.y + (GRID_ICON - cell.icon.height) / 2.0);
        cr.paint ();
        draw_text (cr, cell.label, cell.label_rect, Pango.Alignment.CENTER, false, 2);
      }
      cr.restore ();

      // «Open in Files» al pie.
      var footer_hot = (hovered == -2);
      rounded_rect (cr, footer_rect.x, footer_rect.y, footer_rect.width, footer_rect.height, 6);
      cr.set_source_rgba (1, 1, 1, footer_hot ? 0.22 : 0.10);
      cr.fill ();
      draw_text (cr, _("Open in Files"), footer_rect, Pango.Alignment.CENTER, false, 1);
    }

    int text_width (string text) {
      var layout = create_pango_layout (text);
      int w, h;
      layout.get_pixel_size (out w, out h);
      return w;
    }

    void draw_text (Cairo.Context cr, string text, Gdk.Rectangle rect, Pango.Alignment align, bool bold, int lines) {
      var layout = create_pango_layout (text);
      var font = get_style_context ().get_font (Gtk.StateFlags.NORMAL).copy ();
      if (bold)
        font.set_weight (Pango.Weight.BOLD);
      layout.set_font_description (font);
      layout.set_width ((rect.width - 8) * Pango.SCALE);
      layout.set_alignment (align);
      layout.set_ellipsize (Pango.EllipsizeMode.MIDDLE);
      if (lines > 1) {
        layout.set_wrap (Pango.WrapMode.WORD_CHAR);
        layout.set_height (-lines);
      }
      int w, h;
      layout.get_pixel_size (out w, out h);
      var y = lines > 1 ? rect.y : rect.y + (rect.height - h) / 2.0;

      // Sombra suave para que se lea sobre cualquier fondo, como en macOS.
      cr.move_to (rect.x + 4, y + 1);
      cr.set_source_rgba (0, 0, 0, 0.55);
      Pango.cairo_show_layout (cr, layout);
      cr.move_to (rect.x + 4, y);
      cr.set_source_rgba (1, 1, 1, 1);
      Pango.cairo_show_layout (cr, layout);
    }

    static void rounded_rect (Cairo.Context cr, double x, double y, double w, double h, double r) {
      r = double.min (r, double.min (w, h) / 2.0);
      cr.new_sub_path ();
      cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
      cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
      cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
      cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
      cr.close_path ();
    }

    /**
     * El panel redondeado con la flecha abajo, apuntando a arrow_x.
     */
    static void panel_path (Cairo.Context cr, double x, double y, double w, double h, double r, double arrow_x) {
      arrow_x = arrow_x.clamp (x + r + ARROW, x + w - r - ARROW);
      cr.new_sub_path ();
      cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
      cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
      cr.line_to (arrow_x + ARROW, y + h);
      cr.line_to (arrow_x, y + h + ARROW);
      cr.line_to (arrow_x - ARROW, y + h);
      cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
      cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
      cr.close_path ();
    }

    // ── Eventos ─────────────────────────────────────────────────────────────

    int cell_at (double x, double y) {
      if (mode == StacksPopupMode.GRID) {
        if (point_in (footer_rect, x, y))
          return -2;
        if (y < GRID_TITLE_H || y > GRID_TITLE_H + grid_view_h)
          return -1;
        y += scroll;
      }
      for (var i = 0; i < cells.size; i++)
        if (point_in (cells[i].hit, x, y))
          return i;
      return -1;
    }

    static bool point_in (Gdk.Rectangle r, double x, double y) {
      return x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height;
    }

    public override bool motion_notify_event (Gdk.EventMotion event) {
      var now = cell_at (event.x, event.y);
      if (now != hovered) {
        hovered = now;
        queue_draw ();
      }
      return true;
    }

    public override bool leave_notify_event (Gdk.EventCrossing event) {
      if (hovered != -1) {
        hovered = -1;
        queue_draw ();
      }
      return true;
    }

    public override bool button_press_event (Gdk.EventButton event) {
      // Con el puntero tomado, un clic fuera llega aquí con coordenadas fuera
      // de la ventana: se cierra, como en macOS.
      if (event.x < 0 || event.y < 0 || event.x >= width_px || event.y >= height_px)
        close_now ();
      return true;
    }

    public override bool button_release_event (Gdk.EventButton event) {
      if (event.button != Gdk.BUTTON_PRIMARY)
        return true;

      var index = cell_at (event.x, event.y);
      if (index == -2 || (index >= 0 && cells[index].entry == null)) {
        StacksDockItem.open_file (folder);
        close_now ();
      } else if (index >= 0) {
        StacksDockItem.open_file (cells[index].entry.file);
        close_now ();
      }
      return true;
    }

    public override bool scroll_event (Gdk.EventScroll event) {
      if (mode != StacksPopupMode.GRID || max_scroll == 0)
        return true;

      double dx, dy;
      var delta = 0.0;
      if (event.get_scroll_deltas (out dx, out dy))
        delta = dy * 40;
      else if (event.direction == Gdk.ScrollDirection.UP)
        delta = -GRID_CELL_H / 2;
      else if (event.direction == Gdk.ScrollDirection.DOWN)
        delta = GRID_CELL_H / 2;

      scroll = ((int) (scroll + delta)).clamp (0, max_scroll);
      hovered = cell_at (event.x, event.y);
      queue_draw ();
      return true;
    }

    public override bool key_press_event (Gdk.EventKey event) {
      if (event.keyval == Gdk.Key.Escape)
        close_now ();
      return true;
    }

    public override bool grab_broken_event (Gdk.EventGrabBroken event) {
      close_now ();
      return true;
    }
  }
}
