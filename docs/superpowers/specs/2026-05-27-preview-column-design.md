# Preview pane a la vista de columnes — Disseny

**Data:** 2026-05-27
**Fork:** `marcover9000/files-debian`, branca `gnome-43` (base elementary/files `7.1.6`)
**Estat:** Aprovat, pendent de pla d'implementació

## Objectiu

Afegir a la vista de columnes (Miller) una columna de **vista prèvia estil Finder**:
en seleccionar un fitxer (no carpeta), apareix com a columna més a la dreta un
panell amb una miniatura gran i un bloc de metadades. Forma part de la línia del
fork d'aproximar la sensació d'ús a la de macOS.

## Decisions preses (brainstorming)

1. **Contingut:** preview + informació complet → miniatura/icona gran a dalt, nom,
   i graella de metadades (tipus, mida, dimensions si és imatge, data de modificació).
2. **Miniatures:** es reaprofita el sistema existent. `Files.File.get_icon_pixbuf(size,
   scale, USE_THUMBNAILS)` retorna la miniatura real quan el sistema la pot generar
   (imatges, PDFs, vídeos…) i, si no, l'icona MIME gran. Sense distingir tipus a mà.
3. **Amplada:** com les altres columnes i **redimensionable** arrossegant la vora,
   integrada amb el mecanisme de columnes de Miller.
4. **Abast:** només la vista de columnes (Miller). Icones i llista no es toquen.

## Situació de partida

- `src/View/Miller.vala` (`Files.AbstractSlot`):
  - `colpane` (`Gtk.Box` HORIZONTAL) dins un viewport dins `scrolled_window`.
  - Cada columna és un `View.Slot` empaquetat com `hpane` = `Gtk.Paned(HORIZONTAL)`
    amb `pack1(directory_view, false, false)` i `pack2(slot.colpane, true, true)`.
    El `colpane` d'un slot conté l'`hpane` del slot següent (estructura niuada).
  - `add_location(loc, host)` crea i afegeix una columna (slot) nova.
  - `truncate_list_after_slot(slot)` elimina les columnes a la dreta d'un slot
    (fa `colpane.@foreach` + remove).
  - `slot_list`, `current_slot`, `total_width`, `update_total_width()`,
    `calculate_total_width()` gestionen amplada i scroll.
  - `connect_slot_signals` connecta `slot.selection_changed` →
    `on_slot_selection_changed(files)` que ara només reemet `selection_changed(files)`.
  - Navegar a una carpeta passa per `miller_slot_request` → `on_miller_slot_request`
    → `add_location` (columna nova). Seleccionar un fitxer NO crea columna.
- `Files.File` (`libcore/File.vala`):
  - `get_icon_pixbuf(int size, int scale, IconFlags flags = USE_THUMBNAILS)`.
  - `thumbstate` / `thumbnail_path` / `pix`; sistema `Thumbnailer` (`libcore/Thumbnailer.vala`).
  - `formated_type`, `format_size`, `width`/`height` (imatges), `info` (GFileInfo amb
    nom i `get_modification_date_time()`).
- `PropertiesWindow.file_real_size(file)` calcula la mida real (ja usat per `OverlayBar`).

## Arquitectura proposada

### Component nou: `PreviewColumn`

Fitxer nou `src/View/Widgets/PreviewColumn.vala`. Widget autocontingut.

- **Què fa:** donat un `Files.File`, mostra miniatura gran + nom + metadades.
- **Com s'usa:** `set_file(Files.File? file)` actualitza el contingut; amb `null` es buida.
- **De què depèn:** `Files.File`, `Thumbnailer`, `PropertiesWindow.file_real_size`.

Estructura interna (`Gtk.Box` VERTICAL dins un `Gtk.ScrolledWindow` per si les
metadades no caben):

1. `Gtk.Image` central amb la miniatura/icona gran (p. ex. 128–256 px segons l'escala).
2. `Gtk.Label` amb el nom (negreta, `ellipsize = END`, `max_width_chars`).
3. `Gtk.Separator`.
4. `Gtk.Grid` de metadades, una fila per camp (etiqueta + valor):
   - **Tipus:** `file.formated_type`
   - **Mida:** `format_size (PropertiesWindow.file_real_size (file))`
   - **Dimensions:** `"%i × %i".printf(width, height)` només si el tipus MIME comença
     per `image/` i `width > 0`.
   - **Modificat:** `info.get_modification_date_time()` formatat amb `%x %X` (locale).
   - Els camps sense valor vàlid s'ometen (no es mostra la fila).

**Càrrega de miniatura:** en `set_file`, posar immediatament
`file.get_icon_pixbuf(size, scale, USE_THUMBNAILS)` (retorna icona MIME si encara
no hi ha miniatura). Si `file.thumbstate != READY`, encarregar la miniatura al
`Thumbnailer` i, quan acabi, refer `get_icon_pixbuf` i actualitzar la `Gtk.Image`.
La petició es cancel·la/descarta si `set_file` es torna a cridar amb un altre fitxer.

### Integració a `Miller`

Camp nou `private PreviewColumn? preview_column = null;`.

A `on_slot_selection_changed(files)` (a més de reemetre `selection_changed`):

- Si `files` té **exactament un** element i **no és carpeta** (`!file.is_folder()`),
  i l'slot emissor és l'últim de `slot_list`:
  - Treure qualsevol preview existent.
  - Truncar columnes a la dreta de l'slot emissor (reaprofitant la lògica de
    `truncate_list_after_slot` o equivalent per a no-slots).
  - Crear (o reaprofitar) el `PreviewColumn`, fer `set_file(file)`, empaquetar-lo
    al `colpane` de l'slot emissor com a columna més a la dreta, amb amplada de
    columna i redimensionable (mateix patró `set_size_request(width, -1)` que els
    slots; participa de `total_width`).
  - Fer scroll fins al final (reaprofitant `update_total_width`/scroll existent).
- En qualsevol altre cas (carpeta, selecció múltiple, selecció buida, o navegació
  que crea una columna nova via `add_location`) → **treure** el `preview_column`
  si existeix i posar-lo a `null`.

`add_location` (navegació a carpeta) ha de treure el `preview_column` abans
d'afegir la columna real, perquè el preview no quedi enmig.

`truncate_list_after_slot` ha de contemplar i eliminar també el `preview_column`
si penja del colpane afectat.

## Gestió d'errors

- **Sense miniatura possible** (fitxer especial, remot, error del thumbnailer):
  es queda l'icona MIME gran. Degradació elegant.
- **Fitxer que desapareix** mentre està seleccionat: la propera `selection_changed`
  (buida) treu el preview; a més, si el thumbnailer falla, no trenca.
- **Canvi ràpid de selecció:** la càrrega async de miniatura es descarta si el
  fitxer actual del `PreviewColumn` ja no coincideix.
- **Dimensions:** només es consulten/mostren per a tipus `image/*`; per a la resta
  s'omet la fila (no es força càlcul).

## Proves

Projecte Vala amb Meson; sense tests unitaris a la base → verificació **manual**
després de compilar i instal·lar (`sudo ninja -C build install`):

1. Vista de columnes; seleccionar una **imatge** → columna de preview amb miniatura
   real + Tipus/Mida/Dimensions/Modificat.
2. Seleccionar un **PDF** → miniatura (si el sistema en genera) o icona MIME.
3. Seleccionar un **fitxer de text** o un sense miniatura → icona MIME gran + metadades
   (sense fila Dimensions).
4. Seleccionar una **carpeta** → s'obre columna de contingut, **sense** preview.
5. **Selecció múltiple** o **deseleccionar** → desapareix el preview.
6. Navegar a una carpeta tenint un preview obert → el preview se substitueix per la
   columna nova.
7. **Redimensionar** la columna de preview arrossegant la vora → es comporta com
   les altres columnes.
8. Canvi ràpid de selecció entre fitxers grans → sense miniatures creuades ni errors.

## Fora d'abast (YAGNI)

- Càrrega de la imatge original a alta resolució (s'usa el sistema de miniatures).
- Preview a les vistes d'icones i llista.
- Reproducció de vídeo/àudio o preview interactiu (això ja ho cobreix el Quick Look
  amb Espai via Sushi).
- Edició de metadades des del panell.
