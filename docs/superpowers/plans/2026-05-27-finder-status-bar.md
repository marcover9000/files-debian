# Barra d'estat estil Finder — Pla d'implementació

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convertir l'`OverlayBar` flotant transitori en una barra d'estat inferior persistent i sempre visible, estil Finder, amb estat de repòs `N elements · X lliures`.

**Architecture:** Es reaprofita `OverlayBar` (subclasse de `Granite.Widgets.OverlayBar`, que és un `Gtk.EventBox`). El seu constructor accepta `overlay = null`, així que el creem **sense ancorar-lo a l'overlay** i l'empaquetem com a fila inferior del `Gtk.Box` de `ViewContainer` (orientació vertical: contingut a dalt amb expansió, barra a baix). S'hi afegeix un estat de repòs nou que llegeix `Slot.displayed_files_count` i consulta l'espai lliure de forma asíncrona. La lògica de selecció existent es manté intacta.

**Tech Stack:** Vala, GTK3, Granite 6.x, Meson/Ninja. Sense framework de tests unitaris a la base → verificació via compilació + proves manuals (com indica l'spec).

**Nota sobre TDD:** El codebase no té harness de tests unitaris per a widgets GTK i l'spec va acordar verificació manual. Cada tasca usa la compilació (`ninja -C build`) com a porta automàtica i acaba amb passos de verificació manual concrets. No s'inventen tests que la base no pot executar.

---

## Estructura de fitxers

- **Modify:** `src/View/Widgets/OverlayBar.vala` — constructor amb overlay opcional; nou estat de repòs `show_folder_summary()`; consulta async d'espai lliure amb cache i cancel·lació; classe d'estil CSS.
- **Modify:** `src/View/ViewContainer.vala` — orientació vertical; crear i empaquetar la barra a baix; mantenir el contingut a sobre en cada swap; substituir la lògica de flotació/amagat per l'estat de repòs; connectar `free_space_change`.
- **Modify:** `gnome-integration/gtk-3.0/gtk.css` — estil de barra ancorada (font de veritat del fork).
- **Modify:** `~/.config/gtk-3.0/gtk.css` — còpia viva que carrega l'app instal·lada (mateix bloc CSS).

---

## Task 1: Estat de repòs i overlay opcional a OverlayBar

**Files:**
- Modify: `src/View/Widgets/OverlayBar.vala`

- [ ] **Step 1: Fer el constructor admetre overlay nul i afegir classe d'estil**

A `src/View/Widgets/OverlayBar.vala`, canvia la signatura del constructor (actualment `public OverlayBar (Gtk.Overlay overlay)`) per:

```vala
        public OverlayBar (Gtk.Overlay? overlay = null) {
            base (overlay); /* Si overlay és null, NO s'afegeix com a fill d'overlay; l'empaqueta el ViewContainer. */
        }
```

I dins del bloc `construct { ... }`, després de `label = "";`, afegeix la classe d'estil i fes-lo expansiu horitzontalment:

```vala
            hexpand = true;
            halign = Gtk.Align.FILL;
            get_style_context ().add_class ("files-statusbar");
```

- [ ] **Step 2: Afegir camps per a l'estat de repòs i la cache d'espai lliure**

A la zona de camps privats de la classe (a prop de `private DeepCount? deep_counter = null;`), afegeix:

```vala
        private uint folder_item_count = 0;
        private GLib.File? summary_location = null;
        private string? cached_free_space = null;
        private Cancellable? free_space_cancellable = null;
```

- [ ] **Step 3: Afegir el mètode públic de l'estat de repòs**

Afegeix aquest mètode públic dins la classe (p. ex. just abans de `public void cancel ()`):

```vala
        /* Estat de repòs (sense selecció): mostra "N elements · X lliures". */
        public void show_folder_summary (uint item_count, GLib.File? location) {
            cancel ();
            reset_selection ();
            folder_item_count = item_count;

            /* Si canvia de carpeta, invalida la cache d'espai lliure. */
            if (summary_location == null || location == null || !summary_location.equal (location)) {
                summary_location = location;
                cached_free_space = null;
            }

            render_folder_summary ();

            if (cached_free_space == null && summary_location != null) {
                query_free_space.begin (summary_location);
            }
        }

        private void render_folder_summary () {
            /// TRANSLATORS: %u = nombre d'elements de la carpeta
            string str = ngettext ("%u element", "%u elements", folder_item_count)
                            .printf (folder_item_count);
            if (cached_free_space != null) {
                /// TRANSLATORS: %s = espai lliure formatat (p. ex. "87,3 GB")
                str += " · " + _("%s lliures").printf (cached_free_space);
            }
            label = str;
            visible = true;
        }

        private async void query_free_space (GLib.File location) {
            if (free_space_cancellable != null) {
                free_space_cancellable.cancel ();
            }
            free_space_cancellable = new Cancellable ();
            try {
                var info = yield location.query_filesystem_info_async (
                    FileAttribute.FILESYSTEM_FREE, GLib.Priority.LOW, free_space_cancellable
                );
                if (info.has_attribute (FileAttribute.FILESYSTEM_FREE)) {
                    cached_free_space = format_size (info.get_attribute_uint64 (FileAttribute.FILESYSTEM_FREE));
                    render_folder_summary ();
                }
            } catch (Error e) {
                /* Cancel·lat o remot sense info: degradació elegant, només recompte. */
                debug ("Free space query failed: %s", e.message);
            }
            free_space_cancellable = null;
        }
```

- [ ] **Step 4: Compilar per verificar que OverlayBar segueix vàlid**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors (avisos d'unused `summary_location` poden aparèixer fins que el connectem a la Task 3; un build net és l'objectiu).

- [ ] **Step 5: Commit**

```bash
git add src/View/Widgets/OverlayBar.vala
git commit -m "OverlayBar: estat de repòs amb recompte i espai lliure"
```

---

## Task 2: Ancorar la barra a baix dins ViewContainer

**Files:**
- Modify: `src/View/ViewContainer.vala`

- [ ] **Step 1: Posar ViewContainer en orientació vertical**

A `src/View/ViewContainer.vala`, dins `construct {` (línia ~146), afegeix com a primera instrucció:

```vala
            orientation = Gtk.Orientation.VERTICAL;
```

- [ ] **Step 2: Mantenir el contingut sempre per sobre de la barra en cada swap**

Al setter de `content` (línia ~99-111), després de `add (content_item);` i `content_item.show_all ();`, afegeix la reordenació perquè el contingut quedi a dalt (posició 0) i la barra a baix:

```vala
                if (content_item != null) {
                    add (content_item);
                    content_item.show_all ();
                    reorder_child (content_item, 0);
                }
```

(El `content_item` ha d'expandir-se per omplir l'espai; com que la barra es packarà amb expand=false, el contingut ocupa la resta. Assegura't a la Task 1/aquí que la barra no expandeix verticalment — Gtk.Box vertical no expandeix els fills per defecte.)

- [ ] **Step 3: Crear la barra desancorada i empaquetar-la a baix**

A `add_view (...)` (línia ~240), substitueix:

```vala
            overlay_statusbar = new View.OverlayBar (view.overlay) {
                no_show_all = true
            };
```

per:

```vala
            overlay_statusbar = new View.OverlayBar (null);
            pack_end (overlay_statusbar, false, false, 0);
```

- [ ] **Step 4: Eliminar la lògica de flotació i d'amagat (ara és persistent)**

A `directory_is_loading (...)` (línia ~330), elimina la línia que recol·loca la barra flotant:

```vala
            overlay_statusbar.halign = Gtk.Align.END;
```

A `update_tab_name ()` (final del mètode, línia ~363), elimina:

```vala
            overlay_statusbar.hide ();
```

- [ ] **Step 5: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 6: Commit**

```bash
git add src/View/ViewContainer.vala
git commit -m "ViewContainer: ancorar la barra d'estat a baix sempre visible"
```

---

## Task 3: Connectar estat de repòs vs. selecció

**Files:**
- Modify: `src/View/ViewContainer.vala`

- [ ] **Step 1: Mostrar el repòs quan la selecció queda buida**

A `on_slot_selection_changed (...)` (línia ~598), substitueix el cos:

```vala
        private void on_slot_selection_changed (GLib.List<unowned Files.File> files) {
            overlay_statusbar.selection_changed (files);
        }
```

per:

```vala
        private void on_slot_selection_changed (GLib.List<unowned Files.File> files) {
            if (files == null) {
                if (slot != null) {
                    overlay_statusbar.show_folder_summary (slot.displayed_files_count, location);
                }
            } else {
                overlay_statusbar.selection_changed (files);
            }
        }
```

(`location` és la propietat existent de ViewContainer que retorna `slot.location`; `slot.displayed_files_count` existeix a `Slot.vala:37`.)

- [ ] **Step 2: Mostrar el repòs en acabar de carregar la carpeta**

A `on_slot_directory_loaded (...)`, dins el bloc `if (can_show_folder) {` (línia ~437), just després de `content = view.get_content_box ();`, afegeix:

```vala
                if (selected_locations == null && dir.selected_file == null) {
                    overlay_statusbar.show_folder_summary (slot.displayed_files_count, dir.file.location);
                }
```

- [ ] **Step 3: Refrescar l'espai lliure quan la finestra ho notifiqui**

Al setter de `window` (línia ~36-48), després de `_window.connect_content_signals (this);`, afegeix:

```vala
                _window.free_space_change.connect (on_free_space_change);
```

I a `disconnect_window_signals ()` (línia ~165), després de `window.folder_deleted.disconnect (on_folder_deleted);`, afegeix:

```vala
                window.free_space_change.disconnect (on_free_space_change);
```

Afegeix el handler nou a prop de `on_folder_deleted`:

```vala
        private void on_free_space_change () {
            if (slot != null && current_selected_count () == 0) {
                overlay_statusbar.show_folder_summary (slot.displayed_files_count, location);
            }
        }

        private uint current_selected_count () {
            var sel = slot != null ? slot.get_selected_files () : null;
            return sel != null ? sel.length () : 0;
        }
```

(Si `Slot` no exposa `get_selected_files()`, simplifica `on_free_space_change` perquè cridi sempre `show_folder_summary`; `OverlayBar.show_folder_summary` no es mostra si hi ha selecció activa perquè la propera `selection_changed` la sobreescriu. Verifica l'API a `src/View/Slot.vala` durant la implementació i ajusta.)

- [ ] **Step 4: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors ni avisos d'unused dels camps de la Task 1.

- [ ] **Step 5: Commit**

```bash
git add src/View/ViewContainer.vala
git commit -m "ViewContainer: alternar repòs/selecció a la barra d'estat"
```

---

## Task 4: Estil CSS de la barra ancorada

**Files:**
- Modify: `gnome-integration/gtk-3.0/gtk.css`
- Modify: `~/.config/gtk-3.0/gtk.css`

- [ ] **Step 1: Afegir el bloc CSS a la font de veritat del fork**

Afegeix al final de `gnome-integration/gtk-3.0/gtk.css`:

```css
/* Barra d'estat estil Finder (sempre visible, ancorada a baix) */
.files-statusbar {
    border-top: 1px solid alpha(currentColor, 0.12);
    padding: 2px 8px;
    min-height: 22px;
    font-size: 0.85em;
}
.files-statusbar label {
    opacity: 0.85;
}
```

- [ ] **Step 2: Replicar el bloc a la còpia viva**

Afegeix el mateix bloc al final de `~/.config/gtk-3.0/gtk.css` (és el fitxer que carrega l'app instal·lada a `/opt`). La classe `.files-statusbar` és prou específica per no afectar altres apps GTK3.

- [ ] **Step 3: Commit (només la font de veritat; ~/.config no és al repo)**

```bash
git add gnome-integration/gtk-3.0/gtk.css
git commit -m "gtk.css: estil de la barra d'estat ancorada"
```

---

## Task 5: Compilació, instal·lació i verificació manual

**Files:** cap (verificació).

- [ ] **Step 1: Compilar el projecte sencer**

Run: `ninja -C /home/marc/src/files/build`
Expected: build complet sense errors.

- [ ] **Step 2: Instal·lar al prefix /opt**

Run: `sudo ninja -C /home/marc/src/files/build install`
Expected: instal·la a `/opt/pantheon-files` (pot demanar contrasenya sudo).

- [ ] **Step 3: Llançar l'app**

Run: `~/.local/bin/io.elementary.files &`
(El wrapper fixa `LD_LIBRARY_PATH`/`GSETTINGS_SCHEMA_DIR` al prefix.)

- [ ] **Step 4: Verificacions manuals**

Comprova un per un:
1. Carpeta local amb fitxers → la barra inferior mostra `N elements · X lliures`.
2. Selecció d'1 fitxer → text ric actual (nom · tipus · mida).
3. Selecció múltiple → `N ítems seleccionats (mida)`.
4. Deseleccionar (clic en buit) → torna a `N elements · X lliures`.
5. Carpeta de xarxa/remota → només `N elements`, sense espai (sense errors).
6. Canvi ràpid entre carpetes → sense text obsolet ni errors (cancel·lació OK).
7. Carpeta buida → `0 elements · X lliures`.
8. La barra és visible a baix a totes les vistes: icones, llista i **columnes Miller**.

- [ ] **Step 5: Commit final si calen ajustos**

Si la verificació obliga a retocs, fes-los i commiteja amb un missatge descriptiu.

---

## Self-review (cobertura de l'spec)

- Reaprofitar OverlayBar → Tasks 1-3 (es manté la classe i la lògica de selecció). ✓
- Estat de repòs `N elements · X lliures` → Task 1 (`show_folder_summary`/`render_folder_summary`) + Task 3 (triggers). ✓
- Mantenir text de selecció actual → no es toca `selection_changed`/`update_status`. ✓
- Sempre visible (sense toggle) → Task 2 (pack persistent, sense `hide()`/`no_show_all`). ✓
- Total d'ítems via `displayed_files_count` → Task 3. ✓
- Espai lliure async/cancel·lable/cache → Task 1; refresc amb `free_space_change` → Task 3. ✓
- Gestió d'errors (remot sense FILESYSTEM_FREE, cancel·lació, carpeta buida) → Task 1 `query_free_space`/`render_folder_summary`. ✓
- Estil de barra ancorada → Task 4. ✓
- Proves manuals → Task 5. ✓
