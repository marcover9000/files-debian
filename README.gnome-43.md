# Pantheon Files per GNOME 43 (Debian 12)

Fork d'[elementary/files](https://github.com/elementary/files) sobre el tag **7.1.6**, amb pedaços perquè compili i s'integri en una sessió GNOME 43 amb tema Breeze. L'objectiu era tenir la **vista per columnes (Miller)** estil Finder de macOS, que Nautilus no ofereix.

> Es fixa a **7.1.6** expressament: a 7.3.x la vista Miller té una regressió (en clicar una carpeta d'una columna anterior es trenca la navegació).

## Pedaços al codi

- **`meson.build`** — depèn de `granite` (6.x, de `libgranite-dev`), no de `granite-7` (que a Debian va contra GTK4 i xoca amb el codi GTK3).
- **`pantheon-files-daemon/main.vala`** — el daemon només fa `exit(-1)` si no aconsegueix `io.elementary.files.db`, no per `org.freedesktop.FileManager1` (a GNOME el té Nautilus i, si no, el daemon es matava sol).
- **`libcore/Resources.vala`**, **`libcore/TrashMonitor.vala`** — constants d'icones `ICON_*` apuntant a variants `-symbolic`.
- **`libcore/Bookmark.vala`** — `get_icon()` retorna icones simbòliques per al **sidebar** (carpetes/punts de muntatge).
- **`libcore/File.vala`** — la **vista de contingut** usa icones de **color** (`get_colored_icon_user_special_dirs`), no simbòliques. Convenció: simbòliques només al sidebar, color al contingut.
- **`libcore/Widgets/BasicBreadcrumbsEntry.vala`** — el placeholder/autocompletat de la barra de ruta es posiciona amb `get_layout_offsets()` perquè quedi alineat amb el cursor.

## Compilar

```sh
meson setup build --prefix=/opt/pantheon-files
ninja -C build
sudo ninja -C build install
```

Cal: `valac`, `meson`, `ninja`, `libgranite-dev` (granite 6), `libgtk-3-dev`, `libhandy-1-dev` i la resta de dependències de Files.

## Integració amb GNOME (`gnome-integration/`)

Fitxers de l'entorn (no formen part de la compilació):

- `bin/` — wrappers que fixen `LD_LIBRARY_PATH`, `GSETTINGS_SCHEMA_DIR` i `XDG_DATA_DIRS` cap al prefix `/opt/pantheon-files`. Van a `~/.local/bin/`.
- `applications/io.elementary.files.desktop` — llançador. Usa rutes **absolutes** a `Exec`/`TryExec` (GNOME Shell no té `~/.local/bin` al PATH). Va a `~/.local/share/applications/`.
- `dbus-1-services/*.service` — serveis D-Bus apuntant als wrappers. Van a `~/.local/share/dbus-1/services/`.
- `icons/` — icona pròpia de l'app i `view-column-symbolic.svg` (Adwaita no la porta).
- `gtk-3.0/gtk.css` — retocs visuals estil GNOME (sidebar, headerbar, menús, barra de ruta). Va a `~/.config/gtk-3.0/`.

> **Atenció rutes**: els wrappers, el `.desktop` i els serveis D-Bus tenen rutes absolutes a `/opt/pantheon-files` i `/home/marc/.local/bin`. En una altra màquina (p. ex. Arch) cal ajustar-les.

## Notes per exportar a Arch / GNOME 44

- Comprovar la versió de **granite**: si el sistema només porta granite-7 (GTK4), caldrà el paquet de granite 6 o ajustar `meson.build`.
- Revisar les rutes absolutes dels fitxers de `gnome-integration/`.
- El `gtk.css` està pensat per al tema **Breeze**; amb un altre tema potser cal afinar colors.
