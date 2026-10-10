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
   * El ícono del Calendario con la fecha de hoy, como en el Dock de macOS: un
   * taco de hojas un poco ladeado, la franja roja con el mes y el número del
   * día grande y fino.
   *
   * Se dibuja, no se copia: no lleva nada del ícono de Apple. Las letras usan
   * SF Pro Display si está instalada (se genera en local desde el disco del
   * Mac) y, si no, la fuente del sistema.
   */
  public class CalendarIcon : GLib.Object {
    const string FONT = "SF Pro Display, Helvetica Neue, Sans";
    const double TILT = -0.15;

    /**
     * Dibuja el ícono con la fecha dada en un cuadrado de size x size.
     */
    public static void draw (Cairo.Context cr, int size, DateTime date) {
      var s = (double) size;
      var w = s * 0.78;
      var h = s * 0.80;
      var x = -w / 2.0;
      var y = -h / 2.0 - s * 0.03;
      var r = s * 0.035;

      cr.save ();
      cr.translate (s / 2.0, s / 2.0);
      cr.rotate (TILT);

      // Las hojas de abajo del taco, oscuras, asomando por abajo y a la
      // derecha.
      for (var k = 2; k >= 1; k--) {
        rounded_rect (cr, x - s * 0.012, y + k * s * 0.03, w + s * 0.024, h, r);
        cr.set_source_rgb (0.28 + 0.05 * k, 0.29 + 0.05 * k, 0.31 + 0.05 * k);
        cr.fill ();
      }

      // La sombra de la hoja de arriba.
      rounded_rect (cr, x, y + s * 0.012, w, h, r);
      cr.set_source_rgba (0, 0, 0, 0.30);
      cr.fill ();

      // La hoja: blanca, un poco más gris abajo.
      rounded_rect (cr, x, y, w, h, r);
      var page = new Cairo.Pattern.linear (0, y, 0, y + h);
      page.add_color_stop_rgb (0.0, 1.0, 1.0, 1.0);
      page.add_color_stop_rgb (1.0, 0.90, 0.90, 0.91);
      cr.set_source (page);
      cr.fill_preserve ();
      cr.clip ();

      // La franja roja con el mes.
      var band = h * 0.25;
      cr.rectangle (x, y, w, band);
      var red = new Cairo.Pattern.linear (0, y, 0, y + band);
      red.add_color_stop_rgb (0.0, 0.96, 0.36, 0.33);
      red.add_color_stop_rgb (1.0, 0.89, 0.24, 0.22);
      cr.set_source (red);
      cr.fill ();

      var month = date.format ("%b").up ().replace (".", "");
      draw_text (cr, month, x, y, w, band, band * 0.80, Pango.Weight.BOLD, 1.0, 1.0, 1.0);

      // El número del día.
      var day = date.get_day_of_month ().to_string ();
      draw_text (cr, day, x, y + band, w, h - band, (h - band) * 0.86, Pango.Weight.LIGHT, 0.11, 0.11, 0.12);

      cr.restore ();
    }

    static void draw_text (Cairo.Context cr, string text, double x, double y, double w, double h,
                           double px, Pango.Weight weight, double red, double green, double blue) {
      var layout = Pango.cairo_create_layout (cr);
      var font = Pango.FontDescription.from_string (FONT);
      font.set_absolute_size (px * Pango.SCALE);
      font.set_weight (weight);
      layout.set_font_description (font);
      layout.set_text (text, -1);

      Pango.Rectangle ink, logical;
      layout.get_pixel_extents (out ink, out logical);
      // Centrado por la tinta, no por la caja: así el número queda en el
      // medio de verdad, sin el aire de arriba de la fuente.
      cr.move_to (x + (w - ink.width) / 2.0 - ink.x, y + (h - ink.height) / 2.0 - ink.y);
      cr.set_source_rgb (red, green, blue);
      Pango.cairo_show_layout (cr, layout);
    }

    static void rounded_rect (Cairo.Context cr, double x, double y, double w, double h, double r) {
      cr.new_sub_path ();
      cr.arc (x + w - r, y + r, r, -Math.PI / 2, 0);
      cr.arc (x + w - r, y + h - r, r, 0, Math.PI / 2);
      cr.arc (x + r, y + h - r, r, Math.PI / 2, Math.PI);
      cr.arc (x + r, y + r, r, Math.PI, 3 * Math.PI / 2);
      cr.close_path ();
    }

    /**
     * Cuántos milisegundos faltan para la medianoche, cuando cambia el día.
     */
    public static uint ms_until_midnight () {
      var now = new DateTime.now_local ();
      var tomorrow = new DateTime.local (now.get_year (), now.get_month (), now.get_day_of_month (), 0, 0, 0).add_days (1);
      var diff = tomorrow.difference (now) / 1000;
      return (uint) int64.max (1000, diff + 1000);
    }
  }
}
