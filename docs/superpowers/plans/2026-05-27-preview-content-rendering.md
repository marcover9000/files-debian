# Preview de contingut real per tipus — Pla d'implementació

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que la columna de preview de Miller renderitzi el contingut real del fitxer (imatge, primera pàgina de PDF, text amb scroll) i, si no es pot, l'icona MIME.

**Architecture:** Es reescriu `PreviewColumn` perquè, segons el content-type, despatxi un renderitzador (imatge / PDF via poppler / text / icona) cap a una zona `content_holder` que canvia de widget; el nom i la graella de metadades es mantenen a sota. S'afegeix la dependència `poppler-glib` al build.

**Tech Stack:** Vala, GTK3, Granite 6.x, poppler-glib 22.x, Cairo, Meson/Ninja. Sense tests unitaris → compilació + verificació manual.

**Nota sobre TDD:** No hi ha harness de tests per a widgets GTK; cada tasca usa `ninja -C build` com a porta automàtica i acaba amb verificació manual.

---

## Estructura de fitxers

- **Modify:** `meson.build` (arrel) — declarar `poppler_dep = dependency('poppler-glib')`.
- **Modify:** `src/meson.build` — afegir `poppler_dep` a `pantheon_files_deps` (meson passa `--pkg poppler-glib` automàticament).
- **Modify (reescriptura):** `src/View/Widgets/PreviewColumn.vala` — disposició nova + despatx per tipus + renderitzadors + cancel·lació.

---

## Task 1: Afegir la dependència poppler-glib

**Files:**
- Modify: `meson.build`
- Modify: `src/meson.build`

- [ ] **Step 1: Declarar la dependència a l'arrel**

A `meson.build`, just després de la línia `portal_gtk3_dep = dependency('libportal-gtk3')` (línia ~52), afegeix:

```meson
poppler_dep = dependency('poppler-glib')
```

- [ ] **Step 2: Afegir-la a les deps de l'executable**

A `src/meson.build`, dins la llista `pantheon_files_deps` (línies ~1-9), afegeix `poppler_dep` (p. ex. després de `portal_gtk3_dep`):

```meson
pantheon_files_deps = [
    common_deps,
    handy_dep,
    pantheon_files_core_dep,
    zeitgeist_dep,
    project_config_dep,
    portal_dep,
    portal_gtk3_dep,
    poppler_dep
]
```

- [ ] **Step 3: Reconfigurar i compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: meson reconfigura sol; compila sense errors (encara sense usar poppler).

- [ ] **Step 4: Commit**

```bash
git add meson.build src/meson.build
git commit -m "build: afegir dependència poppler-glib"
```

---

## Task 2: Reescriure PreviewColumn amb renderitzat per tipus

**Files:**
- Modify: `src/View/Widgets/PreviewColumn.vala`

- [ ] **Step 1: Substituir tot el contingut del fitxer**

Reemplaça TOT `src/View/Widgets/PreviewColumn.vala` per:

```vala
/*
 * Finder-style preview column for the Miller (column) view.
 * Renders the actual content of the selected file (image, PDF first page, text)
 * with a large icon fallback, plus a metadata grid.
 */

namespace Files.View {
    public class PreviewColumn : Gtk.Box {
        private const int ICON_SIZE = 256;
        private const size_t MAX_TEXT_BYTES = 10 * 1024 * 1024; // 10 MB safety cap
        private const string[] TEXT_ALLOWLIST = {
            "application/json", "application/xml", "application/x-yaml",
            "application/javascript", "application/x-shellscript",
            "application/toml", "application/x-desktop"
        };

        private Gtk.Box content_holder;
        private Gtk.Label name_label;
        private Gtk.Grid info_grid;
        private Files.File? current_file = null;
        private Cancellable? cancellable = null;

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            spacing = 6;
            get_style_context ().add_class ("files-preview-column");

            content_holder = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                vexpand = true,
                halign = Gtk.Align.FILL,
                valign = Gtk.Align.FILL,
                margin = 12
            };

            name_label = new Gtk.Label (null) {
                halign = Gtk.Align.CENTER,
                ellipsize = Pango.EllipsizeMode.MIDDLE,
                max_width_chars = 24,
                margin_start = 12,
                margin_end = 12
            };
            name_label.get_style_context ().add_class ("heading");

            info_grid = new Gtk.Grid () {
                column_spacing = 8,
                row_spacing = 4,
                margin = 12,
                margin_top = 6,
                halign = Gtk.Align.FILL
            };

            add (content_holder);
            add (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            add (name_label);
            add (info_grid);
            show_all ();
        }

        ~PreviewColumn () {
            if (cancellable != null) {
                cancellable.cancel ();
            }
        }

        public void set_file (Files.File? file) {
            if (cancellable != null) {
                cancellable.cancel ();
            }
            cancellable = new Cancellable ();
            current_file = file;

            clear_content ();
            if (file == null) {
                return;
            }

            populate_info (file);

            unowned string? ctype = file.get_ftype ();
            if (file.is_image () || (ctype != null && GLib.ContentType.is_a (ctype, "image/*"))) {
                render_image.begin (file, cancellable);
            } else if (ctype == "application/pdf") {
                render_pdf (file);
            } else if (looks_like_text (ctype)) {
                render_text.begin (file, cancellable);
            } else {
                render_icon (file);
            }
        }

        private bool looks_like_text (string? ctype) {
            if (ctype == null || ctype == "application/octet-stream") {
                return true; // unknown: try as text; render_text validates UTF-8 and falls back
            }
            if (GLib.ContentType.is_a (ctype, "text/plain") || ctype.has_prefix ("text/")) {
                return true;
            }
            foreach (unowned string t in TEXT_ALLOWLIST) {
                if (ctype == t) {
                    return true;
                }
            }
            return false;
        }

        private void clear_content () {
            content_holder.@foreach ((w) => {
                w.destroy ();
            });
        }

        private int target_width () {
            int w = get_allocated_width ();
            return (w > 48) ? w - 24 : ICON_SIZE; // minus margins; fallback before allocation
        }

        private void show_surface (Cairo.Surface surface) {
            clear_content ();
            var image = new Gtk.Image.from_surface (surface) {
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.START
            };
            content_holder.add (image);
            content_holder.show_all ();
        }

        private void render_icon (Files.File file) {
            var scale = get_scale_factor ();
            var pix = file.get_icon_pixbuf (ICON_SIZE, scale);
            if (pix != null) {
                show_surface (Gdk.cairo_surface_create_from_pixbuf (pix, scale, null));
            }
        }

        private async void render_image (Files.File file, Cancellable cancel) {
            try {
                var stream = yield file.location.read_async (GLib.Priority.DEFAULT, cancel);
                var scale = get_scale_factor ();
                int w = target_width () * scale;
                var pix = yield new Gdk.Pixbuf.from_stream_at_scale_async (
                    stream, w, -1, true, cancel
                );
                if (cancel.is_cancelled () || current_file != file) {
                    return;
                }
                if (pix != null) {
                    show_surface (Gdk.cairo_surface_create_from_pixbuf (pix, scale, null));
                }
            } catch (Error e) {
                if (!cancel.is_cancelled () && current_file == file) {
                    render_icon (file);
                }
            }
        }

        private void render_pdf (Files.File file) {
            try {
                var doc = new Poppler.Document.from_gfile (file.location, null, cancellable);
                if (doc.get_n_pages () < 1) {
                    render_icon (file);
                    return;
                }

                var page = doc.get_page (0);
                double pw, ph;
                page.get_size (out pw, out ph);

                var scale = get_scale_factor ();
                double target = target_width () * scale;
                double factor = (pw > 0) ? target / pw : 1.0;
                int sw = (int) (pw * factor);
                int sh = (int) (ph * factor);
                if (sw < 1 || sh < 1) {
                    render_icon (file);
                    return;
                }

                var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, sw, sh);
                var ctx = new Cairo.Context (surface);
                ctx.set_source_rgb (1, 1, 1); // white page background
                ctx.paint ();
                ctx.scale (factor, factor);
                page.render (ctx);
                surface.flush ();

                show_surface (surface);
            } catch (Error e) {
                render_icon (file);
            }
        }

        private async void render_text (Files.File file, Cancellable cancel) {
            try {
                var stream = yield file.location.read_async (GLib.Priority.DEFAULT, cancel);
                var data = new GLib.ByteArray ();
                var buffer = new uint8[65536];
                while (data.len < MAX_TEXT_BYTES) {
                    ssize_t n = yield stream.read_async (buffer, GLib.Priority.DEFAULT, cancel);
                    if (n <= 0) {
                        break;
                    }
                    data.append (buffer[0:n]);
                }

                if (cancel.is_cancelled () || current_file != file) {
                    return;
                }

                unowned string text = (string) data.data;
                if (!text.validate ((ssize_t) data.len)) {
                    render_icon (file); // not valid UTF-8 → treat as binary
                    return;
                }

                clear_content ();
                var view = new Gtk.TextView () {
                    editable = false,
                    cursor_visible = false,
                    monospace = true,
                    wrap_mode = Gtk.WrapMode.WORD_CHAR,
                    left_margin = 6,
                    right_margin = 6,
                    top_margin = 6,
                    bottom_margin = 6
                };
                view.buffer.set_text (text, (int) data.len);

                var scroller = new Gtk.ScrolledWindow (null, null) {
                    hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                    vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                    vexpand = true,
                    child = view
                };
                content_holder.add (scroller);
                content_holder.show_all ();
            } catch (Error e) {
                if (!cancel.is_cancelled () && current_file == file) {
                    render_icon (file);
                }
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

- [ ] **Step 2: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors. Si valac es queixa de `from_stream_at_scale_async` o `read_async`, vol dir que cal ajustar la signatura (prioritat/cancellable) — corregeix segons l'error i recompila.

- [ ] **Step 3: Commit**

```bash
git add src/View/Widgets/PreviewColumn.vala
git commit -m "PreviewColumn: renderitzar contingut real (imatge/PDF/text) amb fallback a icona"
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

- [ ] **Step 4: Verificacions manuals**

1. **Imatge** (JPG/PNG) → es veu la imatge escalada, no l'icona.
2. **PDF** → primera pàgina renderitzada amb fons blanc.
3. **.md / .txt / .env / codi / .json** → contingut com a text monoespai amb scroll.
4. **Dotfile** (p. ex. `.gitignore`) → es mostra com a text.
5. **Binari / executable / tipus desconegut no-text** → icona MIME gran.
6. **Fitxer de text molt gran** (>10 MB) → no es penja; mostra fins al límit.
7. **Canvi ràpid** entre fitxers de tipus diferents → sense previews creuats ni errors a la consola.
8. Carpeta / selecció múltiple / deseleccionar → desapareix el preview (no ha de regressar).

- [ ] **Step 5: Commit final si calen ajustos**

Si la verificació obliga a retocs (mida, marges, tipus considerats text), fes-los i commiteja.

---

## Self-review (cobertura de l'spec)

- Dependència poppler-glib → Task 1. ✓
- Disposició nova (Box + content_holder + nom + metadades) → Task 2 (`construct`). ✓
- Despatx per tipus (imatge/PDF/text/icona) → Task 2 (`set_file`). ✓
- Detecció ampla de text (is_a text/plain, prefix text/, allowlist, octet-stream/null→sniff via UTF-8 validate) → Task 2 (`looks_like_text` + `render_text`). ✓
- Imatge real escalada → Task 2 (`render_image`). ✓
- PDF primera pàgina via poppler → Task 2 (`render_pdf`). ✓
- Text sencer amb scroll + límit 10 MB → Task 2 (`render_text`, `MAX_TEXT_BYTES`). ✓
- Fallback a icona en error / no-text → Task 2 (`render_icon`, catch blocks, UTF-8 validate). ✓
- Async + cancel·lació en canvi de selecció → Task 2 (`cancellable`, comprovacions `is_cancelled`/`current_file != file`). ✓
- Metadades intactes → Task 2 (`populate_info`/`add_info_row`). ✓
- Abast només Miller; res d'altres vistes → cap canvi fora de PreviewColumn/meson. ✓
- Proves manuals → Task 3. ✓
