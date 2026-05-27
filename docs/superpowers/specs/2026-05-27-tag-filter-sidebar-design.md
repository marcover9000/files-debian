# Filtre per etiqueta a la barra lateral (③, `tag://` virtual) — Disseny

**Data:** 2026-05-27
**Fork:** `marcover9000/files-debian`, branca `gnome-43` (base elementary/files `7.1.6`)
**Estat:** Aprovat, pendent de pla d'implementació

## Objectiu

Afegir una secció **"Etiquetes"** a la barra lateral que llisti els colors **en ús**;
en clicar-ne un, mostrar **tots els fitxers amb aquell color**, estiguin al directori
que estiguin, com si fos una carpeta. Tercera i última peça del sistema d'etiquetes
(① noms ✓ → ② estil ✓ → ③ filtre).

**Avís d'abast:** és la peça més gran del sistema; toca internes de `Directory`
(libcore) i la barra lateral (src). L'arrel d'escaneig és la **carpeta personal**.

## Decisions preses (brainstorming)

1. **Enfocament:** ubicació virtual `tag://N` amb **enumeració custom** dins `Directory`
   (no hi ha backend GVfs `tag:`; els Recents sí que en tenen, per això no calen allà).
2. **Quins tags es mostren:** només els colors **en ús**, via un registre persistit
   `used-tag-colors`, amb **neteja mandrosa** (quan `tag://N` carrega 0 fitxers → s'elimina).
3. **Arrel d'escaneig:** la carpeta personal (`GLib.Environment.get_home_dir ()`).

## Situació de partida

- `Directory` (`libcore/Directory.vala`, ~1356 línies):
  - `scheme` es deriva de la ubicació; `is_recent`, `is_local`, `can_load`, etc.
  - `recent://` s'enumera via GVfs amb `location.enumerate_children_async` (línia ~700)
    dins `list_directory_async`; els fitxers es processen amb `after_load_file
    (gof, show_hidden, file_loaded_func)` i s'insereixen a `file_hash`.
  - Senyals/estats de càrrega (`State.LOADING/LOADED`, `done_loading`) reutilitzables.
- Els fitxers de Recents tenen pare real i la vista ja els mostra agregats → el mateix
  servirà per a `tag://`.
- `Files.File.color` (int 1-10) i `metadata::color-tag` (plugin `ctags`); el plugin
  `set_color` escriu l'atribut.
- `Files.ColorTags` (libcore): `display_name`, `generic_name`, `get_names/set_names`,
  `show_as_dot`. S'hi afegirà el registre d'ús.
- `src/View/Sidebar/SidebarWindow.vala`: seccions com `SidebarExpander` + `Gtk.Revealer`
  amb un listbox (`BookmarkListBox`, `DeviceListBox`, `NetworkListBox`). Naveguen per uri.
- `libcore/Resources.vala`: `protocol_to_name (protocol)` (cas `recent` existent).
- Esquema: `data/schemas/io.elementary.files.gschema.xml`.

## Arquitectura proposada

### 1. Registre de colors en ús (`Files.ColorTags`, libcore)

- Nova clau gsettings `used-tag-colors` (`ai`, default `[]`).
- Mètodes: `int[] used_colors ()`, `void mark_used (int color)` (afegeix si no hi és),
  `void unmark_used (int color)` (elimina).
- El plugin `ctags` `set_color`: quan assigna `n >= 1`, crida `ColorTags.mark_used (n)`.

### 2. Enumeració `tag://N` (`Directory`, libcore)

- Tractar `scheme == "tag"` com a **local i carregable** (al construct: afegir-lo a
  `is_local`, no marcar-lo com a remot/no-info; `can_load = true`).
- A `list_directory_async`, ramificar: si `scheme == "tag"`, en lloc d'enumerar amb
  GIO, cridar un mètode nou `enumerate_tag_async (color, file_loaded_func)` que:
  - Llegeix el color de l'URI (`tag://3` → 3) — via `location.get_uri ()`.
  - Recorre recursivament `GLib.Environment.get_home_dir ()` amb
    `enumerate_children_async` per directori (cua de directoris, async, cancel·lable),
    demanant `standard::*` + `metadata::color-tag`.
  - Per a cada fitxer amb `metadata::color-tag == color`: crear/recuperar `Files.File`,
    assignar `info`, `update ()`, inserir a `file_hash` i cridar `after_load_file (...)`
    (la mateixa via que la càrrega normal).
  - Salta directoris sense permís o amb error (no trenca).
  - En acabar: `state = LOADED`; si `displayed_files_count == 0` →
    `Files.ColorTags.unmark_used (color)`.

### 3. Connexió de l'esquema

- El **títol de pestanya** d'una ubicació `tag://n` es resol al `ViewContainer`
  (a `update_tab_name`, que ja tracta esquemes especials via `protocol_to_name`):
  per a l'esquema `tag` es mostra `Files.ColorTags.display_name (n)` (el nom del color,
  propi o genèric), llegint `n` de l'URI. `protocol_to_name ("tag")` retorna "Tags"
  com a fallback genèric.
- Assegurar que `tag://N` no es reescriu com a ruta de fitxer en construir la
  `Directory`/`Files.File` (acceptar l'esquema tal qual).

### 4. Secció "Etiquetes" a la barra lateral (src)

- `src/View/Sidebar/TagListBox.vala` (nou): un listbox que, per cada color de
  `ColorTags.used_colors ()`, crea una fila amb el **punt de color** + el `display_name`,
  i en activar-se demana navegar a `tag://<n>` (via el mateix mecanisme
  `path_change_request`/`open` que les altres files de la barra lateral).
- `SidebarWindow`: afegir un `SidebarExpander ("Tags")` + `Gtk.Revealer` amb el
  `TagListBox`, després de Bookmarks/Storage/Network. Persistir l'estat de l'expander
  amb una clau gsettings `sidebar-cat-tags-expander` (com les altres seccions).
- El `TagListBox` es reconstrueix quan canvia `used-tag-colors` (senyal
  `changed["used-tag-colors"]`) → afegir/treure files en viu.

### 5. Flux de dades

1. Assignar groc a un fitxer → `set_color (…, 4)` → `ColorTags.mark_used (4)` →
   `used-tag-colors` canvia → el `TagListBox` afegeix la fila "Dev" (nom del groc).
2. Clicar la fila → navega a `tag://4` → `Directory` recorre la carpeta personal i
   alimenta tots els fitxers amb color 4 → la vista els mostra.
3. Si es treu l'últim groc i s'obre `tag://4` → 0 fitxers → `unmark_used (4)` →
   la fila desapareix.

## Gestió d'errors

- Subdirectoris sense permís / errors d'E/S → s'ometen, l'escaneig continua.
- Canvi de ubicació durant l'escaneig → `cancellable` atura el recorregut.
- `tag://` amb color invàlid (fora de [1,10]) → càrrega buida.
- L'escaneig pot trigar en carpetes personals grans → es mostra l'estat de càrrega
  habitual de la vista; és cancel·lable.

## Proves

Vala + Meson; sense tests unitaris → verificació **manual** després de
`sudo ninja -C build install`:

1. Etiquetar fitxers amb un mateix color en **directoris diferents**.
2. Apareix la secció "Tags" a la barra lateral amb una fila (punt + nom) per color usat.
3. Clicar la fila → es mostren **tots** els fitxers d'aquell color, de tots els dirs.
4. Obrir un fitxer dels resultats → s'obre correctament (té pare real).
5. Treure el color a tots els fitxers d'un color i obrir-ne la vista → 0 resultats →
   la fila desapareix de la barra lateral.
6. Posar nom al color (①) → la fila del sidebar mostra el nom nou.
7. Escaneig en carpeta personal gran → mostra càrrega, no penja; canviar de lloc el cancel·la.

## Fora d'abast (YAGNI)

- Arrel d'escaneig configurable o múltiples arrels (de moment, la carpeta personal).
- Índex persistent per evitar reescanejar (es reescaneja en obrir `tag://N`).
- Arrossegar fitxers a una etiqueta des de la barra lateral.
- Mostrar el recompte de fitxers per etiqueta a la barra lateral.
