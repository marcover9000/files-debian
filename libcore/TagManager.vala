/*
 * Central registry for the fixed Finder-style colour tag palette: keys,
 * localized names, colours, and cached coloured-dot pixbufs.
 */

namespace Files {
    public class TagManager : GLib.Object {
        private const string[] KEYS = {
            "red", "orange", "yellow", "green", "blue", "purple", "gray"
        };

        private static Gee.HashMap<string, Gdk.Pixbuf>? dot_cache = null;

        public static unowned string[] all_keys () {
            return KEYS;
        }

        public static bool is_valid (string key) {
            foreach (unowned string k in KEYS) {
                if (k == key) {
                    return true;
                }
            }
            return false;
        }

        public static string display_name (string key) {
            switch (key) {
                case "red": return _("Red");
                case "orange": return _("Orange");
                case "yellow": return _("Yellow");
                case "green": return _("Green");
                case "blue": return _("Blue");
                case "purple": return _("Purple");
                case "gray": return _("Gray");
                default: return key;
            }
        }

        public static Gdk.RGBA color (string key) {
            var rgba = Gdk.RGBA ();
            switch (key) {
                case "red": rgba.parse ("#e01b24"); break;
                case "orange": rgba.parse ("#ff7800"); break;
                case "yellow": rgba.parse ("#f6d32d"); break;
                case "green": rgba.parse ("#33d17a"); break;
                case "blue": rgba.parse ("#3584e4"); break;
                case "purple": rgba.parse ("#9141ac"); break;
                default: rgba.parse ("#9a9996"); break; // gray / fallback
            }
            return rgba;
        }

        /* Filled circle of the tag colour, cached by (key, device pixels). */
        public static Gdk.Pixbuf? dot_pixbuf (string key, int size, int scale) {
            if (!is_valid (key)) {
                return null;
            }
            if (dot_cache == null) {
                dot_cache = new Gee.HashMap<string, Gdk.Pixbuf> ();
            }

            int px = size * scale;
            var cache_key = "%s-%d".printf (key, px);
            if (dot_cache.has_key (cache_key)) {
                return dot_cache.@get (cache_key);
            }

            var surface = new Cairo.ImageSurface (Cairo.Format.ARGB32, px, px);
            var cr = new Cairo.Context (surface);
            var rgba = color (key);
            double r = px / 2.0;
            double margin = px * 0.12;
            cr.arc (r, r, r - margin, 0, 2 * GLib.Math.PI);
            cr.set_source_rgba (rgba.red, rgba.green, rgba.blue, 1.0);
            cr.fill_preserve ();
            cr.set_source_rgba (0, 0, 0, 0.18); // subtle outline for contrast
            cr.set_line_width (px * 0.06);
            cr.stroke ();
            surface.flush ();

            var pix = Gdk.pixbuf_get_from_surface (surface, 0, 0, px, px);
            if (pix != null) {
                dot_cache.@set (cache_key, pix);
            }
            return pix;
        }
    }
}
