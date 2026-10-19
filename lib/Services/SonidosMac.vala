/*
 * Los sonidos de la Mac para el Dock: «poof item off dock» al sacar un ícono con la nube. El archivo es de la instalación
 * (~/.local/share/sounds/mint-macos/<nombre>.wav|oga|ogg), nunca del repo; sin él no suena nada. «Play user interface sound effects»
 * (org.cinnamon.desktop.sound event-sounds) manda sobre todos. Se reproduce con paplay, desacoplado.
 */
namespace Plank {
  internal class SonidosMac : GLib.Object {
    internal static void reproducir (string basename) {
      var fuente = GLib.SettingsSchemaSource.get_default ();
      if (fuente != null && fuente.lookup ("org.cinnamon.desktop.sound", true) != null
          && !new GLib.Settings ("org.cinnamon.desktop.sound").get_boolean ("event-sounds"))
        return;

      var carpeta = GLib.Path.build_filename (GLib.Environment.get_user_data_dir (), "sounds", "mint-macos");
      foreach (unowned string ext in new string[] { "wav", "oga", "ogg" }) {
        var ruta = GLib.Path.build_filename (carpeta, "%s.%s".printf (basename, ext));
        if (!GLib.FileUtils.test (ruta, GLib.FileTest.IS_REGULAR))
          continue;
        try {
          new GLib.Subprocess (GLib.SubprocessFlags.STDOUT_SILENCE | GLib.SubprocessFlags.STDERR_SILENCE, "paplay", ruta);
        } catch (GLib.Error e) {
          warning ("no pude reproducir %s: %s", ruta, e.message);
        }
        return;
      }
    }
  }
}
