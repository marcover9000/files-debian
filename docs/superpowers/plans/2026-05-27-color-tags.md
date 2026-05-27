# Tags de colors (part A) — Pla d'implementació

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Etiquetar fitxers amb colors estil Finder (diverses per fitxer), desats a metadades GVfs, visibles com a punts a les vistes i a la columna de preview, i gestionats des del menú contextual.

**Architecture:** Una utilitat `Files.TagManager` (libcore) defineix la paleta i genera els punts de color. `Files.File` parseja/escriu l'atribut `metadata::files-tags` i afegeix emblemes `tag:<clau>`. `EmblemRenderer` pinta aquests emblemes amb els punts de `TagManager`. El menú contextual (`AbstractDirectoryView`) ofereix un submenú per assignar/treure, i `PreviewColumn` mostra una fila d'etiquetes.

**Tech Stack:** Vala, GTK3, Gee, Cairo, GVfs metadata, Meson/Ninja. Sense tests unitaris → compilació + verificació manual.

**Nota sobre TDD:** No hi ha harness de tests per a aquest codi GTK/GIO; cada tasca usa `ninja -C build` com a porta automàtica i acaba amb verificació manual.

---

## Estructura de fitxers

- **Create:** `libcore/TagManager.vala` — paleta (claus, noms, colors) + generació cachejada dels punts.
- **Modify:** `libcore/meson.build` — registrar el fitxer nou.
- **Modify:** `libcore/File.vala` — atribut `metadata::files-tags`, camp `tags`, parseig, `set_tags`/`has_tag`, emblemes `tag:`.
- **Modify:** `src/EmblemRenderer.vala` — pintar els emblemes amb prefix `tag:` com a punts de color.
- **Modify:** `src/View/AbstractDirectoryView.vala` — submenú "Tags" al menú contextual.
- **Modify:** `src/View/Widgets/PreviewColumn.vala` — fila d'etiquetes a la graella de metadades.

---

## Task 1: TagManager (paleta + punts)

**Files:**
- Create: `libcore/TagManager.vala`
- Modify: `libcore/meson.build`

- [ ] **Step 1: Crear el fitxer**

Crea `libcore/TagManager.vala`:

```vala
/*
 * Central registry for the fixed Finder-style colour tag palette: keys,
 * localized names, colours, and cached coloured-dot pixbufs.
 */

namespace Files {
    public class TagManager : GLib.Object {
        private const string[] KEYS = {
            "red", "orange", "yellow", "green", "blue", "purple", "gray"
        };

        private static Gee.HashMap<string, Gdk.Pixbuf>? dot_cache = null;

        public static unowned string[] all_keys () {
            return KEYS;
        }

        public static bool is_valid (string key) {
            foreach (unowned string k in KEYS) {
                if (k == key) {
                    return true;
                }
            }
            return false;
        }

        public static string display_name (string key) {
            switch (key) {
                case "red": return _("Red");
                case "orange": return _("Orange");
                case "yellow": return _("Yellow");
                case "green": return _("Green");
                case "blue": return _("Blue");
                case "purple": return _("Purple");
                case "gray": return _("Gray");
                default: return key;
            }
        }

        public static Gdk.RGBA color (string key) {
            var rgba = Gdk.RGBA ();
            switch (key) {
                case "red": rgba.parse ("#e01b24"); break;
                case "orange": rgba.parse ("#ff7800"); break;
                case "yellow": rgba.parse ("#f6d32d"); break;
                case "green": rgba.parse ("#33d17a"); break;
                case "blue": rgba.parse ("#3584e4"); break;
                case "purple": rgba.parse ("#9141ac"); break;
                default: rgba.parse ("#9a9996"); break; // gray / fallback
            }
            return rgba;
        }

        /* Filled circle of the tag colour, cached by (key, device pixels). */
        public static Gdk.Pixbuf? dot_pixbuf (string key, int size, int scale) {
            if (!is_valid (key)) {
                return null;
            }
            if (dot_cache == null) {
                dot_cache = new Gee.HashMap<string, Gdk.Pixbuf> ();
            }

            int px = size * scale;
            var cache_key = "%s-%d".printf (key, px);
            if (dot_cache.has_key (cache_key)) {
                return dot_cache.@get (cache_key);
            }

            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, px, px);
            var cr = new Cairo.Context (surface);
            var rgba = color (key);
            double r = px / 2.0;
            double margin = px * 0.12;
            cr.arc (r, r, r - margin, 0, 2 * GLib.Math.PI);
            cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, 1.0);
            cr.fill_preserve ();
            cr.set_source_rgba (0, 0, 0, 0.18); // subtle outline for contrast
            cr.set_line_width (px * 0.06);
            cr.stroke ();
            surface.flush ();

            var pix = Gdk.pixbuf_get_from_surface (surface, 0, 0, px, px);
            if (pix != null) {
                dot_cache.@set (cache_key, pix);
            }
            return pix;
        }
    }
}
```

- [ ] **Step 2: Registrar a meson**

A `libcore/meson.build`, després de la línia `'File.vala',` (línia ~23), afegeix:

```meson
    'TagManager.vala',
```

- [ ] **Step 3: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: meson reconfigura; compila sense errors (encara sense usar TagManager).

- [ ] **Step 4: Commit**

```bash
git add libcore/TagManager.vala libcore/meson.build
git commit -m "TagManager: paleta de tags de colors i punts cachejats"
```

---

## Task 2: Model de tags a Files.File

**Files:**
- Modify: `libcore/File.vala`

- [ ] **Step 1: Sol·licitar l'atribut de tags**

A `libcore/File.vala`, a la cadena d'atributs (línia ~38), canvia el final:

```vala
        "thumbnail::*,mountable::*,metadata::marlin-sort-column-id,metadata::marlin-sort-reversed";
```

per:

```vala
        "thumbnail::*,mountable::*,metadata::marlin-sort-column-id,metadata::marlin-sort-reversed," +
        "metadata::files-tags";
```

- [ ] **Step 2: Afegir el camp `tags`**

A prop de `public uint n_emblems = 0;` (línia ~54), afegeix:

```vala
        public string[] tags = {};
```

- [ ] **Step 3: Parsejar els tags en processar la info**

A `libcore/File.vala`, dins el bloc de metadata, just després del tancament del bloc `if (is_directory) { … marlin-sort … }` (línia ~566, abans de `if (info.has_attribute (GLib.FileAttribute.STANDARD_ICON))`), afegeix:

```vala
        if (info.has_attribute ("metadata::files-tags")) {
            tags = parse_tags (info.get_attribute_string ("metadata::files-tags"));
        } else {
            tags = {};
        }
```

- [ ] **Step 4: Afegir els helpers de tags**

Just abans de `public void update_emblem () {` (línia ~1087), afegeix:

```vala
        private static string[] parse_tags (string? csv) {
            string[] result = {};
            if (csv == null || csv == "") {
                return result;
            }
            foreach (unowned string part in csv.split (",")) {
                var key = part.strip ();
                if (key != "" && TagManager.is_valid (key) && !(key in result)) {
                    result += key;
                }
            }
            return result;
        }

        public bool has_tag (string key) {
            foreach (unowned string t in tags) {
                if (t == key) {
                    return true;
                }
            }
            return false;
        }

        public void set_tags (string[] keys) {
            tags = keys;

            var ginfo = new GLib.FileInfo ();
            ginfo.set_attribute_string ("metadata::files-tags", string.joinv (",", keys));
            location.set_attributes_async.begin (
                ginfo, GLib.FileQueryInfoFlags.NONE, GLib.Priority.DEFAULT, null,
                (obj, res) => {
                    try {
                        GLib.FileInfo unused;
                        location.set_attributes_async.end (res, out unused);
                    } catch (Error e) {
                        warning ("Could not write tags for %s: %s", basename, e.message);
                    }
                }
            );

            update_emblem ();
            icon_changed (); // force redraw even when no emblems remain
        }
```

- [ ] **Step 5: Afegir els emblemes de tag a `update_emblem`**

A `update_emblem ()`, just abans del tancament `}` del mètode (després del bloc `if (!is_writable () …)`, línia ~1118), afegeix:

```vala
            foreach (unowned string tag in tags) {
                add_emblem ("tag:" + tag);
            }
```

- [ ] **Step 6: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 7: Commit**

```bash
git add libcore/File.vala
git commit -m "File: model de tags (metadata::files-tags) + emblemes tag:"
```

---

## Task 3: Pintar els punts a EmblemRenderer

**Files:**
- Modify: `src/EmblemRenderer.vala`

- [ ] **Step 1: Interceptar el prefix `tag:` al bucle de render**

A `src/EmblemRenderer.vala`, substitueix el bloc dins `foreach (string emblem in file.emblems_list) {` que va des de `Gdk.Pixbuf? pix = null;` fins a tancar el `else`/assignació de cache (línies ~53-66):

```vala
        foreach (string emblem in file.emblems_list) {
            Gdk.Pixbuf? pix = null;
            var key = emblem + "-symbolic";

            if (emblem_pixbuf_map.has_key (key)) {
                pix = emblem_pixbuf_map.@get (key);
            } else {
                pix = render_icon (key, style_context);
                if (pix == null) {
                    continue;
                }

                emblem_pixbuf_map.@set (key, pix);
            }
```

per:

```vala
        foreach (string emblem in file.emblems_list) {
            Gdk.Pixbuf? pix = null;

            if (emblem.has_prefix ("tag:")) {
                pix = Files.TagManager.dot_pixbuf (
                    emblem.substring (4), (int) Files.IconSize.EMBLEM, icon_scale
                );
                if (pix == null) {
                    continue;
                }
            } else {
                var key = emblem + "-symbolic";
                if (emblem_pixbuf_map.has_key (key)) {
                    pix = emblem_pixbuf_map.@get (key);
                } else {
                    pix = render_icon (key, style_context);
                    if (pix == null) {
                        continue;
                    }
                    emblem_pixbuf_map.@set (key, pix);
                }
            }
```

(La resta del cos del bucle —càlcul de `emblem_area` i `style_context.render_icon (…)`— es manté igual.)

- [ ] **Step 2: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 3: Commit**

```bash
git add src/EmblemRenderer.vala
git commit -m "EmblemRenderer: pintar emblemes tag: com a punts de color"
```

---

## Task 4: Submenú de tags al menú contextual

**Files:**
- Modify: `src/View/AbstractDirectoryView.vala`

- [ ] **Step 1: Afegir el mètode auxiliar**

A `src/View/AbstractDirectoryView.vala`, just abans de `protected void show_context_menu (Gdk.Event event) requires (window != null) {` (línia ~1907), afegeix:

```vala
        private void append_tags_menu (Gtk.Menu menu, unowned GLib.List<Files.File> selection) {
            var tags_item = new Gtk.MenuItem.with_label (_("Tags"));
            var submenu = new Gtk.Menu ();

            foreach (unowned string key in Files.TagManager.all_keys ()) {
                bool all_have = true;
                foreach (unowned Files.File f in selection) {
                    if (!f.has_tag (key)) {
                        all_have = false;
                        break;
                    }
                }

                var item = new Gtk.CheckMenuItem.with_label (Files.TagManager.display_name (key));
                item.active = all_have;
                var captured_key = key;
                item.toggled.connect (() => {
                    foreach (unowned Files.File f in selection) {
                        string[] updated = {};
                        if (item.active) {
                            updated = f.tags;
                            if (!(captured_key in updated)) {
                                updated += captured_key;
                            }
                        } else {
                            foreach (unowned string t in f.tags) {
                                if (t != captured_key) {
                                    updated += t;
                                }
                            }
                        }
                        f.set_tags (updated);
                    }
                });
                submenu.add (item);
            }

            submenu.add (new Gtk.SeparatorMenuItem ());
            var clear_item = new Gtk.MenuItem.with_label (_("Clear Tags"));
            clear_item.activate.connect (() => {
                foreach (unowned Files.File f in selection) {
                    f.set_tags (new string[0]);
                }
            });
            submenu.add (clear_item);

            tags_item.submenu = submenu;
            tags_item.show_all ();
            menu.add (tags_item);
        }
```

- [ ] **Step 2: Inserir el submenú al branch de selecció normal**

A `show_context_menu`, al branch de selecció de fitxers (no paperera, no recents), substitueix (línia ~2249-2257):

```vala
                    /* Do  not offer to bookmark if location is already bookmarked */
                    if (common_actions.get_action_enabled ("bookmark") &&
                        window.can_bookmark_uri (selected_files.data.uri)) {

                        menu.add (bookmark_menuitem);
                    }

                    menu.add (new Gtk.SeparatorMenuItem ());
                    menu.add (properties_menuitem);
                }
```

per:

```vala
                    /* Do  not offer to bookmark if location is already bookmarked */
                    if (common_actions.get_action_enabled ("bookmark") &&
                        window.can_bookmark_uri (selected_files.data.uri)) {

                        menu.add (bookmark_menuitem);
                    }

                    menu.add (new Gtk.SeparatorMenuItem ());
                    append_tags_menu (menu, selected_files);
                    menu.add (new Gtk.SeparatorMenuItem ());
                    menu.add (properties_menuitem);
                }
```

- [ ] **Step 3: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 4: Commit**

```bash
git add src/View/AbstractDirectoryView.vala
git commit -m "AbstractDirectoryView: submenú Tags al menú contextual"
```

---

## Task 5: Fila de tags a la columna de preview

**Files:**
- Modify: `src/View/Widgets/PreviewColumn.vala`

- [ ] **Step 1: Mostrar els tags a `populate_info`**

A `src/View/Widgets/PreviewColumn.vala`, dins `populate_info`, just abans de `info_grid.show_all ();`, afegeix:

```vala
            if (file.tags.length > 0) {
                var tags_key = new Gtk.Label (_("Tags")) {
                    halign = Gtk.Align.END,
                    xalign = 1
                };
                tags_key.get_style_context ().add_class ("dim-label");

                var tags_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                    halign = Gtk.Align.START
                };
                var scale = get_scale_factor ();
                foreach (unowned string key in file.tags) {
                    var dot = Files.TagManager.dot_pixbuf (key, 12, scale);
                    if (dot != null) {
                        tags_box.add (new Gtk.Image.from_surface (
                            Gdk.cairo_surface_create_from_pixbuf (dot, scale, null)
                        ));
                    }
                }
                var names = new string[file.tags.length];
                for (int i = 0; i < file.tags.length; i++) {
                    names[i] = Files.TagManager.display_name (file.tags[i]);
                }
                tags_box.add (new Gtk.Label (string.joinv (", ", names)) {
                    xalign = 0
                });

                info_grid.attach (tags_key, 0, row, 1, 1);
                info_grid.attach (tags_box, 1, row, 1, 1);
                row++;
            }
```

(El comptador `row` ja existeix a `populate_info`, just després de les crides `add_info_row (ref row, …)`.)

- [ ] **Step 2: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 3: Commit**

```bash
git add src/View/Widgets/PreviewColumn.vala
git commit -m "PreviewColumn: mostrar les etiquetes del fitxer seleccionat"
```

---

## Task 6: Compilació, instal·lació i verificació manual

**Files:** cap (verificació).

- [ ] **Step 1: Compilar el projecte sencer**

Run: `ninja -C /home/marc/src/files/build`
Expected: build complet sense errors.

- [ ] **Step 2: Instal·lar**

Run: `sudo ninja -C /home/marc/src/files/build install`
Expected: instal·la a `/opt/pantheon-files` (demana contrasenya sudo).

- [ ] **Step 3: Llançar**

Run: `~/.local/bin/io.elementary.files &`

- [ ] **Step 4: Verificacions manuals**

1. Clic dret sobre un fitxer → submenú **"Tags"** amb els 7 colors + "Clear Tags".
2. Marcar un color → apareix el punt sobre la icona i el ✓ queda marcat.
3. Marcar-ne un segon → dos punts.
4. Desmarcar → desapareix el punt.
5. "Clear Tags" → desapareixen tots.
6. Selecció **múltiple** → s'aplica/treu a tots; ✓ marcat només si tots el tenen.
7. **Persistència:** tancar i reobrir Files → els tags hi són.
8. Punts visibles a vistes **icones, llista i columnes**.
9. Seleccionar un fitxer etiquetat → la **columna de preview** mostra la fila "Tags" amb punts + noms.

- [ ] **Step 5: Commit final si calen ajustos**

Si cal retocar (mida del punt, posició, colors), fes-ho i commiteja.

---

## Self-review (cobertura de l'spec)

- Paleta fixa 7 colors → Task 1 (`TagManager`). ✓
- Emmagatzematge `metadata::files-tags` (CSV) → Task 2 (atribut + `parse_tags` + `set_tags`). ✓
- Multi-etiqueta → `tags` és `string[]`; menú afegeix/treu individualment. ✓
- Assignar/treure al menú contextual amb ✓ per selecció + "Clear Tags" → Task 4. ✓
- Punts a les vistes via emblemes → Task 2 (`tag:` emblems) + Task 3 (EmblemRenderer). ✓
- Tags a la columna de preview → Task 5. ✓
- Gestió d'errors: backend sense metadata (catch a `set_tags`), clau desconeguda (`parse_tags` filtra), atribut absent (llista buida) → Tasks 1-2. ✓
- Refresc en assignar (`icon_changed`) → Task 2. ✓
- Abast: només part A; cap canvi a la barra lateral → ✓.
- Proves manuals → Task 6. ✓
