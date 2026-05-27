# Estil del color de l'etiqueta: fons vs punt (②) — Disseny

**Data:** 2026-05-27
**Fork:** `marcover9000/files-debian`, branca `gnome-43` (base elementary/files `7.1.6`)
**Estat:** Aprovat, pendent de pla d'implementació

## Objectiu

Permetre triar **com es pinta** el color d'etiqueta d'un fitxer: com a **fons darrere
el nom** (comportament actual) o com a **punt de color a la icona** (estil macOS),
mitjançant un interruptor al menú principal. Segona de tres peces del sistema
d'etiquetes (① noms ✓ → ② estil → ③ filtre a la barra lateral).

## Decisions preses (brainstorming)

1. **Setting:** clau gsettings booleana `color-tag-as-dot` (default `false` = fons).
2. **UI:** un `Granite.SwitchModelButton` "Mostra les etiquetes com a punt" a l'`AppMenu`.
3. **Punt:** cercle de color a la **cantonada inferior dreta** de la icona.
4. **Actualització en viu** en alternar el switch.

## Situació de partida

- El color tag és un **únic** color per fitxer (`Files.File.color`, int 1-10, índex
  dins `Files.Preferences.TAGS_COLORS`), del plugin `pantheon-files-ctags`.
- **Render del fons (actual):** `libcore/ListModel.vala` exposa la columna
  `ColumnID.COLOR` = `TAGS_COLORS[file.color]` (o `TAGS_COLORS[0]` = null). Les vistes
  lliguen aquesta columna a la propietat `background` del `TextRenderer`:
  - `src/View/AbstractTreeView.vala:81` i `src/View/IconView.vala:66`
    (`add_attribute (name_renderer, "background", ColumnID.COLOR)`).
- **Icona:** `src/IconRenderer.vala` (`render()`) pinta el pixbuf de la icona a totes
  les vistes; rep `cr` i `cell_area`.
- **Settings globals:** `Files.app_settings` (`new Settings("io.elementary.files.preferences")`,
  creat a `src/Application.vala`) és accessible des de `src` (l'`AppMenu` ja l'usa).
- **Switches al menú:** `src/View/Widgets/AppMenu.vala` usa `Granite.SwitchModelButton`
  amb `action_name = "win.<x>"`; les accions amb estat es defineixen a
  `src/View/Window.vala` (`WIN_ENTRIES`, p. ex. `singleclick-select` amb
  `change_state_single_click_select`) i es lliguen a la clau gsettings.
- L'esquema és `data/schemas/io.elementary.files.gschema.xml`, schema
  `io.elementary.files.preferences`.

## Arquitectura proposada

### 1. Clau gsettings

Afegir a l'schema `io.elementary.files.preferences`:

```xml
<key type="b" name="color-tag-as-dot">
  <default>false</default>
  <summary>Show colour tags as a dot instead of a name background</summary>
  <description>When true, a file's colour tag is drawn as a coloured dot on its icon; when false, as a background behind the file name.</description>
</key>
```

### 2. Acció + switch

- `src/View/Window.vala`: afegir a `WIN_ENTRIES`
  `{"color-tag-as-dot", null, null, "false", change_state_color_tag_as_dot}` i el
  handler `change_state_color_tag_as_dot` que escriu la clau a `Files.app_settings`
  (mateix patró que `change_state_single_click_select`). A l'inici de la finestra,
  l'estat de l'acció es sincronitza amb la clau (com fan els altres switches).
- `src/View/Widgets/AppMenu.vala`: afegir un `Granite.SwitchModelButton`
  "Show Tags as Dots" amb `action_name = "win.color-tag-as-dot"`, a la secció de
  switches (a prop de "Restore Tabs from Last Time").

### 3. Render condicional

- **`libcore/ListModel.vala`** (cas `ColumnID.COLOR`): si
  `Files.app_settings.get_boolean ("color-tag-as-dot")` és cert, retornar sempre
  `TAGS_COLORS[0]` (null) → cap fons. Si és fals, el comportament actual.
- **`src/IconRenderer.vala`** (`render()`): si la clau és certa i `file.color` ∈ [1,10],
  després de pintar la icona, dibuixar un cercle ple de `TAGS_COLORS[file.color]` amb
  una vora subtil a la cantonada inferior dreta de la zona de la icona (mida ~ 10 px
  lògics · `icon_scale`).

### 4. Actualització en viu

A `src/View/AbstractDirectoryView.vala`, connectar-se a
`Files.app_settings.changed["color-tag-as-dot"]` i fer `queue_draw` de la vista (el
mateix patró que ja s'usa per a altres canvis de settings de vista), perquè el canvi
es vegi a l'instant sense recarregar.

## Flux de dades

1. Usuari activa el switch → l'acció escriu `color-tag-as-dot=true` a gsettings.
2. El senyal `changed` dispara `queue_draw` de la vista.
3. En repintar: `ListModel` no dóna fons (null) i `IconRenderer` pinta el punt.
   En desactivar, al revés.

## Gestió d'errors

- `file.color` = 0 o fora de [1,10] → ni fons ni punt (cap canvi de comportament).
- Lectura de la clau a cada `render`/getter: GSettings cacheja en memòria, és barat.

## Proves

Vala + Meson; sense tests unitaris → verificació **manual** després de
`sudo ninja -C build install`:

1. Etiquetar un fitxer amb un color (mode fons per defecte) → fons darrere el nom.
2. Menú hamburguesa → activar "Show Tags as Dots" → el fons desapareix i surt un
   **punt** de color a la cantonada inferior dreta de la icona, **a l'instant**.
3. Comprovar a les tres vistes: icones, llista, columnes.
4. Desactivar el switch → torna al fons.
5. Fitxer sense etiqueta → ni fons ni punt en cap mode.
6. Tancar i reobrir Files → l'estat del switch persisteix.

## Fora d'abast (YAGNI)

- ③ Filtre a la barra lateral (següent cicle).
- Més de dos estils de visualització (per això un booleà, no un enum).
- Mostrar el punt també a la columna de preview (es pot afegir més endavant).
