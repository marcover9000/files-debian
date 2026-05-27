# Preview de contingut real per tipus — Disseny

**Data:** 2026-05-27
**Fork:** `marcover9000/files-debian`, branca `gnome-43` (base elementary/files `7.1.6`)
**Estat:** Aprovat, pendent de pla d'implementació

## Objectiu

Ampliar la columna de preview de la vista de columnes (Miller) perquè mostri el
**contingut real** del fitxer seleccionat segons el seu tipus, en lloc de només
l'icona MIME:
- Imatge → la imatge.
- PDF → la primera pàgina renderitzada.
- Text (ampli: .md, .txt, .env, codi, json…) → el contingut amb scroll.
- Qualsevol altra cosa o error → l'icona MIME gran (com ara).

Continua la línia del fork d'aproximar la sensació d'ús a la del Finder de macOS.

## Decisions preses (brainstorming)

1. **Detecció de text:** ampla. Compta com a text si `ContentType.is_a(t, "text/plain")`,
   o el tipus comença per `text/`, o és un tipus textual conegut (json, xml, yaml,
   javascript, x-shellscript, toml…), o el sniff dels primers bytes indica UTF-8
   sense bytes NUL.
2. **Quantitat de text:** el fitxer sencer, amb scroll vertical.
3. **PDF:** només la primera pàgina (per al document sencer ja hi ha el Quick Look
   amb Espai via Sushi).
4. **Fallback:** tot el que no sigui imatge/PDF/text, o qualsevol error, mostra
   l'icona MIME gran.

## Situació de partida

- `src/View/Widgets/PreviewColumn.vala` (ja existent, fet en el cicle anterior):
  `Gtk.ScrolledWindow` amb `Gtk.Image` (via `get_icon_pixbuf` + sistema de thumbnails)
  + `name_label` + `info_grid` (Tipus/Mida/Dimensions/Modificat). El problema actual:
  el sistema de thumbnails no entrega miniatura per al fitxer seleccionat a Miller,
  així que sempre es veu l'icona MIME.
- `Files.File`: `get_ftype()` (content-type), `is_image()`, `location` (`GLib.File`),
  `get_display_name()`, `formated_type`, `get_formated_time()`, `width`/`height`.
- `poppler-glib` 22.12.0 instal·lat; vapi a `/usr/share/vala-0.56/vapi/poppler-glib.vapi`
  (valac l'agafa amb `--pkg poppler-glib`). El projecte encara NO el llinka.
- `GtkSourceView` (dev) NO disponible → el text es mostra sense ressaltat de sintaxi.
- `src/meson.build` llista fonts i dependències explícitament.

## Arquitectura proposada

Refactoritzar `PreviewColumn` perquè despatxi un **renderitzador segons el tipus**
i mostri el resultat en una zona de preview que canvia de widget. Afegir
`poppler-glib` com a dependència de build.

### Canvi de disposició

`PreviewColumn` passa de `Gtk.ScrolledWindow` a `Gtk.Box` (VERTICAL):

1. `content_holder` (`Gtk.Box` VERTICAL, `vexpand = true`) — conté el widget de
   preview actual; es buida i es reomple a cada `set_file`.
2. `Gtk.Separator`.
3. `name_label` (negreta, ellipsize).
4. `info_grid` (metadades; igual que ara).

Widgets de preview que es col·loquen a `content_holder`:
- **Imatge / PDF / icona:** un `Gtk.Image` centrat.
- **Text:** un `Gtk.ScrolledWindow` (vexpand) amb un `Gtk.TextView` monoespai,
  `editable = false`, `monospace = true`, `wrap_mode = WORD_CHAR`.

### Despatx per tipus a `set_file(file)`

Ordre d'avaluació sobre `ctype = file.get_ftype()`:

1. `file.is_image()` o `ContentType.is_a(ctype, "image/*")` → **render_image**.
2. `ctype == "application/pdf"` → **render_pdf**.
3. `looks_like_text(file, ctype)` → **render_text**.
4. Altrament → **render_icon** (icona MIME gran via `get_icon_pixbuf`).

`looks_like_text(file, ctype)`:
- cert si `ContentType.is_a(ctype, "text/plain")`, o `ctype` comença per `"text/"`,
  o `ctype` és a l'allowlist {`application/json`, `application/xml`,
  `application/x-yaml`, `application/javascript`, `application/x-shellscript`,
  `application/toml`, `application/x-desktop`};
- si no, sniff: llegir els primers 4096 bytes; cert si no contenen cap byte `0x00`
  i són UTF-8 vàlids.

### Renderitzadors

- **render_image:** `Gdk.Pixbuf.new_from_stream_at_scale_async` des de
  `file.location.read()`, amplada objectiu = amplada de la columna (menys marges),
  preservant aspecte; en acabar, `image.set_from_surface` amb el `scale_factor`.
- **render_pdf:** `Poppler.Document.new_from_gfile(file.location, null, null)`;
  si té ≥ 1 pàgina, agafar la pàgina 0, calcular escala per ajustar a l'amplada,
  pintar sobre un `Cairo.ImageSurface` i posar-lo a la `Gtk.Image`.
- **render_text:** llegir el fitxer (async) fins a un màxim de seguretat de
  10 MB; posar el text al `Gtk.TextView`.
- **render_icon:** com ara, `file.get_icon_pixbuf(256, scale)`.

### Càrrega async i cancel·lació

Cada `set_file` crea un `Cancellable` nou i cancel·la l'anterior. Les operacions
async (lectura d'imatge i de text) comproven la cancel·lació; si el fitxer actual
ja no coincideix en acabar, es descarta el resultat. El render del PDF (una pàgina)
es fa al moment.

## Gestió d'errors / seguretat

- Qualsevol error de render (imatge corrupta, PDF il·legible, lectura fallida,
  permís denegat, remot) → fallback a `render_icon`.
- Text > 10 MB → es llegeix fins al límit (degradació elegant; evita congelar la UI).
- Canvi ràpid de selecció → resultats obsolets descartats per cancel·lació.
- PDF sense pàgines → fallback a icona.

## Proves

Vala + Meson; sense tests unitaris → verificació **manual** després de
`sudo ninja -C build install`:

1. **Imatge** (JPG/PNG) → es veu la imatge escalada, nítida.
2. **PDF** → primera pàgina renderitzada.
3. **.md / .txt / .env / codi font / .json** → contingut com a text amb scroll.
4. **Dotfile sense extensió** (p. ex. `.gitignore`) → es mostra com a text.
5. **Binari / executable / tipus desconegut** → icona MIME gran.
6. **Fitxer de text molt gran** (>10 MB) → no es penja; mostra fins al límit.
7. **Canvi ràpid** entre fitxers de tipus diferents → sense previews creuats ni errors.
8. Seleccionar carpeta / selecció múltiple / deseleccionar → desapareix el preview
   (comportament ja existent de Miller, no ha de regressar).

## Fora d'abast (YAGNI)

- PDF multipàgina (només primera pàgina; el sencer ja és el Quick Look amb Espai).
- Ressaltat de sintaxi (no hi ha GtkSourceView dev).
- Reproducció de vídeo/àudio inline (ho cobreix Sushi).
- Preview a les vistes d'icones i llista.
- Edició del contingut o de metadades.
