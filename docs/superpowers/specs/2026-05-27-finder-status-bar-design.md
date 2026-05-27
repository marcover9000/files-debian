# Barra d'estat estil Finder — Disseny

**Data:** 2026-05-27
**Fork:** `marcover9000/files-debian`, branca `gnome-43` (base elementary/files `7.1.6`)
**Estat:** Aprovat, pendent de pla d'implementació

## Objectiu

Donar a Pantheon Files una barra d'estat inferior **persistent i sempre visible**,
a l'estil de la barra inferior del Finder de macOS, que mostri l'estat de la carpeta
i de la selecció. Forma part de la línia general del fork: aproximar la sensació
d'ús a la de macOS sobre Debian 12 / GNOME 43.

## Decisions preses (brainstorming)

1. **Reaprofitar `OverlayBar`** en lloc de crear un widget nou ni mantenir-ne dos.
   Es conserva tota la lògica de càlcul existent (recompte i mida de selecció,
   resolució d'imatges, deep-count de carpetes) i només se'n canvia l'ancoratge i
   s'hi afegeix un estat nou.
2. **Estat de repòs (sense selecció):** mostrar `N elements · X GB lliures`
   (estil Finder).
3. **Estat de selecció:** mantenir el text ric actual sense canvis (zero risc).
4. **Sempre visible:** sense toggle ni opció de menú ni gsetting. Ancorada a baix.

## Situació de partida

- `src/View/Widgets/OverlayBar.vala`: subclasse de `Granite.Widgets.OverlayBar`.
  És un overlay flotant transitori a la cantonada inferior (`halign = END`). Quan
  no hi ha res a mostrar, `label = ""` i `visible = false`. Calcula:
  - fitxer únic → `nom – tipus (mida)` (+ resolució si és imatge, + deep-count si és carpeta)
  - selecció múltiple → `N ítems seleccionats (mida)` / variants amb carpetes
- `src/View/ViewContainer.vala` (`Gtk.Box`):
  - crea l'OverlayBar a la línia ~240 sobre `view.overlay`
  - `on_slot_selection_changed()` (línia ~598) hi reenvia `selection_changed(files)`
- `src/View/Slot.vala`:
  - `displayed_files_count` (línia 37) → total d'ítems visibles de la carpeta
  - `directory.done_loading` (línia 166) → senyal en acabar de carregar la carpeta
- Espai lliure: patró existent a `src/View/Sidebar/AbstractMountableRow.vala:301`
  → `root.query_filesystem_info_async("filesystem::*")` + `FileAttribute.FILESYSTEM_FREE`.
- `src/View/Window.vala:105`: senyal `free_space_change`.

## Arquitectura proposada

Transformar `OverlayBar` d'overlay flotant a **barra horitzontal ancorada a baix**,
a tota l'amplada, sota el contingut de la vista, i afegir-hi un **estat de repòs**.

### Canvis estructurals

1. **Ancoratge (`ViewContainer`):** deixar de tractar l'OverlayBar com a overlay
   flotant a la cantonada. Empaquetar-lo com a barra inferior dins un contenidor
   vertical (el contingut de la vista a dalt, la barra a baix). Com que
   `ViewContainer` ja és un `Gtk.Box`, caldrà assegurar orientació vertical o
   embolcallar contingut+barra en un `Gtk.Box` vertical.
2. **Estat de repòs (`OverlayBar`):** nou mètode `show_folder_summary()` que,
   quan no hi ha selecció, en lloc d'amagar la barra, hi mostra
   `N elements · X GB lliures`.

### Estats de la barra

| Situació           | Text                                          | Origen                                   |
|--------------------|-----------------------------------------------|------------------------------------------|
| Sense selecció     | `24 elements · 87,3 GB lliures`               | `Slot.displayed_files_count` + free space |
| 1 fitxer           | `nom – tipus (mida)` (+ resolució/deep-count) | lògica existent, sense canvis            |
| Selecció múltiple  | `N ítems seleccionats (mida)`                 | lògica existent, sense canvis            |

### Flux de dades

- `directory.done_loading` **i** selecció buida → `show_folder_summary()`:
  - llegeix `displayed_files_count`
  - dispara consulta async d'espai lliure (cancel·lable) sobre la ubicació actual
- L'espai lliure es **cacheja** per la ubicació actual; es recalcula en canviar de
  carpeta o en rebre `Window.free_space_change`.
- Selecció no buida → `selection_changed()` actual, sense canvis.

### Integració visual

- CSS a `gnome-integration/gtk-3.0/gtk.css` per donar aspecte de barra fixa: vora
  superior fina, alçada discreta, fons coherent amb el tema Breeze de l'usuari.
  En línia amb els overrides CSS que el fork ja hi té.

## Gestió d'errors

- **Consulta d'espai async i cancel·lable:** si falla o es cancel·la (canvi ràpid
  de carpeta), degradació elegant → mostrar només `N elements` sense l'espai.
- **Ubicacions remotes/de xarxa:** si `query_filesystem_info` no retorna
  `FILESYSTEM_FREE`, ometre la part d'espai i mostrar només el recompte.
- **Carpeta buida:** `0 elements · X GB lliures`.

## Proves

Projecte Vala compilat amb Meson; la base no té tests unitaris. Verificació
**manual** després de compilar i instal·lar:

1. Carpeta local amb fitxers → `N elements · X GB lliures`.
2. Selecció d'1 fitxer → text ric actual (nom/tipus/mida).
3. Selecció múltiple → `N ítems seleccionats (mida)`.
4. Carpeta remota/de xarxa → només recompte, sense espai.
5. Canvi ràpid entre carpetes → sense errors ni text obsolet (cancel·lació OK).
6. Carpeta buida → `0 elements · X GB lliures`.
7. La barra és visible permanentment a baix, a totes les vistes (icones, llista, columnes).

## Fora d'abast (YAGNI)

- Toggle de visibilitat / opció de menú / gsetting.
- Canvis al text de selecció.
- Indicadors addicionals (p. ex. progrés d'operacions de fitxers a la mateixa barra).
