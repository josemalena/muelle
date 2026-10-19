# Muelle

Fork de [zquestz/plank-reloaded](https://github.com/zquestz/plank-reloaded) para
[mint-macos](https://github.com/josemalena/mint-macos): el Dock de macOS Catalina
(punto bajo las apps abiertas, fondo desenfocado, separador, pilas y el efecto genio).

Se instala y se ejecuta como `muelle`. Cambian el ejecutable, el esquema de gsettings
(`org.mintmacos.muelle`, ruta `/org/mintmacos/muelle/`), el nombre de D-Bus de la aplicación
(`org.mintmacos.Muelle`), el `.desktop` y las carpetas (`~/.config/muelle`,
`~/.local/share/muelle/themes`); la biblioteca `libplank`, los docklets y el resto de los
nombres internos siguen siendo los de Plank. La primera vez que arranca trae la configuración
del nombre viejo (lanzadores, temas y dconf) sin tocarla, y deja un respaldo del dconf en
`~/.local/share/mint-macos/respaldos/` (`src/Migracion.vala`); `MUELLE_SIN_MIGRAR=1` la salta. Lo compila y lo instala `construir.sh` de mint-macos, fijado a un commit.
El README.md en inglés es el del proyecto original.

No incluye imágenes, fuentes ni iconos de Apple. Licencia GPL-3.0, la del proyecto
original (`COPYING`).
