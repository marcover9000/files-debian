/*
 * Finder-style preview column for the Miller (column) view.
 * Renders the actual content of the selected file (image, PDF first page, text)
 * with a large icon fallback, plus a metadata grid.
 */

namespace Files.View {

    /*
     * Draws a pixbuf scaled to fit the space it is given (contained, centred
     * horizontally, top-aligned). Requests a 1x1 minimum so it never forces the
     * preview column wider than the panel — it simply fills whatever room it gets,
     * so resizing the column rescales the content with no horizontal overflow.
     */
    private class PreviewImage : Gtk.DrawingArea {
        private Gdk.Pixbuf? pixbuf = null;

        public PreviewImage () {
            hexpand = true;
            vexpand = true;
        }

        public void set_pixbuf (Gdk.Pixbuf? pix) {
            pixbuf = pix;
            queue_draw ();
        }

        public override void get_preferred_width (out int minimum, out int natural) {
            minimum = 1;
            natural = 1;
        }

        public override void get_preferred_height (out int minimum, out int natural) {
            minimum = 1;
            natural = 1;
        }

        public override bool draw (Cairo.Context cr) {
            if (pixbuf == null) {
                return false;
            }

            int aw = get_allocated_width ();
            int ah = get_allocated_height ();
            if (aw < 1 || ah < 1 || pixbuf.width < 1 || pixbuf.height < 1) {
                return false;
            }

            double s = double.min ((double) aw / pixbuf.width, (double) ah / pixbuf.height);
            double dw = pixbuf.width * s;
            double ox = (aw - dw) / 2.0; // centre horizontally, top-aligned

            cr.save ();
            cr.translate (ox, 0);
            cr.scale (s, s);
            Gdk.cairo_set_source_pixbuf (cr, pixbuf, 0, 0);
            cr.get_source ().set_filter (Cairo.Filter.GOOD);
            cr.paint ();
            cr.restore ();
            return false;
        }
    }

    public class PreviewColumn : Gtk.Box {
        private const int ICON_SIZE = 256;
        private const int PDF_RENDER_WIDTH = 1200; // resolution the first page is rasterised at
        private const size_t MAX_TEXT_BYTES = 10 * 1024 * 1024; // 10 MB safety cap
        private const string[] TEXT_ALLOWLIST = {
            "application/json", "application/xml", "application/x-yaml",
            "application/javascript", "application/x-shellscript",
            "application/toml", "application/x-desktop"
        };

        private Gtk.Box content_holder;
        private Gtk.Label name_label;
        private Gtk.Grid info_grid;
        private Files.File? current_file = null;
        private Cancellable? cancellable = null;

        construct {
            orientation = Gtk.Orientation.VERTICAL;
            spacing = 6;
            get_style_context ().add_class ("files-preview-column");

            content_holder = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
                vexpand = true,
                halign = Gtk.Align.FILL,
                valign = Gtk.Align.FILL,
                margin = 12
            };

            name_label = new Gtk.Label (null) {
                halign = Gtk.Align.CENTER,
                ellipsize = Pango.EllipsizeMode.MIDDLE,
                max_width_chars = 24,
                margin_start = 12,
                margin_end = 12
            };
            name_label.get_style_context ().add_class ("heading");

            info_grid = new Gtk.Grid () {
                column_spacing = 8,
                row_spacing = 4,
                margin = 12,
                margin_top = 6,
                halign = Gtk.Align.FILL
            };

            add (content_holder);
            add (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            add (name_label);
            add (info_grid);
            show_all ();
        }

        ~PreviewColumn () {
            if (cancellable != null) {
                cancellable.cancel ();
            }
        }

        public void set_file (Files.File? file) {
            if (cancellable != null) {
                cancellable.cancel ();
            }
            cancellable = new Cancellable ();
            current_file = file;

            clear_content ();
            if (file == null) {
                return;
            }

            populate_info (file);

            unowned string? ctype = file.get_ftype ();
            if (file.is_image () || (ctype != null && GLib.ContentType.is_a (ctype, "image/*"))) {
                render_image.begin (file, cancellable);
            } else if (ctype == "application/pdf") {
                render_pdf (file);
            } else if (looks_like_text (ctype)) {
                render_text.begin (file, cancellable);
            } else {
                show_icon (file);
            }
        }

        private bool looks_like_text (string? ctype) {
            if (ctype == null || ctype == "application/octet-stream") {
                return true; // unknown: try as text; render_text validates UTF-8 and falls back
            }
            if (GLib.ContentType.is_a (ctype, "text/plain") || ctype.has_prefix ("text/")) {
                return true;
            }
            foreach (unowned string t in TEXT_ALLOWLIST) {
                if (ctype == t) {
                    return true;
                }
            }
            return false;
        }

        private void clear_content () {
            content_holder.@foreach ((w) => {
                w.destroy ();
            });
        }

        /* Shows a pixbuf scaled to fit the panel (used for images and PDFs). */
        private void show_pixbuf (Gdk.Pixbuf pix) {
            clear_content ();
            var view = new PreviewImage ();
            view.set_pixbuf (pix);
            content_holder.add (view);
            content_holder.show_all ();
        }

        /* Shows the MIME icon at its natural size, centred (the fallback). */
        private void show_icon (Files.File file) {
            clear_content ();
            var scale = get_scale_factor ();
            var pix = file.get_icon_pixbuf (ICON_SIZE, scale);
            if (pix != null) {
                var image = new Gtk.Image.from_surface (
                    Gdk.cairo_surface_create_from_pixbuf (pix, scale, null)
                ) {
                    halign = Gtk.Align.CENTER,
                    valign = Gtk.Align.START
                };
                content_holder.add (image);
                content_holder.show_all ();
            }
        }

        private async void render_image (Files.File file, Cancellable cancel) {
            try {
                var stream = yield file.location.read_async (GLib.Priority.DEFAULT, cancel);
                var pix = yield new Gdk.Pixbuf.from_stream_async (stream, cancel);
                if (cancel.is_cancelled () || current_file != file) {
                    return;
                }
                if (pix != null) {
                    show_pixbuf (pix);
                }
            } catch (Error e) {
                if (!cancel.is_cancelled () && current_file == file) {
                    show_icon (file);
                }
            }
        }

        private void render_pdf (Files.File file) {
            try {
                var doc = new Poppler.Document.from_gfile (file.location, null, cancellable);
                if (doc.get_n_pages () < 1) {
                    show_icon (file);
                    return;
                }

                var page = doc.get_page (0);
                double pw, ph;
                page.get_size (out pw, out ph);

                double factor = (pw > 0) ? (double) PDF_RENDER_WIDTH / pw : 1.0;
                int sw = (int) (pw * factor);
                int sh = (int) (ph * factor);
                if (sw < 1 || sh < 1) {
                    show_icon (file);
                    return;
                }

                var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, sw, sh);
                var ctx = new Cairo.Context (surface);
                ctx.set_source_rgb (1, 1, 1); // white page background
                ctx.paint ();
                ctx.scale (factor, factor);
                page.render (ctx);
                surface.flush ();

                var pix = Gdk.pixbuf_get_from_surface (surface, 0, 0, sw, sh);
                if (pix != null) {
                    show_pixbuf (pix);
                } else {
                    show_icon (file);
                }
            } catch (Error e) {
                show_icon (file);
            }
        }

        private async void render_text (Files.File file, Cancellable cancel) {
            try {
                var stream = yield file.location.read_async (GLib.Priority.DEFAULT, cancel);
                var data = new GLib.ByteArray ();
                var buffer = new uint8[65536];
                while (data.len < MAX_TEXT_BYTES) {
                    ssize_t n = yield stream.read_async (buffer, GLib.Priority.DEFAULT, cancel);
                    if (n <= 0) {
                        break;
                    }
                    data.append (buffer[0:n]);
                }

                if (cancel.is_cancelled () || current_file != file) {
                    return;
                }

                unowned string text = (string) data.data;
                if (!text.validate ((ssize_t) data.len)) {
                    show_icon (file); // not valid UTF-8 → treat as binary
                    return;
                }

                clear_content ();
                var view = new Gtk.TextView () {
                    editable = false,
                    cursor_visible = false,
                    monospace = true,
                    wrap_mode = Gtk.WrapMode.WORD_CHAR,
                    left_margin = 6,
                    right_margin = 6,
                    top_margin = 6,
                    bottom_margin = 6
                };
                view.buffer.set_text (text, (int) data.len);

                var scroller = new Gtk.ScrolledWindow (null, null) {
                    hscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                    vscrollbar_policy = Gtk.PolicyType.AUTOMATIC,
                    vexpand = true,
                    child = view
                };
                content_holder.add (scroller);
                content_holder.show_all ();
            } catch (Error e) {
                if (!cancel.is_cancelled () && current_file == file) {
                    show_icon (file);
                }
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

            if (file.tags.length > 0) {
                var tags_key = new Gtk.Label (_("Tags")) {
                    halign = Gtk.Align.END,
                    xalign = 1
                };
                tags_key.get_style_context ().add_class ("dim-label");

                var tags_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4) {
                    halign = Gtk.Align.START
                };
                var scale = get_scale_factor ();
                foreach (unowned string key in file.tags) {
                    var dot = Files.TagManager.dot_pixbuf (key, 12, scale);
                    if (dot != null) {
                        tags_box.add (new Gtk.Image.from_surface (
                            Gdk.cairo_surface_create_from_pixbuf (dot, scale, null)
                        ));
                    }
                }
                var names = new string[file.tags.length];
                for (int i = 0; i < file.tags.length; i++) {
                    names[i] = Files.TagManager.display_name (file.tags[i]);
                }
                tags_box.add (new Gtk.Label (string.joinv (", ", names)) {
                    xalign = 0
                });

                info_grid.attach (tags_key, 0, row, 1, 1);
                info_grid.attach (tags_box, 1, row, 1, 1);
                row++;
            }

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
