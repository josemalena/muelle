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

public static void docklet_init (Plank.DockletManager manager) {
  manager.register_docklet (typeof (Docky.StacksDocklet));
}

namespace Docky {
  /**
   * Una carpeta como pila, igual que en el Dock de macOS: Descargas por
   * defecto, que se abre en abanico, cuadrícula o lista.
   */
  public class StacksDocklet : Object, Plank.Docklet {
    private const string ID = "stacks";
    private const string ICON = "folder-download;;folder";

    public unowned string get_id () { return ID; }

    public unowned string get_name () { return _("Stack"); }

    public unowned string get_description () { return _("A folder as a stack, shown as a fan, a grid or a list."); }

    public unowned string get_icon () { return ICON; }

    public bool is_supported () { return true; }

    public Plank.DockElement make_element (string launcher, GLib.File file) {
      return new StacksDockItem.with_dockitem_file (file);
    }
  }
}
