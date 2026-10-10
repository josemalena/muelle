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
   * Un archivo de la pila, con lo que hace falta para ordenarlo y pintarlo.
   */
  public class StacksEntry : Object {
    public GLib.File file { get; construct; }
    public string name { get; construct; }
    public string content_type { get; construct; }
    public bool is_directory { get; construct; }
    public int64 added { get; construct; }
    public int64 modified { get; construct; }
    public int64 created { get; construct; }
    /**
     * Miniatura si existe; si no, los nombres del ícono del tipo de archivo.
     */
    public string icon { get; construct; }

    const string ATTRIBUTES = FileAttribute.STANDARD_NAME + ","
                              + FileAttribute.STANDARD_DISPLAY_NAME + ","
                              + FileAttribute.STANDARD_TYPE + ","
                              + FileAttribute.STANDARD_IS_HIDDEN + ","
                              + FileAttribute.STANDARD_IS_BACKUP + ","
                              + FileAttribute.STANDARD_CONTENT_TYPE + ","
                              + FileAttribute.STANDARD_ICON + ","
                              + FileAttribute.THUMBNAIL_PATH + ","
                              + FileAttribute.TIME_MODIFIED + ","
                              + FileAttribute.TIME_CHANGED + ","
                              + FileAttribute.TIME_CREATED;

    public StacksEntry (GLib.File file, string name, string content_type, bool is_directory,
                        int64 added, int64 modified, int64 created, string icon) {
      Object (file: file, name: name, content_type: content_type, is_directory: is_directory,
              added: added, modified: modified, created: created, icon: icon);
    }

    /**
     * Lee la carpeta: sin ocultos ni respaldos, como el Finder.
     *
     * «Date Added» en macOS es cuándo llegó el archivo a la carpeta. En Linux
     * no existe ese dato; lo más cercano es el último cambio de estado
     * (ctime), que se pone al bajarlo, moverlo o copiarlo ahí.
     */
    public static Gee.ArrayList<StacksEntry> load (GLib.File folder) {
      var entries = new Gee.ArrayList<StacksEntry> ();

      try {
        var enumerator = folder.enumerate_children (ATTRIBUTES, FileQueryInfoFlags.NONE);
        FileInfo? info;
        while ((info = enumerator.next_file ()) != null) {
          if (info.get_is_hidden () || info.get_is_backup ())
            continue;

          var child = folder.get_child (info.get_name ());
          var modified = (int64) info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
          var changed = (int64) info.get_attribute_uint64 (FileAttribute.TIME_CHANGED);
          var created = info.has_attribute (FileAttribute.TIME_CREATED)
                        ? (int64) info.get_attribute_uint64 (FileAttribute.TIME_CREATED)
                        : modified;

          string? icon = null;
          unowned string? thumb = info.get_attribute_byte_string (FileAttribute.THUMBNAIL_PATH);
          if (thumb != null && thumb != "")
            icon = thumb;
          if (icon == null)
            icon = DrawingService.get_icon_from_gicon (info.get_icon ());
          if (icon == null || icon == "")
            icon = "text-x-generic";

          entries.add (new StacksEntry (child,
                                        info.get_display_name (),
                                        info.get_content_type () ?? "",
                                        info.get_file_type () == FileType.DIRECTORY,
                                        changed > 0 ? changed : modified,
                                        modified,
                                        created,
                                        icon));
        }
        enumerator.close ();
      } catch (Error e) {
        warning ("Stacks: no se pudo leer '%s': %s", folder.get_uri (), e.message);
      }

      return entries;
    }

    /**
     * Ordena como el «Sort by» de macOS: por fecha, lo más nuevo primero; por
     * nombre, alfabético y sin distinguir mayúsculas; por tipo, agrupados por
     * tipo y por nombre dentro de cada uno.
     */
    public static void sort (Gee.ArrayList<StacksEntry> entries, StacksSortBy sort_by) {
      entries.sort ((a, b) => {
        switch (sort_by) {
        case StacksSortBy.NAME:
          return compare_names (a, b);
        case StacksSortBy.KIND:
          var kind = strcmp (kind_key (a), kind_key (b));
          return kind != 0 ? kind : compare_names (a, b);
        case StacksSortBy.DATE_MODIFIED:
          return newest_first (a.modified, b.modified, a, b);
        case StacksSortBy.DATE_CREATED:
          return newest_first (a.created, b.created, a, b);
        case StacksSortBy.DATE_ADDED:
        default:
          return newest_first (a.added, b.added, a, b);
        }
      });
    }

    static int compare_names (StacksEntry a, StacksEntry b) {
      return strcmp (a.name.collate_key_for_filename (), b.name.collate_key_for_filename ());
    }

    static int newest_first (int64 x, int64 y, StacksEntry a, StacksEntry b) {
      if (x != y)
        return x > y ? -1 : 1;
      return compare_names (a, b);
    }

    static string kind_key (StacksEntry e) {
      // Las carpetas primero, como el Finder al ordenar por tipo.
      if (e.is_directory)
        return "0";
      var description = ContentType.get_description (e.content_type);
      return "1" + (description ?? e.content_type).casefold ();
    }
  }
}
