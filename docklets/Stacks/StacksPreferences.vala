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
   * Cómo se ordena el contenido de la pila (el «Sort by» de macOS).
   */
  public enum StacksSortBy {
    NAME,
    DATE_ADDED,
    DATE_MODIFIED,
    DATE_CREATED,
    KIND
  }

  /**
   * Cómo se ve el ícono en el dock (el «Display as» de macOS).
   */
  public enum StacksDisplayAs {
    FOLDER,
    STACK
  }

  /**
   * Cómo se abre el contenido (el «View content as» de macOS).
   */
  public enum StacksViewAs {
    FAN,
    GRID,
    LIST,
    AUTOMATIC
  }

  public class StacksPreferences : DockItemPreferences {
    [Description (nick = "folder", blurb = "The folder shown by the stack, as a URI. Empty means the Downloads folder.")]
    public string Folder { get; set; default = ""; }

    [Description (nick = "sort-by", blurb = "How the contents are sorted.")]
    public StacksSortBy SortBy { get; set; default = StacksSortBy.DATE_ADDED; }

    [Description (nick = "display-as", blurb = "Show the folder icon or a stack of its newest items.")]
    public StacksDisplayAs DisplayAs { get; set; default = StacksDisplayAs.STACK; }

    [Description (nick = "view-as", blurb = "How the contents open: fan, grid, list or automatic.")]
    public StacksViewAs ViewAs { get; set; default = StacksViewAs.FAN; }

    public StacksPreferences.with_file (GLib.File file)
    {
      base.with_file (file);
    }

    protected override void reset_properties () {
      base.reset_properties ();
      Folder = "";
      SortBy = StacksSortBy.DATE_ADDED;
      DisplayAs = StacksDisplayAs.STACK;
      ViewAs = StacksViewAs.FAN;
    }

    /**
     * La carpeta de la pila: la configurada, o Descargas.
     */
    public GLib.File get_folder () {
      if (Folder != null && Folder != "")
        return GLib.File.new_for_uri (Folder);

      var downloads = GLib.Environment.get_user_special_dir (GLib.UserDirectory.DOWNLOAD);
      if (downloads == null || downloads == "")
        downloads = GLib.Path.build_filename (GLib.Environment.get_home_dir (), "Downloads");
      return GLib.File.new_for_path (downloads);
    }
  }
}
