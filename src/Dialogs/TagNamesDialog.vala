/*
 * Lets the user assign a custom name to each of the ten colour tags.
 * Names are persisted via Files.ColorTags (gsettings key `tag-names`).
 */

public class Files.View.TagNamesDialog : Granite.Dialog {
    private Gtk.Entry[] entries;

    public TagNamesDialog (Gtk.Window parent) {
        Object (
            transient_for: parent,
            modal: true
        );
    }

    construct {
        title = _("Tag Names");

        var grid = new Gtk.Grid () {
            column_spacing = 12,
            row_spacing = 6
        };

        var names = Files.ColorTags.get_names ();
        entries = new Gtk.Entry[10];
        for (int i = 0; i < 10; i++) {
            int color = i + 1;

            var dot = new Gtk.Image.from_surface (make_dot (color)) {
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.CENTER
            };

            var entry = new Gtk.Entry () {
                hexpand = true,
                placeholder_text = Files.ColorTags.generic_name (color),
                text = names[i]
            };
            entries[i] = entry;

            grid.attach (dot, 0, i);
            grid.attach (entry, 1, i);
        }

        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
            margin_start = 18,
            margin_end = 18,
            margin_top = 12,
            margin_bottom = 18
        };
        content.add (new Granite.HeaderLabel (_("Tag Names")));
        content.add (grid);

        get_content_area ().add (content);

        add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
        var done_button = (Gtk.Button) add_button (_("Done"), Gtk.ResponseType.OK);
        done_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);

        response.connect ((id) => {
            if (id == Gtk.ResponseType.OK) {
                save ();
            }
            destroy ();
        });

        resizable = false;
        show_all ();
    }

    private void save () {
        var names = new string[10];
        for (int i = 0; i < 10; i++) {
            names[i] = entries[i].text.strip ();
        }
        Files.ColorTags.set_names (names);
    }

    private Cairo.Surface make_dot (int color) {
        const int PX = 16;
        var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, PX, PX);
        var cr = new Cairo.Context (surface);
        var rgba = Gdk.RGBA ();
        rgba.parse (Files.Preferences.TAGS_COLORS[color] ?? "#000000");
        cr.arc (PX / 2.0, PX / 2.0, PX / 2.0 - 2, 0, 2 * GLib.Math.PI);
        cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, 1.0);
        cr.fill ();
        surface.flush ();
        return surface;
    }
}
