# Noms a les etiquetes de color (①) — Disseny

**Data:** 2026-05-27
**Fork:** `marcover9000/files-debian`, branca `gnome-43` (base elementary/files `7.1.6`)
**Estat:** Aprovat, pendent de pla d'implementació

## Objectiu

Permetre posar un **nom propi a cada color d'etiqueta** (p. ex. groc = "manuals de
dnd"), editar-los des d'un diàleg al menú principal, i veure'ls com a **tooltip**
sobre els cercles de color del menú contextual. És la primera de tres peces del
sistema d'etiquetes (① noms → ② setting fons/punt → ③ filtre a la barra lateral).

## Context i decisions

- El sistema de color tags és el plugin natiu `pantheon-files-ctags` (un color per
  fitxer, `metadata::color-tag` int 1-10; índex dins `Files.Preferences.TAGS_COLORS`),
  amb la fila de cercles de color (`ColorWidget`) al menú contextual.
- **Emmagatzematge dels noms:** gsettings (no per fitxer; els noms són globals de l'usuari).
- **Editor:** diàleg obert des del menú principal (`AppMenu`).
- **Visualització ara:** tooltip a cada cercle. La barra lateral (③) reutilitzarà els noms.

## Situació de partida

- Esquema: `data/schemas/io.elementary.files.gschema.xml`, schema
  `io.elementary.files.preferences` (path `/io/elementary/files/preferences/`).
- `libcore/Preferences.vala`: `TAGS_COLORS` = `{ null, "#64baff", "#43d6b5",
  "#9bdb4d", "#ffe16b", "#ffc27d", "#ff8c82", "#f4679d", "#cd9ef7", "#a3907c",
  "#95a3ab", null }` (índex 1-10 són colors).
- `src/View/Widgets/AppMenu.vala`: menú hamburguesa amb botons que disparen accions
  `win.*` (p. ex. `win.singleclick-select`).
- Accions `win.*` definides a `src/View/Window.vala`.
- Plugin: `plugins/pantheon-files-ctags/plugin.vala` amb `ColorWidget` (10 `ColorButton`
  + el botó "none").

## Arquitectura proposada

### 1. Clau gsettings

Afegir a l'esquema `io.elementary.files.preferences`:

```xml
<key type="as" name="tag-names">
  <default>['','','','','','','','','','']</default>
  <summary>Custom names for the colour tags</summary>
  <description>One name per colour tag (indices 0-9 map to colours 1-10). Empty = use the generic colour name.</description>
</key>
```

### 2. Helper `Files.ColorTags` (libcore)

Fitxer nou `libcore/ColorTags.vala` (registrat a `libcore/meson.build`), accessible
des del plugin i des de `src`:

- `static string generic_name (int color)` → noms genèrics localitzats:
  1 Blau, 2 Menta, 3 Verd, 4 Groc, 5 Taronja, 6 Vermell, 7 Rosa, 8 Lila, 9 Marró,
  10 Pissarra. Per a 0 o fora de rang → "" .
- `static string display_name (int color)` → llegeix `tag-names` de
  `io.elementary.files.preferences`; si l'entrada `color-1` existeix i no és buida,
  la retorna; si no, `generic_name(color)`.
- `static void set_names (string[] names)` → escriu l'array (mida 10) a `tag-names`.
- `static string[] get_names ()` → l'array actual normalitzat a mida 10 (omple amb "").

### 3. Diàleg `TagNamesDialog` (src)

Fitxer nou `src/Dialogs/TagNamesDialog.vala` (registrat a `src/meson.build`).
`Granite.Dialog` (o `Gtk.Dialog`) amb:
- 10 files; cada fila: un punt de color (es pinta amb `TAGS_COLORS[i]`, Cairo, com
  el render del menú) + un `Gtk.Entry` precarregat amb `ColorTags.get_names()[i]`.
- Botó "Fet"/"Tanca": en tancar, recull els 10 entries i crida `ColorTags.set_names()`.

### 4. Llançament des de l'AppMenu

- A `src/View/Widgets/AppMenu.vala`: afegir un `Gtk.ModelButton` "Noms de les
  etiquetes…" amb `action_name = "win.edit-tag-names"`.
- A `src/View/Window.vala`: registrar l'acció `edit-tag-names` que instancia i mostra
  el `TagNamesDialog` (transient per la finestra).

### 5. Tooltips al menú contextual

A `ColorWidget` (plugin ctags): després de crear cada `ColorButton`, posar
`tooltip_text`:
- cercles de color i (1-10): `Files.ColorTags.display_name (i)`.
- cercle "none": `_("Remove colour")`.

## Flux de dades

1. Usuari obre menú principal → "Noms de les etiquetes…" → diàleg precarregat amb
   `ColorTags.get_names()`.
2. Escriu noms, tanca → `ColorTags.set_names()` escriu gsettings.
3. En obrir el menú contextual, cada cercle agafa el tooltip via
   `ColorTags.display_name()` (gsettings + fallback genèric).

## Gestió d'errors

- `tag-names` amb menys de 10 entrades → `get_names()` ho normalitza a 10 amb "".
- Entrada buida → `display_name` retorna el genèric.
- color fora de [1,10] → cadena buida.

## Proves

Vala + Meson; sense tests unitaris → verificació **manual** després de
`sudo ninja -C build install` (cal recompilar l'esquema gsettings, que la instal·lació ja fa):

1. Menú principal → "Noms de les etiquetes…" obre el diàleg amb 10 files (punt + camp).
2. Posar "manuals de dnd" al groc, tancar.
3. Clic dret sobre un fitxer → passar per sobre el cercle groc → tooltip "manuals de dnd".
4. Cercles sense nom propi → tooltip amb el nom genèric (Blau, Verd…).
5. Tancar i reobrir Files → els noms persisteixen.
6. Cercle "none" → tooltip "Treu el color".

## Fora d'abast (YAGNI)

- ② Setting fons vs punt (següent cicle).
- ③ Filtre a la barra lateral (cicle posterior).
- Noms mostrats com a text visible al menú (es fa per tooltip per no inflar la fila).
- Sincronització dels noms entre màquines.
