# Tags de colors (part A: assignar + veure) — Disseny

**Data:** 2026-05-27
**Fork:** `marcover9000/files-debian`, branca `gnome-43` (base elementary/files `7.1.6`)
**Estat:** Aprovat, pendent de pla d'implementació

## Objectiu

Permetre etiquetar fitxers i carpetes amb **colors estil Finder**, veure'ls com a
punts de color a les vistes i a la columna de preview, i assignar-los/treure'ls
des del menú contextual. Continua la línia del fork d'aproximar la sensació d'ús
a la del Finder de macOS.

Aquest spec cobreix **la part A** (assignar, treure, veure). La part B (secció
"Etiquetes" a la barra lateral per filtrar per color) es farà en un cicle futur i
queda **fora d'abast** aquí.

## Decisions preses (brainstorming)

1. **Abast:** A ara (assignar/treure + visualització); B (filtre a la barra lateral) després.
2. **Emmagatzematge:** metadades GVfs per fitxer (`metadata::files-tags`), no xattr ni db.
3. **Multi-etiqueta:** un fitxer pot tenir-ne diverses (diversos punts).
4. **Paleta:** fixa, 7 colors estil Finder.
5. **Ubicacions UI:** submenú al clic dret, punts de color a les vistes, i punts + noms
   a la columna de preview.

## Situació de partida

- `Files.File` (`libcore/File.vala`):
  - Cadena d'atributs sol·licitats inclou ja `metadata::marlin-sort-column-id`, etc.
    (línia ~38). Cal afegir-hi `metadata::files-tags`.
  - Llegeix metadata amb `info.has_attribute(...)` / `info.get_attribute_string(...)`
    (p. ex. línies ~556-563 per a marlin-sort).
  - Sistema d'emblemes: `emblems_list`, `n_emblems`, `add_emblem(string)` (~1120),
    es regenera a `update_emblems`-style; `EmblemRenderer` (`src/EmblemRenderer.vala`)
    pinta els emblemes sobre la icona a totes les vistes.
- `src/View/AbstractDirectoryView.vala`: el menú contextual es construeix imperativament
  a `show_context_menu` (~1907), afegint `Gtk.MenuItem`s.
- `src/View/Widgets/PreviewColumn.vala`: ja existeix amb `populate_info`/`add_info_row`
  per a la graella de metadades; s'hi afegirà una fila d'etiquetes.
- Escriptura de metadata: `GLib.File.set_attribute_string("metadata::…", valor,
  FileQueryInfoFlags.NONE)` (patró estàndard GIO/GVfs).

## Arquitectura proposada

### Component nou: `TagManager` (utilitat central de la paleta)

Fitxer nou `libcore/TagManager.vala` (o `src/Utils/TagManager.vala` segons on
encaixi millor amb meson; veure pla). Responsabilitat única: definir la paleta i
servir colors/noms/punts.

- Paleta fixa: claus estables `red, orange, yellow, green, blue, purple, gray`.
- `string[] all_keys ()` — ordre de la paleta.
- `bool is_valid (string key)`.
- `string display_name (string key)` — nom localitzat (Vermell, Taronja, …).
- `Gdk.RGBA color (string key)` — color RGBA del punt.
- `Gdk.Pixbuf dot_pixbuf (string key, int size, int scale)` — cercle ple del color,
  cachejat per (clau,size,scale); dibuixat amb Cairo.

### Model a `Files.File`

- Afegir `metadata::files-tags` a la cadena d'atributs (línia ~38).
- Camp `public GLib.List<string> tags` (o `string[]`), poblat en llegir la info:
  parsejar `metadata::files-tags` (CSV) filtrant per `TagManager.is_valid`.
- `public async void set_tags (string[] keys)`: escriure
  `metadata::files-tags` = `string.joinv(",", keys)` via
  `location.set_attribute_string(...)`, refrescar `tags` i regenerar emblemes.
- Helpers: `bool has_tag(string key)`, `add_tag(string)`, `remove_tag(string)`
  (operen sobre la llista i criden `set_tags`).
- En regenerar emblemes, afegir un emblema per cada tag amb una clau prefixada
  `tag:<clau>` (p. ex. `tag:red`).

### Visualització (punts a la vista) — `EmblemRenderer`

- `EmblemRenderer` ja itera `file.emblems_list` i pinta cada emblema. S'estén perquè,
  si la clau d'emblema comença per `tag:`, en lloc de buscar una icona del tema,
  usi `TagManager.dot_pixbuf(clau_sense_prefix, size, scale)`.
- Diversos tags → diversos punts (el renderer ja col·loca múltiples emblemes).

### Assignar / treure (menú contextual) — `AbstractDirectoryView`

- A `show_context_menu`, afegir un `Gtk.MenuItem` "Etiquetes" amb un submenú que conté:
  - Un `Gtk.CheckMenuItem` per color (nom + es marca si TOTS els fitxers seleccionats
    el tenen); en activar/desactivar, afegeix/treu aquell color a tota la selecció.
  - Separador + "Treu les etiquetes" (buida els tags de tota la selecció).
- Després de modificar, escriure via `set_tags` i refrescar (regenerar emblemes +
  `queue_draw`).

### Visualització a la columna de preview — `PreviewColumn`

- A `populate_info`, afegir una fila "Etiquetes" si el fitxer en té: una `Gtk.Box`
  horitzontal amb els punts de color (`TagManager.dot_pixbuf`) seguits dels noms
  (separats per comes). Si no en té, s'omet la fila.

## Flux de dades

1. Lectura de directori → `Files.File` parseja `metadata::files-tags` → `tags` →
   genera emblemes `tag:<clau>` → `EmblemRenderer` pinta els punts.
2. Usuari obre clic dret → submenú "Etiquetes" reflecteix l'estat de la selecció.
3. Usuari marca/desmarca un color → `set_tags` escriu l'atribut a cada fitxer →
   refresca emblemes i redibuixa; si hi ha preview obert d'un fitxer afectat,
   es refà la fila d'etiquetes.

## Gestió d'errors

- Atribut absent → llista buida (cas normal, sense punts).
- Backend que no permet escriure metadata (alguns remots) → `set_attribute_string`
  falla; es captura, es registra amb `warning`/`debug` i no trenca (com Files amb
  altres metadata). L'opció pot quedar deshabilitada per a aquests casos si convé.
- Clau de color desconeguda en llegir → s'ignora (filtre `TagManager.is_valid`).
- Selecció buida → el submenú "Etiquetes" no s'afegeix.

## Proves

Vala + Meson; sense tests unitaris → verificació **manual** després de
`sudo ninja -C build install`:

1. Clic dret sobre un fitxer → submenú "Etiquetes" amb els 7 colors.
2. Marcar un color → apareix el punt sobre la icona; el ✓ queda marcat.
3. Marcar-ne un segon → es veuen dos punts.
4. Desmarcar un color → desapareix el punt corresponent.
5. "Treu les etiquetes" → desapareixen tots els punts.
6. Selecció **múltiple** → assignar/treure aplica a tots; el ✓ surt marcat només si
   tots el tenen.
7. **Persistència:** tancar i tornar a obrir Files → les etiquetes hi són.
8. Es veuen els punts a les vistes **icones, llista i columnes**.
9. Seleccionar un fitxer etiquetat → la **columna de preview** mostra la fila
   "Etiquetes" amb punts + noms.
10. Fitxer en backend remot sense suport → no trenca (acció ignorada/registrada).

## Fora d'abast (YAGNI)

- Part B: secció "Etiquetes" a la barra lateral i filtre per color (cicle futur;
  requerirà índex invers).
- Colors personalitzats o reanomenar etiquetes.
- Sincronització/compatibilitat amb les etiquetes de macOS o Nautilus.
- Drecera de teclat per etiquetar (es pot afegir més endavant).
