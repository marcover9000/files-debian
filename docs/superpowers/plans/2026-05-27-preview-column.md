# Preview pane a la vista de columnes — Pla d'implementació

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Afegir a la vista de columnes (Miller) una columna de vista prèvia estil Finder que mostra miniatura gran + metadades en seleccionar un fitxer.

**Architecture:** Un widget nou autocontingut `PreviewColumn` (`Gtk.ScrolledWindow`) que, donat un `Files.File`, mostra miniatura (via el sistema de thumbnails existent) i una graella de metadades. `Miller` el crea/treu segons la selecció i el col·loca al `colpane` del darrer slot, on el `Gtk.Paned` existent ja proporciona el redimensionat.

**Tech Stack:** Vala, GTK3, Granite 6.x, Meson/Ninja. Sense framework de tests unitaris → verificació via compilació + proves manuals (com la resta de la base i com l'spec).

**Nota sobre TDD:** Igual que la barra d'estat, no hi ha harness de tests unitaris per a widgets GTK; cada tasca usa `ninja -C build` com a porta automàtica i acaba amb verificació manual concreta.

---

## Estructura de fitxers

- **Create:** `src/View/Widgets/PreviewColumn.vala` — el widget de preview (miniatura + metadades + càrrega async de thumbnail).
- **Modify:** `src/meson.build` — registrar el fitxer nou a la llista de fonts.
- **Modify:** `src/View/Miller.vala` — mostrar/treure el preview segons la selecció; incloure'l al càlcul d'amplada total.

---

## Task 1: Widget PreviewColumn + registre a meson

**Files:**
- Create: `src/View/Widgets/PreviewColumn.vala`
- Modify: `src/meson.build`

- [ ] **Step 1: Crear el fitxer del widget**

Crea `src/View/Widgets/PreviewColumn.vala` amb aquest contingut complet:

```vala
/*
 * Finder-style preview column for the Miller (column) view.
 * Shows a large thumbnail/icon plus a metadata grid for the selected file.
 */

namespace Files.View {
    public class PreviewColumn : Gtk.ScrolledWindow {
        private const int PREVIEW_ICON_SIZE = 256;

        private Gtk.Image image;
        private Gtk.Label name_label;
        private Gtk.Grid info_grid;
        private Files.File? current_file = null;
        private ulong thumb_handler_id = 0;
        private int thumb_request = -1;

        construct {
            hscrollbar_policy = Gtk.PolicyType.NEVER;
            vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            get_style_context ().add_class ("files-preview-column");

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin = 12,
                valign = Gtk.Align.START
            };

            image = new Gtk.Image () {
                halign = Gtk.Align.CENTER
            };

            name_label = new Gtk.Label (null) {
                halign = Gtk.Align.CENTER,
                ellipsize = Pango.EllipsizeMode.MIDDLE,
                max_width_chars = 24
            };
            name_label.get_style_context ().add_class ("heading");

            info_grid = new Gtk.Grid () {
                column_spacing = 8,
                row_spacing = 4,
                margin_top = 6,
                halign = Gtk.Align.FILL
            };

            box.add (image);
            box.add (name_label);
            box.add (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            box.add (info_grid);

            add (box);
            box.show_all ();
        }

        ~PreviewColumn () {
            disconnect_thumb ();
        }

        public void set_file (Files.File? file) {
            disconnect_thumb ();
            current_file = file;
            if (file == null) {
                return;
            }

            update_image ();
            populate_info (file);

            if (file.thumbstate != Files.File.ThumbState.READY) {
                unowned var thumbnailer = Files.Thumbnailer.@get ();
                if (thumbnailer != null && thumbnailer.queue_file (file, out thumb_request)) {
                    thumb_handler_id = thumbnailer.finished.connect (on_thumbnail_finished);
                }
            }
        }

        private void on_thumbnail_finished (uint request) {
            if ((int) request == thumb_request && current_file != null) {
                update_image ();
                disconnect_thumb ();
            }
        }

        private void disconnect_thumb () {
            if (thumb_handler_id != 0) {
                unowned var thumbnailer = Files.Thumbnailer.@get ();
                if (thumbnailer != null) {
                    thumbnailer.disconnect (thumb_handler_id);
                }
                thumb_handler_id = 0;
            }
            thumb_request = -1;
        }

        private void update_image () {
            if (current_file == null) {
                return;
            }

            var scale = get_scale_factor ();
            var pix = current_file.get_icon_pixbuf (PREVIEW_ICON_SIZE, scale);
            if (pix != null) {
                var surface = Gdk.cairo_surface_create_from_pixbuf (pix, scale, null);
                image.set_from_surface (surface);
            }
        }

        private void populate_info (Files.File file) {
            info_grid.@foreach ((w) => {
                w.destroy ();
            });

            name_label.label = file.get_display_name ();

            int row = 0;
            var ftype = (file.formated_type != null && file.formated_type != "")
                            ? file.formated_type : file.get_ftype ();
            add_info_row (ref row, _("Type"), ftype);
            add_info_row (ref row, _("Size"), format_size (PropertiesWindow.file_real_size (file)));
            if (file.is_image () && file.width > 0) {
                add_info_row (ref row, _("Dimensions"), "%i × %i".printf (file.width, file.height));
            }
            add_info_row (ref row, _("Modified"), file.get_formated_time (GLib.FileAttribute.TIME_MODIFIED));

            info_grid.show_all ();
        }

        private void add_info_row (ref int row, string key, string? value) {
            if (value == null || value == "") {
                return;
            }

            var key_label = new Gtk.Label (key) {
                halign = Gtk.Align.END,
                xalign = 1
            };
            key_label.get_style_context ().add_class ("dim-label");

            var val_label = new Gtk.Label (value) {
                halign = Gtk.Align.START,
                xalign = 0,
                wrap = true,
                selectable = true
            };

            info_grid.attach (key_label, 0, row, 1, 1);
            info_grid.attach (val_label, 1, row, 1, 1);
            row++;
        }
    }
}
```

- [ ] **Step 2: Registrar el fitxer a meson**

A `src/meson.build`, després de la línia `'View/Widgets/OverlayBar.vala',` (línia ~57), afegeix:

```meson
    'View/Widgets/PreviewColumn.vala',
```

- [ ] **Step 3: Compilar (el widget encara no s'usa, però ha de compilar)**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors. (Pot aparèixer un avís que `PreviewColumn` no s'usa fins a la Task 2; l'objectiu és que compili.)

- [ ] **Step 4: Commit**

```bash
git add src/View/Widgets/PreviewColumn.vala src/meson.build
git commit -m "PreviewColumn: widget de vista prèvia (miniatura + metadades)"
```

---

## Task 2: Mostrar/treure el preview a Miller

**Files:**
- Modify: `src/View/Miller.vala`

- [ ] **Step 1: Afegir els camps d'estat**

A `src/View/Miller.vala`, a la zona de camps (a prop de `public int total_width = 0;`, línia ~36), afegeix:

```vala
        private View.PreviewColumn? preview_column = null;
        private int preview_width = 0;
```

- [ ] **Step 2: Disparar l'actualització del preview en canviar la selecció**

Substitueix `on_slot_selection_changed` (línia ~427):

```vala
        private void on_slot_selection_changed (GLib.List<Files.File> files) {
            selection_changed (files);
        }
```

per:

```vala
        private void on_slot_selection_changed (GLib.List<Files.File> files) {
            selection_changed (files);
            update_preview (files);
        }

        private void update_preview (GLib.List<Files.File> files) {
            remove_preview ();

            unowned View.Slot? last = (slot_list != null && slot_list.last () != null)
                                          ? slot_list.last ().data : null;

            /* Only for a single, non-folder file selected in the last column. */
            if (last != null && current_slot == last &&
                files != null && files.data != null && files.next == null &&
                !files.data.is_folder ()) {

                preview_column = new View.PreviewColumn () {
                    hexpand = true
                };
                preview_column.set_file (files.data);
                preview_width = last.width;
                preview_column.set_size_request (preview_width, -1);
                preview_column.show_all ();
                last.colpane.add (preview_column);
                update_total_width ();
                scroll_to_preview ();
            }
        }

        private void remove_preview () {
            if (preview_column != null) {
                if (preview_column.parent != null) {
                    ((Gtk.Container) preview_column.parent).remove (preview_column);
                }
                preview_column.destroy ();
                preview_column = null;
                preview_width = 0;
                update_total_width ();
            }
        }

        private void scroll_to_preview () {
            GLib.Timeout.add (250, () => {
                if (!scrolled_window.get_realized ()) {
                    return Source.CONTINUE;
                }
                smooth_adjustment_to (this.hadj, (int) hadj.upper);
                return Source.REMOVE;
            });
        }
```

- [ ] **Step 3: Treure el preview en navegar a una carpeta**

A `add_location` (línia ~94), just després de la línia d'obertura `public void add_location (GLib.File loc, View.Slot? host = null) {`, afegeix com a primera instrucció:

```vala
            remove_preview ();
```

- [ ] **Step 4: Incloure l'amplada del preview al total**

A `calculate_total_width` (línia ~151), afegeix la contribució del preview abans del tancament del mètode:

```vala
        private void calculate_total_width () {
            total_width = 100; // Extra space to allow increasing the size of columns by dragging the edge
            slot_list.@foreach ((slot) => {
                total_width += slot.width;
            });

            if (preview_column != null) {
                total_width += preview_width;
            }
        }
```

- [ ] **Step 5: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 6: Commit**

```bash
git add src/View/Miller.vala
git commit -m "Miller: mostrar la columna de preview en seleccionar un fitxer"
```

---

## Task 3: Compilació, instal·lació i verificació manual

**Files:** cap (verificació).

- [ ] **Step 1: Compilar el projecte sencer**

Run: `ninja -C /home/marc/src/files/build`
Expected: build complet sense errors.

- [ ] **Step 2: Instal·lar al prefix /opt**

Run: `sudo ninja -C /home/marc/src/files/build install`
Expected: instal·la a `/opt/pantheon-files` (demana contrasenya sudo).

- [ ] **Step 3: Llançar l'app en vista de columnes**

Run: `~/.local/bin/io.elementary.files &`
Després, canvia a la vista de columnes (Miller) i navega a una carpeta amb fitxers variats.

- [ ] **Step 4: Verificacions manuals**

1. Seleccionar una **imatge** → columna de preview a la dreta amb miniatura real + Tipus/Mida/Dimensions/Modificat.
2. Seleccionar un **PDF** → miniatura (si el sistema en genera) o icona MIME gran.
3. Seleccionar un **fitxer de text** o sense miniatura → icona MIME gran + metadades (sense fila Dimensions).
4. Seleccionar una **carpeta** → s'obre columna de contingut, **sense** preview.
5. **Selecció múltiple** o **deseleccionar** → desapareix el preview.
6. Navegar a una carpeta tenint un preview obert → el preview se substitueix per la columna nova.
7. **Redimensionar** arrossegant la vora entre la darrera columna i el preview → funciona com les altres columnes.
8. Canvi ràpid de selecció entre fitxers grans → sense miniatures creuades ni errors a la consola.

- [ ] **Step 5: Commit final si calen ajustos**

Si la verificació obliga a retocs (mida de miniatura, camps, espaiat), fes-los i commiteja amb un missatge descriptiu.

---

## Self-review (cobertura de l'spec)

- Component `PreviewColumn` (miniatura + nom + separador + graella) → Task 1. ✓
- Miniatures via `get_icon_pixbuf` + `Thumbnailer` async amb cancel·lació → Task 1 (`update_image`/`set_file`/`on_thumbnail_finished`/`disconnect_thumb`). ✓
- Metadades (tipus, mida, dimensions només imatges, modificat) amb omissió de buits → Task 1 (`populate_info`/`add_info_row`). ✓
- Aparició només amb 1 fitxer no-carpeta al darrer slot → Task 2 (`update_preview`). ✓
- Treure el preview en carpeta/múltiple/buida i en navegar → Task 2 (`remove_preview`, crida a `add_location`). ✓
- Amplada de columna + redimensionable (colpane del darrer slot + Paned existent) → Task 2 (`set_size_request` + ubicació a `last.colpane`). ✓
- Scroll fins al preview → Task 2 (`scroll_to_preview`). ✓
- Amplada total inclou el preview → Task 2 (`calculate_total_width`). ✓
- Registre a meson → Task 1 Step 2. ✓
- Abast només Miller; icones/llista intactes → cap canvi en aquells fitxers. ✓
- Gestió d'errors (sense miniatura → icona; canvi ràpid → descartar; dimensions només imatge) → Task 1. ✓
- Proves manuals → Task 3. ✓
