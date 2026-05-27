/***
    Copyright (c) ammonkey 2011 <am.monkeyd@gmail.com>

    Marlin is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the
    Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Marlin is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
    See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program.  If not, see <http://www.gnu.org/licenses/>.
***/

public class Files.Plugins.CTags : Files.Plugins.Base {
    /* May be used by more than one directory simultaneously so do not make assumptions */
    private Cancellable cancellable;
    private GLib.List<Files.File> current_selected_files;

    public CTags () {
        cancellable = new Cancellable ();
    }

    /* Colour tags are stored solely in the file's GVfs metadata (metadata::color-tag).
     * The legacy io.elementary.files.db daemon lookup has been dropped: it is unreliable
     * on non-elementary systems and the metadata is the source of truth. */
    private async void read_color_async (Files.File file) {
        try {
            var info = yield file.location.query_info_async (
                "metadata::color-tag", FileQueryInfoFlags.NONE
            );

            int color = 0;
            if (info.has_attribute ("metadata::color-tag")) {
                color = int.parse (info.get_attribute_string ("metadata::color-tag"));
            }

            if (file.color != color) {
                file.color = color;
                file.icon_changed (); /* Trigger redraw - the underlying GFile has not changed */
            }
        } catch (Error err) {
            if (!(err is IOError.CANCELLED)) {
                warning ("Could not read colour tag for %s: %s", file.uri, err.message);
            }
        }
    }

    public override void update_file_info (Files.File file) {
        if (!file.is_hidden || Files.Preferences.get_default ().show_hidden_files) {
            read_color_async.begin (file);
        }
    }

    public override void context_menu (Gtk.Widget widget, GLib.List<Files.File> selected_files) {
        if (selected_files == null) {
            return;
        }

        var menu = widget as Gtk.Menu;
        var color_menu_item = new ColorWidget ();
        current_selected_files = selected_files.copy_deep ((GLib.CopyFunc) GLib.Object.ref);

        /* Check the colors currently set */
        foreach (Files.File gof in current_selected_files) {
            color_menu_item.check_color (gof.color);
        }

        color_menu_item.color_changed.connect ((ncolor) => {
            set_color.begin (current_selected_files, ncolor);
        });

        add_menuitem (menu, new Gtk.SeparatorMenuItem ());
        add_menuitem (menu, color_menu_item);
    }

    private void add_menuitem (Gtk.Menu menu, Gtk.MenuItem menu_item) {
        menu.append (menu_item);
        menu_item.show ();
    }

    private async void set_color (GLib.List<Files.File> files, int n) throws Error {
        foreach (unowned Files.File file in files) {
            if (!(file is Files.File)) {
                continue;
            }

            Files.File target_file;
            if (file.location.has_uri_scheme ("recent")) {
                target_file = Files.File.get_by_uri (file.get_display_target_uri ());
            } else {
                target_file = file;
            }

            if (target_file.color != n) {
                target_file.color = n;
                target_file.location.set_attribute_string ("metadata::color-tag", n.to_string (), FileQueryInfoFlags.NONE);
                target_file.icon_changed ();
            }
        }

        if (files != null) {
            /* If the color of the target is set while in recent view, we have to
             * update the recent view to reflect this */
            foreach (unowned Files.File file in files) {
                if (file.location.has_uri_scheme ("recent")) {
                    file.color = n;
                    file.icon_changed (); /* Just need to trigger redraw */
                }
            }
        }
    }

    private class ColorButton : Gtk.CheckButton {
        private static Gtk.CssProvider css_provider;
        public string color_name { get; construct; }

        static construct {
            css_provider = new Gtk.CssProvider ();
            css_provider.load_from_resource ("io/elementary/files/ColorButton.css");
        }

        public ColorButton (string color_name) {
            Object (color_name: color_name);
        }

        construct {
            var style_context = get_style_context ();
            style_context.add_provider (css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            style_context.add_class (Granite.STYLE_CLASS_COLOR_BUTTON);
            style_context.add_class (color_name);
        }
    }

    private class ColorWidget : Gtk.MenuItem {
        public signal void color_changed (int ncolor);
        private ColorButton color_button_remove;
        private Gee.ArrayList<ColorButton> color_buttons;
        private const int COLORBOX_SPACING = 3;

        construct {
            color_button_remove = new ColorButton ("none");
            color_buttons = new Gee.ArrayList<ColorButton> ();
            color_buttons.add (new ColorButton ("blue"));
            color_buttons.add (new ColorButton ("mint"));
            color_buttons.add (new ColorButton ("green"));
            color_buttons.add (new ColorButton ("yellow"));
            color_buttons.add (new ColorButton ("orange"));
            color_buttons.add (new ColorButton ("red"));
            color_buttons.add (new ColorButton ("pink"));
            color_buttons.add (new ColorButton ("purple"));
            color_buttons.add (new ColorButton ("brown"));
            color_buttons.add (new ColorButton ("slate"));

            var colorbox = new Gtk.Grid () {
                column_spacing = COLORBOX_SPACING,
                margin_start = 3,
                halign = Gtk.Align.START
            };

            colorbox.add (color_button_remove);

            for (int i = 0; i < color_buttons.size; i++) {
                colorbox.add (color_buttons[i]);
            }

            add (colorbox);

            try {
                string css = ".nohover { background: none; }";

                var css_provider = new Gtk.CssProvider ();
                css_provider.load_from_data (css, -1);

                var style_context = get_style_context ();
                style_context.add_provider (css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
                style_context.add_class ("nohover");
            } catch (GLib.Error e) {
                warning ("Failed to parse css style : %s", e.message);
            }

            show_all ();

            // The menu item swallows clicks on its children, so dispatch them ourselves
            // by hit-testing the actual button allocations (robust to spacing/theme).
            button_press_event.connect (button_pressed_cb);
        }

        private void clear_checks () {
            color_buttons.foreach ((b) => { b.active = false; return true; });
        }

        public void check_color (int color) {
            if (color <= 0 || color > color_buttons.size) {
                return;
            }

            color_buttons[color - 1].active = true;
        }

        private bool widget_hit (Gtk.Widget w, double ex, double ey) {
            int tx, ty;
            if (!w.translate_coordinates (this, 0, 0, out tx, out ty)) {
                return false;
            }

            Gtk.Allocation alloc;
            w.get_allocation (out alloc);
            return ex >= tx && ex <= tx + alloc.width && ey >= ty && ey <= ty + alloc.height;
        }

        private bool button_pressed_cb (Gdk.EventButton event) {
            double ex, ey;
            event.get_coords (out ex, out ey);

            /* "none" removes the colour (index 0) */
            if (widget_hit (color_button_remove, ex, ey)) {
                clear_checks ();
                color_changed (0);
                return true;
            }

            for (int i = 0; i < color_buttons.size; i++) {
                if (widget_hit (color_buttons[i], ex, ey)) {
                    clear_checks ();
                    color_buttons[i].active = true;
                    color_changed (i + 1);
                    return true;
                }
            }

            return true;
        }
    }
}

public Files.Plugins.Base module_init () {
    return new Files.Plugins.CTags ();
}
