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
