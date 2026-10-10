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

namespace Plank {
  /**
   * El fondo de pantalla desenfocado que se ve detrás del dock, como en macOS.
   *
   * Cinnamon (Muffin) no desenfoca lo que hay detrás de una ventana, así que
   * el dock lo pinta él mismo: arma el fondo de pantalla del escritorio al
   * tamaño del monitor, lo desenfoca una sola vez y el renderer pinta el
   * pedazo que le queda detrás, recortado a la silueta del fondo del dock,
   * antes del relleno translúcido del tema.
   *
   * Lo que no se ve así: una ventana que pase por detrás del dock no sale
   * desenfocada. En la práctica casi nunca pasa, porque las ventanas no se
   * meten debajo del dock.
   *
   * Para que sea barato, se desenfoca a un cuarto de la resolución y al
   * pintarlo se escala de vuelta con filtro bilineal: un desenfoque grande
   * no tiene detalle que se pierda al bajar la resolución.
   */
  public class WallpaperBlur : GLib.Object {
    /**
     * Cuánto se reduce el fondo antes de desenfocarlo.
     */
    public const int SCALE = 4;

    /**
     * El fondo de pantalla cambió: hay que volver a pintar.
     */
    public signal void changed ();

    GLib.Settings? settings = null;
    Surface? blurred = null;
    Gdk.Rectangle cached_geo;
    int cached_radius = -1;

    construct
    {
      // Cinnamon primero; si no está, GNOME (mismas claves).
      var source = GLib.SettingsSchemaSource.get_default ();
      string[] ids = { "org.cinnamon.desktop.background", "org.gnome.desktop.background" };
      foreach (unowned string id in ids) {
        if (source != null && source.lookup (id, true) != null) {
          settings = new GLib.Settings (id);
          settings.changed.connect (handle_settings_changed);
          break;
        }
      }
    }

    ~WallpaperBlur ()
    {
      if (settings != null)
        settings.changed.disconnect (handle_settings_changed);
    }

    void handle_settings_changed (string key) {
      if (key != "picture-uri" && key != "picture-options" && key != "primary-color")
        return;

      blurred = null;
      changed ();
    }

    /**
     * El fondo desenfocado del monitor, reducido por SCALE, o null si no hay
     * de dónde sacarlo o el radio es 0.
     *
     * @param monitor la geometría completa del monitor (no el área de trabajo)
     * @param radius el radio del desenfoque, en píxeles de pantalla
     */
    public unowned Surface? get_blurred (Gdk.Rectangle monitor, int radius) {
      if (settings == null || radius <= 0 || monitor.width <= 0 || monitor.height <= 0)
        return null;

      if (blurred != null && cached_radius == radius
          && cached_geo.x == monitor.x && cached_geo.y == monitor.y
          && cached_geo.width == monitor.width && cached_geo.height == monitor.height)
        return blurred;

      blurred = build (monitor, radius);
      cached_geo = monitor;
      cached_radius = radius;
      return blurred;
    }

    Surface build (Gdk.Rectangle monitor, int radius) {
      var width = int.max (1, monitor.width / SCALE);
      var height = int.max (1, monitor.height / SCALE);
      var surface = new Surface (width, height);
      unowned Cairo.Context cr = surface.Context;

      // El color de fondo va debajo: es lo que queda donde la imagen no cubre.
      var primary = Gdk.RGBA ();
      if (!primary.parse (settings.get_string ("primary-color")))
        primary = { 0.0, 0.0, 0.0, 1.0 };
      cr.set_source_rgb (primary.red, primary.green, primary.blue);
      cr.paint ();

      var uri = settings.get_string ("picture-uri");
      var options = settings.get_string ("picture-options");
      if (uri != "" && options != "none") {
        try {
          var path = File.new_for_uri (uri).get_path ();
          if (path != null) {
            var pixbuf = new Gdk.Pixbuf.from_file (path);
            paint_wallpaper (cr, pixbuf, width, height, options);
          }
        } catch (Error e) {
          warning ("WallpaperBlur: no se pudo leer el fondo '%s': %s", uri, e.message);
        }
      }

      surface.gaussian_blur (int.max (1, radius / SCALE));
      return surface;
    }

    /**
     * Pinta el fondo como lo pinta el escritorio, en un lienzo de width x
     * height que representa el monitor reducido por SCALE.
     */
    static void paint_wallpaper (Cairo.Context cr, Gdk.Pixbuf pixbuf, int width, int height, string options) {
      double pw = pixbuf.width, ph = pixbuf.height;
      double sx, sy;

      cr.save ();
      switch (options) {
      case "wallpaper":
        // Mosaico a tamaño natural.
        cr.scale (1.0 / SCALE, 1.0 / SCALE);
        Gdk.cairo_set_source_pixbuf (cr, pixbuf, 0, 0);
        cr.get_source ().set_extend (Cairo.Extend.REPEAT);
        cr.rectangle (0, 0, width * SCALE, height * SCALE);
        cr.fill ();
        cr.restore ();
        return;
      case "centered":
        sx = sy = 1.0 / SCALE;
        break;
      case "scaled":
        sx = sy = double.min (width / pw, height / ph);
        break;
      case "stretched":
        sx = width / pw;
        sy = height / ph;
        break;
      case "zoom":
      case "spanned":
      default:
        sx = sy = double.max (width / pw, height / ph);
        break;
      }

      cr.translate ((width - pw * sx) / 2.0, (height - ph * sy) / 2.0);
      cr.scale (sx, sy);
      Gdk.cairo_set_source_pixbuf (cr, pixbuf, 0, 0);
      cr.get_source ().set_filter (Cairo.Filter.GOOD);
      cr.paint ();
      cr.restore ();
    }
  }
}
