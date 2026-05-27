# Filtre per etiqueta a la barra lateral (③, `tag://`) — Pla d'implementació

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Una secció "Tags" a la barra lateral que llisti els colors en ús; en clicar-ne un, una ubicació virtual `tag://N` recorre la carpeta personal i mostra tots els fitxers amb aquell color.

**Architecture:** `Files.ColorTags` (libcore) manté un registre `used-tag-colors`. `Directory` (libcore) tracta l'esquema `tag` amb branques additives protegides per `is_tag`: curtcircuita la preparació (la ubicació no és GIO real) i enumera amb un recorregut recursiu propi de la carpeta personal llegint `metadata::color-tag`, alimentant els fitxers per la via normal. Un listbox simple a la barra lateral emet `path_change_request("tag://N")`.

**Tech Stack:** Vala, GTK3, GIO, GSettings, Meson/Ninja. Sense tests unitaris → compilació + verificació manual.

**Nota sobre TDD:** Sense harness de tests; cada tasca usa `ninja -C build` com a porta automàtica i acaba amb verificació manual. Les branques de `Directory` són additives (`if (is_tag)`), de manera que la navegació normal no es veu afectada.

---

## Estructura de fitxers

- **Modify:** `data/schemas/io.elementary.files.gschema.xml` — claus `used-tag-colors`, `sidebar-cat-tags-expander`.
- **Modify:** `libcore/ColorTags.vala` — registre de colors en ús.
- **Modify:** `plugins/pantheon-files-ctags/plugin.vala` — `mark_used` en assignar.
- **Modify:** `libcore/Directory.vala` — esquema `tag` + enumeració virtual.
- **Modify:** `libcore/Resources.vala` — `protocol_to_name` per a `tag`.
- **Modify:** `src/View/ViewContainer.vala` — títol de pestanya per a `tag://N`.
- **Create:** `src/View/Sidebar/TagListBox.vala` + **Modify** `src/meson.build` — secció de tags.
- **Modify:** `src/View/Sidebar/SidebarWindow.vala` — afegir la secció.

---

## Task 1: Claus gsettings

**Files:**
- Modify: `data/schemas/io.elementary.files.gschema.xml`

- [ ] **Step 1: Afegir les dues claus**

A `data/schemas/io.elementary.files.gschema.xml`, just després de la clau `color-tag-as-dot` (abans de `  </schema>` de l'schema `io.elementary.files.preferences`), afegeix:

```xml
    <key type="ai" name="used-tag-colors">
      <default>[]</default>
      <summary>Colour tag indices currently in use</summary>
      <description>Colour indices (1-10) that have at least one tagged file, shown in the sidebar Tags section.</description>
    </key>
    <key type="b" name="sidebar-cat-tags-expander">
      <default>true</default>
      <summary>Tags sidebar category expander state</summary>
      <description>Whether the Tags section of the sidebar is expanded.</description>
    </key>
```

- [ ] **Step 2: Validar**

Run: `glib-compile-schemas --dry-run /home/marc/src/files/data/schemas`
Expected: sense errors.

- [ ] **Step 3: Commit**

```bash
git add data/schemas/io.elementary.files.gschema.xml
git commit -m "schema: claus used-tag-colors i sidebar-cat-tags-expander"
```

---

## Task 2: Registre de colors en ús (ColorTags)

**Files:**
- Modify: `libcore/ColorTags.vala`

- [ ] **Step 1: Afegir els mètodes**

A `libcore/ColorTags.vala`, just abans del mètode `public static bool show_as_dot () {`, afegeix:

```vala
        public static int[] used_colors () {
            return get_settings ().get_value ("used-tag-colors").dup_int32 ();
        }

        public static void mark_used (int color) {
            if (color < 1 || color > 10) {
                return;
            }
            var current = used_colors ();
            foreach (int c in current) {
                if (c == color) {
                    return; // already listed
                }
            }
            current += color;
            get_settings ().set_value ("used-tag-colors", new GLib.Variant.array (new GLib.VariantType ("i"), variant_ints (current)));
        }

        public static void unmark_used (int color) {
            var current = used_colors ();
            int[] result = {};
            foreach (int c in current) {
                if (c != color) {
                    result += c;
                }
            }
            get_settings ().set_value ("used-tag-colors", new GLib.Variant.array (new GLib.VariantType ("i"), variant_ints (result)));
        }

        private static GLib.Variant[] variant_ints (int[] values) {
            GLib.Variant[] arr = {};
            foreach (int v in values) {
                arr += new GLib.Variant.int32 (v);
            }
            return arr;
        }
```

- [ ] **Step 2: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 3: Commit**

```bash
git add libcore/ColorTags.vala
git commit -m "ColorTags: registre de colors en ús (used-tag-colors)"
```

---

## Task 3: Marcar el color com a usat en assignar-lo

**Files:**
- Modify: `plugins/pantheon-files-ctags/plugin.vala`

- [ ] **Step 1: Cridar mark_used a set_color**

A `plugins/pantheon-files-ctags/plugin.vala`, dins `set_color`, substitueix:

```vala
            if (target_file.color != n) {
                target_file.color = n;
                target_file.location.set_attribute_string ("metadata::color-tag", n.to_string (), FileQueryInfoFlags.NONE);
                target_file.icon_changed ();
            }
```

per:

```vala
            if (target_file.color != n) {
                target_file.color = n;
                target_file.location.set_attribute_string ("metadata::color-tag", n.to_string (), FileQueryInfoFlags.NONE);
                target_file.icon_changed ();
                if (n >= 1) {
                    Files.ColorTags.mark_used (n);
                }
            }
```

- [ ] **Step 2: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 3: Commit**

```bash
git add plugins/pantheon-files-ctags/plugin.vala
git commit -m "ctags: marcar el color com a usat en assignar-lo"
```

---

## Task 4: Ubicació virtual tag:// a Directory

**Files:**
- Modify: `libcore/Directory.vala`

- [ ] **Step 1: Afegir el camp `is_tag`**

A `libcore/Directory.vala`, just després de `public bool is_recent {get; private set;}` (línia ~94), afegeix:

```vala
    public bool is_tag {get; private set;}
```

- [ ] **Step 2: Detectar l'esquema al construct**

A `libcore/Directory.vala`, al construct, substitueix:

```vala
        is_recent = (scheme == "recent");
        is_admin = (scheme == "admin");
```

per:

```vala
        is_recent = (scheme == "recent");
        is_tag = (scheme == "tag");
        is_admin = (scheme == "admin");
```

I substitueix:

```vala
        is_local = is_trash || is_recent || (scheme == "file");
```

per:

```vala
        is_local = is_trash || is_recent || is_tag || (scheme == "file");
```

- [ ] **Step 3: Curtcircuitar prepare_directory per a tag://**

A `prepare_directory` (línia ~249), just després de la línia d'obertura `debug ("Preparing directory for loading");`, afegeix:

```vala
        if (is_tag) {
            /* tag:// is not a real GIO location; give it a synthetic folder identity
             * and go straight to ready so the recursive scan can run. */
            var tag_info = new GLib.FileInfo ();
            tag_info.set_file_type (GLib.FileType.DIRECTORY);
            tag_info.set_name ("tag");
            tag_info.set_attribute_boolean (GLib.FileAttribute.STANDARD_IS_HIDDEN, false);
            file.info = tag_info;
            file.update ();
            yield make_ready (true, file_loaded_func, done_loading_func);
            return;
        }
```

- [ ] **Step 4: Ramificar la llista per a tag://**

A `list_directory_async` (línia ~670), just després de la comprovació inicial `if (!is_ready || file_hash.size () > 0) { ... return; }` (és a dir, abans de `if (!can_load) {`), afegeix:

```vala
        if (is_tag) {
            yield list_tag_async (file_loaded_func, done_loading_func);
            return;
        }
```

- [ ] **Step 5: Implementar l'enumeració recursiva**

A `libcore/Directory.vala`, just abans de `private void after_load_file (` (línia ~771), afegeix:

```vala
    private async void list_tag_async (FileLoadedFunc? file_loaded_func, DoneLoadingFunc? done_loading_func) {
        cancellable = new Cancellable ();
        displayed_files_count = 0;
        state = State.LOADING;

        int target_color = int.parse (location.get_uri ().substring ("tag://".length));
        bool show_hidden = Preferences.get_default ().show_hidden_files;
        const string ATTRS = "standard::name,standard::type,standard::is-hidden,standard::is-symlink," +
                             "standard::content-type,standard::size,time::*,metadata::color-tag";

        var queue = new GLib.Queue<GLib.File> ();
        queue.push_tail (GLib.File.new_for_path (GLib.Environment.get_home_dir ()));

        while (!cancellable.is_cancelled ()) {
            var dir = queue.pop_head ();
            if (dir == null) {
                break;
            }

            try {
                var e = yield dir.enumerate_children_async (ATTRS, GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, cancellable);
                while (!cancellable.is_cancelled ()) {
                    var infos = yield e.next_files_async (200, Priority.LOW, cancellable);
                    if (infos == null) {
                        break;
                    }
                    foreach (unowned var info in infos) {
                        var child = dir.get_child (info.get_name ());
                        if (info.get_file_type () == GLib.FileType.DIRECTORY) {
                            if (!info.get_is_symlink () && (show_hidden || !info.get_is_hidden ())) {
                                queue.push_tail (child);
                            }
                            continue;
                        }

                        if (info.has_attribute ("metadata::color-tag") &&
                            int.parse (info.get_attribute_string ("metadata::color-tag")) == target_color) {

                            var gof = Files.File.@get (child);
                            gof.info = info;
                            gof.update ();
                            file_hash.insert (gof.location, gof);
                            after_load_file (gof, show_hidden, file_loaded_func);
                        }
                    }
                }
            } catch (Error err) {
                debug ("tag scan: skipping %s: %s", dir.get_uri (), err.message);
            }
        }

        if (!cancellable.is_cancelled ()) {
            state = State.LOADED;
            if (displayed_files_count == 0) {
                ColorTags.unmark_used (target_color);
            }
        }

        after_loading (done_loading_func);
    }
```

- [ ] **Step 6: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 7: Commit**

```bash
git add libcore/Directory.vala
git commit -m "Directory: ubicació virtual tag:// (escaneig recursiu per color)"
```

---

## Task 5: Nom de l'esquema i títol de pestanya

**Files:**
- Modify: `libcore/Resources.vala`
- Modify: `src/View/ViewContainer.vala`

- [ ] **Step 1: protocol_to_name per a tag**

A `libcore/Resources.vala`, dins `protocol_to_name`, just després de `case "recent":\n                return _(Files.PROTOCOL_NAME_RECENT);`, afegeix:

```vala
            case "tag":
                return _("Tags");
```

- [ ] **Step 2: Títol de pestanya per a tag://N**

A `src/View/ViewContainer.vala`, dins `update_tab_name`, just després de la línia d'obertura `private void update_tab_name () {`, afegeix:

```vala
            if (this.uri.has_prefix ("tag://")) {
                this.tab_name = Files.ColorTags.display_name (int.parse (this.uri.substring ("tag://".length)));
                return;
            }
```

- [ ] **Step 3: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 4: Commit**

```bash
git add libcore/Resources.vala src/View/ViewContainer.vala
git commit -m "tag://: nom de l'esquema i títol de pestanya amb el nom del color"
```

---

## Task 6: Secció "Tags" a la barra lateral

**Files:**
- Create: `src/View/Sidebar/TagListBox.vala`
- Modify: `src/meson.build`
- Modify: `src/View/Sidebar/SidebarWindow.vala`

- [ ] **Step 1: Crear el listbox**

Crea `src/View/Sidebar/TagListBox.vala`:

```vala
/*
 * Simple sidebar list of the colour tags currently in use. Each row opens a
 * tag://N virtual location. Deliberately does NOT implement the heavy
 * SidebarListInterface/SidebarItemInterface — it just emits the sidebar's
 * path_change_request signal on activation.
 */

public class Sidebar.TagListBox : Gtk.ListBox {
    public Files.SidebarInterface sidebar { get; construct; }

    public TagListBox (Files.SidebarInterface sidebar) {
        Object (sidebar: sidebar);
    }

    construct {
        hexpand = true;
        selection_mode = Gtk.SelectionMode.SINGLE;

        row_activated.connect ((row) => {
            var tag_row = row as TagRow;
            if (tag_row != null) {
                sidebar.path_change_request (tag_row.uri, Files.OpenFlag.DEFAULT);
            }
        });

        refresh ();
    }

    public void refresh () {
        Gtk.ListBoxRow? r = get_row_at_index (0);
        while (r != null) {
            remove (r);
            r = get_row_at_index (0);
        }

        foreach (int color in Files.ColorTags.used_colors ()) {
            if (color >= 1 && color <= 10) {
                add (new TagRow (color));
            }
        }

        show_all ();
    }

    private class TagRow : Gtk.ListBoxRow {
        public string uri { get; construct; }
        public int color { get; construct; }

        public TagRow (int color) {
            Object (color: color, uri: "tag://" + color.to_string ());
        }

        construct {
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6) {
                margin_start = 12,
                margin_end = 12,
                margin_top = 4,
                margin_bottom = 4
            };
            box.add (new Gtk.Image.from_surface (make_dot (color)) {
                valign = Gtk.Align.CENTER
            });
            box.add (new Gtk.Label (Files.ColorTags.display_name (color)) {
                xalign = 0,
                hexpand = true,
                ellipsize = Pango.EllipsizeMode.END
            });
            add (box);
        }

        private Cairo.Surface make_dot (int color) {
            const int PX = 14;
            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, PX, PX);
            var cr = new Cairo.Context (surface);
            var rgba = Gdk.RGBA ();
            rgba.parse (Files.Preferences.TAGS_COLORS[color] ?? "#000000");
            cr.arc (PX / 2.0, PX / 2.0, PX / 2.0 - 1, 0, 2 * GLib.Math.PI);
            cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, 1.0);
            cr.fill ();
            surface.flush ();
            return surface;
        }
    }
}
```

- [ ] **Step 2: Registrar a meson**

A `src/meson.build`, després de la línia `'View/Sidebar/NetworkRow.vala',`, afegeix:

```meson
    'View/Sidebar/TagListBox.vala',
```

- [ ] **Step 3: Afegir els camps a SidebarWindow**

A `src/View/Sidebar/SidebarWindow.vala`, després de `private NetworkListBox network_listbox;`, afegeix:

```vala
    private TagListBox tag_listbox;
    private SidebarExpander tags_expander;
    private Gtk.Revealer tags_revealer;
```

- [ ] **Step 4: Crear el listbox i la secció al construct**

A `construct`, després de `network_listbox = new NetworkListBox (this);`, afegeix:

```vala
        tag_listbox = new TagListBox (this);
```

I després del bloc del `network_revealer`:

```vala
        var network_revealer = new Gtk.Revealer () {
            child = network_listbox
        };
```

afegeix:

```vala
        tags_expander = new SidebarExpander (_("Tags")) {
            tooltip_text = _("Files grouped by colour tag")
        };

        tags_revealer = new Gtk.Revealer () {
            child = tag_listbox
        };
```

- [ ] **Step 5: Afegir la secció al box**

A `construct`, després de `bookmarklists_box.add (network_revealer);`, afegeix:

```vala
        bookmarklists_box.add (tags_expander);
        bookmarklists_box.add (tags_revealer);
```

- [ ] **Step 6: Lligar estat i visibilitat**

A `construct`, després de
`network_expander.bind_property ("active", network_revealer, "reveal-child", GLib.BindingFlags.SYNC_CREATE);`,
afegeix:

```vala
        Files.app_settings.bind (
            "sidebar-cat-tags-expander", tags_expander, "active", SettingsBindFlags.DEFAULT
        );
        tags_expander.bind_property ("active", tags_revealer, "reveal-child", GLib.BindingFlags.SYNC_CREATE);

        update_tags_visibility ();
        Files.app_settings.changed["used-tag-colors"].connect (() => {
            tag_listbox.refresh ();
            update_tags_visibility ();
        });
```

- [ ] **Step 7: Afegir el mètode de visibilitat**

A `src/View/Sidebar/SidebarWindow.vala`, just abans de `private void refresh (bool bookmarks = true, ...)`, afegeix:

```vala
    private void update_tags_visibility () {
        bool any = Files.ColorTags.used_colors ().length > 0;
        tags_expander.no_show_all = !any;
        tags_expander.visible = any;
        tags_revealer.no_show_all = !any;
        tags_revealer.visible = any;
    }
```

- [ ] **Step 8: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 9: Commit**

```bash
git add src/View/Sidebar/TagListBox.vala src/meson.build src/View/Sidebar/SidebarWindow.vala
git commit -m "Sidebar: secció Tags amb una fila per color en ús"
```

---

## Task 7: Compilació, instal·lació i verificació manual

**Files:** cap (verificació).

- [ ] **Step 1: Compilar el projecte sencer**

Run: `ninja -C /home/marc/src/files/build`
Expected: build complet sense errors.

- [ ] **Step 2: Instal·lar (recompila l'esquema)**

Run: `sudo ninja -C /home/marc/src/files/build install`

- [ ] **Step 3: Llançar**

Run: `~/.local/bin/io.elementary.files &`

- [ ] **Step 4: Verificacions manuals**

1. Etiquetar fitxers amb un mateix color en **directoris diferents** (p. ex. dos PNG a carpetes diferents amb groc).
2. Apareix la secció **"Tags"** a la barra lateral amb una fila (punt + nom) pel color usat.
3. Clicar la fila → es mostren **tots** els fitxers d'aquell color, de tots els dirs; el títol de pestanya és el nom del color.
4. Obrir un fitxer dels resultats → s'obre correctament.
5. Posar nom al color (diàleg ①) → la fila del sidebar mostra el nom nou.
6. Treure el color a tots els fitxers d'un color i obrir-ne la vista → 0 resultats → la fila desapareix de la barra lateral en tornar.
7. Navegar a una carpeta normal → tot segueix funcionant igual (sense regressions).

- [ ] **Step 5: Commit final si calen ajustos**

Si cal retocar, fes-ho i commiteja.

---

## Self-review (cobertura de l'spec)

- Registre `used-tag-colors` + `sidebar-cat-tags-expander` → Task 1. ✓
- `ColorTags.used_colors/mark_used/unmark_used` → Task 2. ✓
- `mark_used` en assignar color → Task 3. ✓
- Esquema `tag` local/carregable + curtcircuit de preparació (FileInfo sintètic) → Task 4 (steps 1-3). ✓
- Enumeració recursiva de la carpeta personal per color + neteja si 0 → Task 4 (steps 4-5). ✓
- Nom de l'esquema + títol de pestanya amb el nom del color → Task 5. ✓
- Secció "Tags" amb fila per color en ús, navega a tag://N, refresc i visibilitat en viu → Task 6. ✓
- Branques additives `if (is_tag)` → navegació normal intacta. ✓
- Proves manuals (inclòs no-regressió) → Task 7. ✓

## Notes de risc (per a l'execució)

- **Task 4 és la de més risc.** Si la vista peta en obrir `tag://N` per `file.info`
  nul o per `file.is_folder ()`, revisar el FileInfo sintètic del Step 3. Si el
  recorregut no troba res tot i haver-hi fitxers etiquetats, comprovar el parseig del
  color de l'URI (`tag://N` → `substring("tag://".length)`).
- Si `Files.File.@get (child)` retorna un fitxer amb `info` ja existent, igualment
  s'hi assigna `info` i es crida `update ()`, així que el color i la icona són correctes.
- La navegació normal NO s'ha de veure afectada: si hi ha qualsevol regressió en obrir
  carpetes normals, és un error a les branques de Task 4 (han d'estar protegides per `is_tag`).

