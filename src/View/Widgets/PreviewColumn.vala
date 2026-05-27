/*
 * Finder-style preview column for the Miller (column) view.
 * Renders the actual content of the selected file (image, PDF first page, text)
 * with a large icon fallback, plus a metadata grid.
 */

namespace Files.View {
    public class PreviewColumn : Gtk.Box {
        private const int ICON_SIZE = 256;
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
        private Gdk.Pixbuf? source_pixbuf = null;
        private Poppler.Document? pdf_doc = null;
        private Poppler.Page? pdf_page = null;
        private int rendered_width = 0;
        private uint resize_timeout_id = 0;

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

            size_allocate.connect (on_size_allocate);
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
            source_pixbuf = null;
            pdf_doc = null;
            pdf_page = null;
            rendered_width = 0;
            if (resize_timeout_id > 0) {
                GLib.Source.remove (resize_timeout_id);
                resize_timeout_id = 0;
            }

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

        private int target_width () {
            int w = get_allocated_width ();
            return (w > 48) ? w - 24 : ICON_SIZE; // minus margins; fallback before allocation
        }

        private void show_surface (Cairo.Surface surface) {
            clear_content ();
            var image = new Gtk.Image.from_surface (surface) {
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.START
            };
            content_holder.add (image);
            content_holder.show_all ();
        }

        private void show_icon (Files.File file) {
            var scale = get_scale_factor ();
            var pix = file.get_icon_pixbuf (ICON_SIZE, scale);
            if (pix != null) {
                show_surface (Gdk.cairo_surface_create_from_pixbuf (pix, scale, null));
            }
        }

        private async void render_image (Files.File file, Cancellable cancel) {
            try {
                var stream = yield file.location.read_async (GLib.Priority.DEFAULT, cancel);
                var pix = yield new Gdk.Pixbuf.from_stream_async (stream, cancel);
                if (cancel.is_cancelled () || current_file != file) {
                    return;
                }
                source_pixbuf = pix;
                scale_and_show_pixbuf ();
            } catch (Error e) {
                if (!cancel.is_cancelled () && current_file == file) {
                    show_icon (file);
                }
            }
        }

        /* Scales the cached source image to the panel's current width and shows it. */
        private void scale_and_show_pixbuf () {
            if (source_pixbuf == null) {
                return;
            }
            int tw = target_width ();
            if (tw < 1 || source_pixbuf.width < 1) {
                return;
            }
            var scale = get_scale_factor ();
            int target_px = tw * scale;
            int dh = (int) ((double) source_pixbuf.height * target_px / source_pixbuf.width);
            if (target_px < 1 || dh < 1) {
                return;
            }
            var scaled = source_pixbuf.scale_simple (target_px, dh, Gdk.InterpType.BILINEAR);
            rendered_width = tw;
            show_surface (Gdk.cairo_surface_create_from_pixbuf (scaled, scale, null));
        }

        private void render_pdf (Files.File file) {
            try {
                pdf_doc = new Poppler.Document.from_gfile (file.location, null, cancellable);
                if (pdf_doc.get_n_pages () < 1) {
                    show_icon (file);
                    return;
                }
                pdf_page = pdf_doc.get_page (0);
                render_pdf_page ();
            } catch (Error e) {
                show_icon (file);
            }
        }

        /* Renders the cached first PDF page at the panel's current width. */
        private void render_pdf_page () {
            if (pdf_page == null) {
                return;
            }
            int tw = target_width ();
            if (tw < 1) {
                return;
            }
            double pw, ph;
            pdf_page.get_size (out pw, out ph);

            var scale = get_scale_factor ();
            double target = tw * scale;
            double factor = (pw > 0) ? target / pw : 1.0;
            int sw = (int) (pw * factor);
            int sh = (int) (ph * factor);
            if (sw < 1 || sh < 1) {
                return;
            }

            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, sw, sh);
            var ctx = new Cairo.Context (surface);
            ctx.set_source_rgb (1, 1, 1); // white page background
            ctx.paint ();
            ctx.scale (factor, factor);
            pdf_page.render (ctx);
            surface.flush ();
            surface.set_device_scale (scale, scale);
            rendered_width = tw;
            show_surface (surface);
        }

        /* Re-render image/PDF when the panel width changes (debounced). */
        private void on_size_allocate (Gtk.Allocation alloc) {
            if (source_pixbuf == null && pdf_page == null) {
                return;
            }
            if (target_width () == rendered_width || resize_timeout_id > 0) {
                return;
            }
            resize_timeout_id = GLib.Timeout.add (50, () => {
                resize_timeout_id = 0;
                if (source_pixbuf != null) {
                    scale_and_show_pixbuf ();
                } else if (pdf_page != null) {
                    render_pdf_page ();
                }
                return Source.REMOVE;
            });
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
