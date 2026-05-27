/*
 * Finder-style preview column for the Miller (column) view.
 * Shows a large thumbnail/icon plus a metadata grid for the selected file.
 */

namespace Files.View {
    public class PreviewColumn : Gtk.ScrolledWindow {
        private const int PREVIEW_ICON_SIZE = 256;

        private Gtk.Image image;
        private Gtk.Label name_label;
        private Gtk.Grid info_grid;
        private Files.File? current_file = null;
        private ulong thumb_handler_id = 0;
        private int thumb_request = -1;

        construct {
            hscrollbar_policy = Gtk.PolicyType.NEVER;
            vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
            get_style_context ().add_class ("files-preview-column");

            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6) {
                margin = 12,
                valign = Gtk.Align.START
            };

            image = new Gtk.Image () {
                halign = Gtk.Align.CENTER
            };

            name_label = new Gtk.Label (null) {
                halign = Gtk.Align.CENTER,
                ellipsize = Pango.EllipsizeMode.MIDDLE,
                max_width_chars = 24
            };
            name_label.get_style_context ().add_class ("heading");

            info_grid = new Gtk.Grid () {
                column_spacing = 8,
                row_spacing = 4,
                margin_top = 6,
                halign = Gtk.Align.FILL
            };

            box.add (image);
            box.add (name_label);
            box.add (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            box.add (info_grid);

            add (box);
            box.show_all ();
        }

        ~PreviewColumn () {
            disconnect_thumb ();
        }

        public void set_file (Files.File? file) {
            disconnect_thumb ();
            current_file = file;
            if (file == null) {
                return;
            }

            update_image ();
            populate_info (file);

            if (file.thumbstate != Files.File.ThumbState.READY) {
                var thumbnailer = Files.Thumbnailer.@get ();
                if (thumbnailer != null && thumbnailer.queue_file (file, out thumb_request)) {
                    thumb_handler_id = thumbnailer.finished.connect (on_thumbnail_finished);
                }
            }
        }

        private void on_thumbnail_finished (uint request) {
            if ((int) request == thumb_request && current_file != null) {
                update_image ();
                disconnect_thumb ();
            }
        }

        private void disconnect_thumb () {
            if (thumb_handler_id != 0) {
                var thumbnailer = Files.Thumbnailer.@get ();
                if (thumbnailer != null) {
                    thumbnailer.disconnect (thumb_handler_id);
                }
                thumb_handler_id = 0;
            }
            thumb_request = -1;
        }

        private void update_image () {
            if (current_file == null) {
                return;
            }

            var scale = get_scale_factor ();
            var pix = current_file.get_icon_pixbuf (PREVIEW_ICON_SIZE, scale);
            if (pix != null) {
                var surface = Gdk.cairo_surface_create_from_pixbuf (pix, scale, null);
                image.set_from_surface (surface);
            }
        }

        private void populate_info (Files.File file) {
            info_grid.@foreach ((w) => {
                w.destroy ();
            });

            name_label.label = file.get_display_name ();

            int row = 0;
            var ftype = (file.formated_type != null && file.formated_type != "")
                            ? file.formated_type : file.get_ftype ();
            add_info_row (ref row, _("Type"), ftype);
            add_info_row (ref row, _("Size"), format_size (PropertiesWindow.file_real_size (file)));
            if (file.is_image () && file.width > 0) {
                add_info_row (ref row, _("Dimensions"), "%i × %i".printf (file.width, file.height));
            }
            add_info_row (ref row, _("Modified"), file.get_formated_time (GLib.FileAttribute.TIME_MODIFIED));

            info_grid.show_all ();
        }

        private void add_info_row (ref int row, string key, string? value) {
            if (value == null || value == "") {
                return;
            }

            var key_label = new Gtk.Label (key) {
                halign = Gtk.Align.END,
                xalign = 1
            };
            key_label.get_style_context ().add_class ("dim-label");

            var val_label = new Gtk.Label (value) {
                halign = Gtk.Align.START,
                xalign = 0,
                wrap = true,
                selectable = true
            };

            info_grid.attach (key_label, 0, row, 1, 1);
            info_grid.attach (val_label, 1, row, 1, 1);
            row++;
        }
    }
}
