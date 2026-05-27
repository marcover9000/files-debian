# Estil del color de l'etiqueta: fons vs punt (②) — Pla d'implementació

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Afegir un interruptor que canvia com es pinta el color d'etiqueta: fons darrere el nom (per defecte) o punt de color a la icona.

**Architecture:** Una clau gsettings booleana `color-tag-as-dot` controla el mode. `Files.ColorTags.show_as_dot()` (libcore) la llegeix; `ListModel` deixa de donar fons quan és certa i `IconRenderer` pinta un cercle a la cantonada de la icona. Un `SwitchModelButton` a l'`AppMenu` (acció `win.color-tag-as-dot`) l'activa, i `AbstractDirectoryView` redibuixa en viu.

**Tech Stack:** Vala, GTK3, Granite 6.x, GSettings, Cairo, Meson/Ninja. Sense tests unitaris → compilació + verificació manual.

**Nota sobre TDD:** Sense harness de tests GTK; cada tasca usa `ninja -C build` com a porta automàtica i acaba amb verificació manual.

---

## Estructura de fitxers

- **Modify:** `data/schemas/io.elementary.files.gschema.xml` — clau `color-tag-as-dot`.
- **Modify:** `libcore/ColorTags.vala` — `show_as_dot ()`.
- **Modify:** `libcore/ListModel.vala` — no donar fons en mode punt.
- **Modify:** `src/IconRenderer.vala` — pintar el punt en mode punt.
- **Modify:** `src/View/Window.vala` — acció `color-tag-as-dot` + init estat.
- **Modify:** `src/View/Widgets/AppMenu.vala` — switch "Show Tags as Dots".
- **Modify:** `src/View/AbstractDirectoryView.vala` — redibuix en viu.

---

## Task 1: Clau gsettings `color-tag-as-dot`

**Files:**
- Modify: `data/schemas/io.elementary.files.gschema.xml`

- [ ] **Step 1: Afegir la clau**

A `data/schemas/io.elementary.files.gschema.xml`, just després del tancament `</key>` de `tag-names` i abans de `  </schema>`, afegeix:

```xml
    <key type="b" name="color-tag-as-dot">
      <default>false</default>
      <summary>Show colour tags as a dot instead of a name background</summary>
      <description>When true, a file's colour tag is drawn as a coloured dot on its icon; when false, as a background behind the file name.</description>
    </key>
```

- [ ] **Step 2: Validar**

Run: `glib-compile-schemas --dry-run /home/marc/src/files/data/schemas`
Expected: sense errors.

- [ ] **Step 3: Commit**

```bash
git add data/schemas/io.elementary.files.gschema.xml
git commit -m "schema: clau color-tag-as-dot"
```

---

## Task 2: ColorTags.show_as_dot()

**Files:**
- Modify: `libcore/ColorTags.vala`

- [ ] **Step 1: Afegir el mètode**

A `libcore/ColorTags.vala`, just abans del mètode `public static string display_name (int color) {`, afegeix:

```vala
        public static bool show_as_dot () {
            return get_settings ().get_boolean ("color-tag-as-dot");
        }
```

- [ ] **Step 2: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 3: Commit**

```bash
git add libcore/ColorTags.vala
git commit -m "ColorTags: show_as_dot() llegeix el mode d'estil"
```

---

## Task 3: ListModel sense fons en mode punt

**Files:**
- Modify: `libcore/ListModel.vala`

- [ ] **Step 1: Condicionar la columna COLOR**

A `libcore/ListModel.vala`, al `case ColumnID.COLOR:`, substitueix:

```vala
            case ColumnID.COLOR:
                value = Value (typeof (string));
                if (
                    file != null &&
                    file.color >= 0 &&
                    file.color < Files.Preferences.TAGS_COLORS.length
                ) {
                    value.set_string (Files.Preferences.TAGS_COLORS[file.color]);
                } else {
                    value.set_string (Files.Preferences.TAGS_COLORS[0]);
                }

                break;
```

per:

```vala
            case ColumnID.COLOR:
                value = Value (typeof (string));
                if (
                    !Files.ColorTags.show_as_dot () &&
                    file != null &&
                    file.color >= 0 &&
                    file.color < Files.Preferences.TAGS_COLORS.length
                ) {
                    value.set_string (Files.Preferences.TAGS_COLORS[file.color]);
                } else {
                    value.set_string (Files.Preferences.TAGS_COLORS[0]); // null → no background
                }

                break;
```

- [ ] **Step 2: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 3: Commit**

```bash
git add libcore/ListModel.vala
git commit -m "ListModel: sense fons de color quan el mode és punt"
```

---

## Task 4: IconRenderer pinta el punt

**Files:**
- Modify: `src/IconRenderer.vala`

- [ ] **Step 1: Dibuixar el cercle després de la icona**

A `src/IconRenderer.vala`, dins `render()`, just després de:

```vala
            style_context.render_icon (cr, pb, draw_rect.x * icon_scale, draw_rect.y * icon_scale);

            style_context.restore ();
```

afegeix:

```vala
            if (Files.ColorTags.show_as_dot () &&
                file.color >= 1 &&
                file.color < Files.Preferences.TAGS_COLORS.length &&
                Files.Preferences.TAGS_COLORS[file.color] != null) {

                double diameter = 11.0 * icon_scale;
                double pad = 1.0 * icon_scale;
                double right = (draw_rect.x + draw_rect.width) * icon_scale;
                double bottom = (draw_rect.y + draw_rect.height) * icon_scale;
                double cx = right - diameter / 2.0 - pad;
                double cy = bottom - diameter / 2.0 - pad;

                var rgba = Gdk.RGBA ();
                rgba.parse (Files.Preferences.TAGS_COLORS[file.color]);

                cr.save ();
                cr.arc (cx, cy, diameter / 2.0, 0, 2 * GLib.Math.PI);
                cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, 1.0);
                cr.fill_preserve ();
                cr.set_line_width (icon_scale);
                cr.set_source_rgba (1.0, 1.0, 1.0, 0.85); // light ring for contrast
                cr.stroke ();
                cr.restore ();
            }
```

- [ ] **Step 2: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 3: Commit**

```bash
git add src/IconRenderer.vala
git commit -m "IconRenderer: pintar el color d'etiqueta com a punt a la icona"
```

---

## Task 5: Switch al menú + acció + redibuix en viu

**Files:**
- Modify: `src/View/Window.vala`
- Modify: `src/View/Widgets/AppMenu.vala`
- Modify: `src/View/AbstractDirectoryView.vala`

- [ ] **Step 1: Registrar l'acció**

A `src/View/Window.vala`, dins `WIN_ENTRIES`, substitueix:

```vala
        {"edit-tag-names", action_edit_tag_names}
    };
```

per:

```vala
        {"edit-tag-names", action_edit_tag_names},
        {"color-tag-as-dot", null, null, "false", change_state_color_tag_as_dot}
    };
```

- [ ] **Step 2: Afegir el handler**

A `src/View/Window.vala`, just abans de `public void change_state_single_click_select (GLib.SimpleAction action) {`, afegeix:

```vala
    public void change_state_color_tag_as_dot (GLib.SimpleAction action) {
        bool state = !action.state.get_boolean ();
        action.set_state (new GLib.Variant.boolean (state));
        Files.app_settings.set_boolean ("color-tag-as-dot", state);
    }
```

- [ ] **Step 3: Inicialitzar l'estat de l'acció**

A `src/View/Window.vala`, just després de la línia
`get_action ("restore-tabs-on-startup").set_state (app_settings.get_boolean ("restore-tabs"));`,
afegeix:

```vala
        get_action ("color-tag-as-dot").set_state (app_settings.get_boolean ("color-tag-as-dot"));
```

- [ ] **Step 4: Afegir el switch a l'AppMenu**

A `src/View/Widgets/AppMenu.vala`, just després de:

```vala
        var restore_tabs = new Granite.SwitchModelButton (_("Restore Tabs from Last Time")) {
            action_name = "win.restore-tabs-on-startup"
        };
```

afegeix:

```vala
        var tags_as_dots = new Granite.SwitchModelButton (_("Show Tags as Dots")) {
            action_name = "win.color-tag-as-dot"
        };
```

I a la zona on s'afegeixen els switches al `menu_box`, just després de `menu_box.add (restore_tabs);`, afegeix:

```vala
        menu_box.add (tags_as_dots);
```

- [ ] **Step 5: Redibuixar en viu en canviar el mode**

A `src/View/AbstractDirectoryView.vala`, just després de la línia `view = create_view ();` (al constructor, ~línia 340), afegeix:

```vala
            Files.app_settings.changed["color-tag-as-dot"].connect (() => {
                view.queue_draw ();
            });
```

- [ ] **Step 6: Compilar**

Run: `ninja -C /home/marc/src/files/build`
Expected: compila sense errors.

- [ ] **Step 7: Commit**

```bash
git add src/View/Window.vala src/View/Widgets/AppMenu.vala src/View/AbstractDirectoryView.vala
git commit -m "Activar el mode punt des del menú + redibuix en viu"
```

---

## Task 6: Compilació, instal·lació i verificació manual

**Files:** cap (verificació).

- [ ] **Step 1: Compilar el projecte sencer**

Run: `ninja -C /home/marc/src/files/build`
Expected: build complet sense errors.

- [ ] **Step 2: Instal·lar (recompila l'esquema)**

Run: `sudo ninja -C /home/marc/src/files/build install`

- [ ] **Step 3: Llançar**

Run: `~/.local/bin/io.elementary.files &`

- [ ] **Step 4: Verificacions manuals**

1. Etiquetar un fitxer amb un color → per defecte, fons darrere el nom.
2. Menú hamburguesa → activar "Show Tags as Dots" → el fons desapareix i surt un
   **punt** de color a la cantonada inferior dreta de la icona, **a l'instant**.
3. Comprovar a icones, llista i columnes.
4. Desactivar → torna al fons.
5. Fitxer sense etiqueta → ni fons ni punt.
6. Tancar i reobrir Files → l'estat del switch persisteix.

- [ ] **Step 5: Commit final si calen ajustos**

Si cal retocar (mida/posició del punt), fes-ho i commiteja.

---

## Self-review (cobertura de l'spec)

- Clau gsettings booleana `color-tag-as-dot` (default false) → Task 1. ✓
- `ColorTags.show_as_dot()` (libcore, accessible des de ListModel i IconRenderer) → Task 2. ✓
- Mode fons sense canvis / mode punt sense fons → Task 3 (ListModel). ✓
- Punt a la cantonada inferior dreta de la icona, totes les vistes → Task 4 (IconRenderer). ✓
- Switch a l'AppMenu + acció sincronitzada amb gsettings + init → Task 5 (Window/AppMenu). ✓
- Actualització en viu → Task 5 (AbstractDirectoryView `changed` → `queue_draw`). ✓
- color 0/fora de rang → ni fons ni punt → Tasks 3-4 (condicions). ✓
- Abast: només estil; no toca noms (①) ni filtre (③). ✓
- Proves manuals → Task 6. ✓
