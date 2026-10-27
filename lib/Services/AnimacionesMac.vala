/*
 * Los números de las animaciones de la Mac, del perfil de versión activo (mint-macos: macos/<versión>/apps/animaciones.json, medidos
 * en videos de pantalla; cada uno trae su fuente en el perfil). Una clave ausente significa «no medido»: quien llama conserva
 * entonces su valor de siempre. Sin Json-GLib a propósito: cada animación es un objeto plano, sin objetos anidados.
 */
namespace Plank {
  internal class AnimacionesMac : GLib.Object {
    static string? contenido = null;
    static bool leido = false;

    static string? version_activa () {
      string texto;
      foreach (var ruta in new string[] { GLib.Path.build_filename (GLib.Environment.get_user_runtime_dir (), "mint-macos", "macos.json"),
                                          GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "mint-macos", "macos.json") }) {
        try {
          if (GLib.FileUtils.get_contents (ruta, out texto)) {
            GLib.MatchInfo m;
            if (/"version"\s*:\s*"([^"]+)"/.match (texto, 0, out m))
              return m.fetch (1);
          }
        } catch (GLib.Error e) {
        }
      }
      return null;
    }

    static string? bloque (string animacion) {
      if (!leido) {
        leido = true;
        var ruta = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "mint-macos", "macos",
                                             version_activa () ?? "catalina-10.15", "apps", "animaciones.json");
        try {
          GLib.FileUtils.get_contents (ruta, out contenido);
        } catch (GLib.Error e) {
          contenido = null;
        }
      }
      if (contenido == null)
        return null;
      try {
        GLib.MatchInfo m;
        var re = new GLib.Regex ("\"" + GLib.Regex.escape_string (animacion) + "\"\\s*:\\s*\\{([^{}]*)\\}");
        return re.match (contenido, 0, out m) ? m.fetch (1) : null;
      } catch (GLib.RegexError e) {
        return null;
      }
    }

    /** El campo numérico de una animación, o -1.0 si el perfil no lo trae. */
    internal static double numero (string animacion, string campo) {
      var b = bloque (animacion);
      if (b == null)
        return -1.0;
      try {
        GLib.MatchInfo m;
        var re = new GLib.Regex ("\"" + GLib.Regex.escape_string (campo) + "\"\\s*:\\s*(-?[0-9]+(?:\\.[0-9]+)?)");
        return re.match (b, 0, out m) ? double.parse (m.fetch (1)) : -1.0;
      } catch (GLib.RegexError e) {
        return -1.0;
      }
    }

    /** La curva medida, aproximada con las del motor (la lineal; la easeInEaseOut es la cuadrática); la de siempre si no se midió o no coincide. */
    internal static AnimationMode curva (string animacion, AnimationMode por_defecto) {
      var b = bloque (animacion);
      if (b == null)
        return por_defecto;
      GLib.MatchInfo m;
      if (/"curva"\s*:\s*"([^"]*)"/.match (b, 0, out m)) {
        var c = m.fetch (1).down ();
        if (c.has_prefix ("easeineaseout"))
          return AnimationMode.EASE_IN_OUT_QUAD;
        if (c.has_prefix ("casi lineal") || c.has_prefix ("lineal") || c.has_prefix ("linear"))
          return AnimationMode.LINEAR;
      }
      return por_defecto;
    }
  }
}
