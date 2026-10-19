//
// Muelle es el Plank de mint-macos con su propio nombre. La primera vez que arranca trae lo que había con el nombre viejo, sin tocarlo:
// ~/.config/plank → ~/.config/muelle, ~/.local/share/plank → ~/.local/share/muelle (los temas) y el árbol de dconf
// /net/launchpad/plank/ → /org/mintmacos/muelle/. Lo viejo queda igual, así que volver atrás es arrancar el plank de antes.
// Antes de cargar el dconf viejo en el nuevo se guarda un respaldo en ~/.local/share/mint-macos/respaldos/.
// MUELLE_SIN_MIGRAR=1 la salta (las pruebas).
//

namespace Plank {
  namespace Migracion {
    /** Corre un programa y devuelve su salida; null si no está o falla. `entrada` va por stdin. */
    string? correr (string[] argv, string? entrada = null) {
      try {
        var flags = SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE;
        if (entrada != null)
          flags |= SubprocessFlags.STDIN_PIPE;
        var proceso = new Subprocess.newv (argv, flags);
        string? salida;
        proceso.communicate_utf8 (entrada, null, out salida, null);
        return proceso.get_successful () ? (salida ?? "") : null;
      } catch (Error e) {
        warning ("migración: %s: %s", argv[0], e.message);
        return null;
      }
    }

    public void de_plank () {
      if (Environment.get_variable ("MUELLE_SIN_MIGRAR") != null)
        return;

      var config = Environment.get_user_config_dir ();
      var datos = Environment.get_user_data_dir ();
      var config_nuevo = Path.build_filename (config, "muelle");
      var marca = Path.build_filename (config_nuevo, ".migrado-de-plank");
      if (FileUtils.test (marca, FileTest.EXISTS))
        return;

      var config_viejo = Path.build_filename (config, "plank");
      var datos_viejo = Path.build_filename (datos, "plank");
      var datos_nuevo = Path.build_filename (datos, "muelle");
      var fecha = new DateTime.now_local ().format ("%Y%m%d-%H%M%S");

      // La configuración de los docks (los lanzadores): solo si Muelle todavía no tiene los suyos.
      if (FileUtils.test (config_viejo, FileTest.IS_DIR) && !FileUtils.test (Path.build_filename (config_nuevo, "dock1"), FileTest.IS_DIR)) {
        DirUtils.create_with_parents (config_nuevo, 0755);
        if (correr ({ "cp", "-a", "--", config_viejo + "/.", config_nuevo }) == null)
          warning ("migración: no se pudo copiar %s", config_viejo);
      }

      // Los temas del usuario.
      if (FileUtils.test (datos_viejo, FileTest.IS_DIR) && !FileUtils.test (datos_nuevo, FileTest.EXISTS)) {
        if (correr ({ "cp", "-a", "--", datos_viejo, datos_nuevo }) == null)
          warning ("migración: no se pudo copiar %s", datos_viejo);
      }

      // Los ajustes de dconf, con respaldo.
      var viejo = correr ({ "dconf", "dump", "/net/launchpad/plank/" });
      var existente = correr ({ "dconf", "list", "/org/mintmacos/muelle/" });
      if (viejo != null && viejo.strip () != "" && (existente == null || existente.strip () == "")) {
        var respaldos = Path.build_filename (datos, "mint-macos", "respaldos");
        DirUtils.create_with_parents (respaldos, 0755);
        try {
          FileUtils.set_contents (Path.build_filename (respaldos, "plank-dconf-%s.ini".printf (fecha)), viejo);
        } catch (FileError e) {
          warning ("migración: no se pudo guardar el respaldo (%s); no se migra el dconf", e.message);
          return;
        }
        if (correr ({ "dconf", "load", "/org/mintmacos/muelle/" }, viejo) == null)
          warning ("migración: dconf load falló");
      }

      DirUtils.create_with_parents (config_nuevo, 0755);
      try {
        FileUtils.set_contents (marca, fecha + "\n");
      } catch (FileError e) {
        warning ("migración: no se pudo escribir la marca (%s)", e.message);
      }
      message ("Muelle: trajo la configuración de Plank (%s)", fecha);
    }
  }
}
