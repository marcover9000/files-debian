/*
 * Helper for colour-tag names. Names are stored globally per user in the
 * `tag-names` gsettings key; index i (0-9) maps to colour i+1 (1-10). An empty
 * entry falls back to the generic colour name.
 */

namespace Files {
    public class ColorTags : GLib.Object {
        private static GLib.Settings? settings = null;

        private static GLib.Settings get_settings () {
            if (settings == null) {
                settings = new GLib.Settings ("io.elementary.files.preferences");
            }
            return settings;
        }

        public static string generic_name (int color) {
            switch (color) {
                case 1: return _("Blue");
                case 2: return _("Mint");
                case 3: return _("Green");
                case 4: return _("Yellow");
                case 5: return _("Orange");
                case 6: return _("Red");
                case 7: return _("Pink");
                case 8: return _("Purple");
                case 9: return _("Brown");
                case 10: return _("Slate");
                default: return "";
            }
        }

        public static string[] get_names () {
            var stored = get_settings ().get_strv ("tag-names");
            var result = new string[10];
            for (int i = 0; i < 10; i++) {
                result[i] = (i < stored.length) ? stored[i] : "";
            }
            return result;
        }

        public static void set_names (string[] names) {
            var arr = new string[10];
            for (int i = 0; i < 10; i++) {
                arr[i] = (i < names.length && names[i] != null) ? names[i] : "";
            }
            get_settings ().set_strv ("tag-names", arr);
        }

        public static int[] used_colors () {
            var v = get_settings ().get_value ("used-tag-colors");
            int[] result = {};
            for (int i = 0; i < (int) v.n_children (); i++) {
                result += v.get_child_value (i).get_int32 ();
            }
            return result;
        }

        public static void mark_used (int color) {
            if (color < 1 || color > 10) {
                return;
            }
            var current = used_colors ();
            foreach (int c in current) {
                if (c == color) {
                    return; // already listed
                }
            }
            current += color;
            get_settings ().set_value ("used-tag-colors", new GLib.Variant.array (new GLib.VariantType ("i"), variant_ints (current)));
        }

        public static void unmark_used (int color) {
            var current = used_colors ();
            int[] result = {};
            foreach (int c in current) {
                if (c != color) {
                    result += c;
                }
            }
            get_settings ().set_value ("used-tag-colors", new GLib.Variant.array (new GLib.VariantType ("i"), variant_ints (result)));
        }

        private static GLib.Variant[] variant_ints (int[] values) {
            GLib.Variant[] arr = {};
            foreach (int v in values) {
                arr += new GLib.Variant.int32 (v);
            }
            return arr;
        }

        public static bool show_as_dot () {
            return get_settings ().get_boolean ("color-tag-as-dot");
        }

        public static string display_name (int color) {
            if (color < 1 || color > 10) {
                return "";
            }
            var custom = get_names ()[color - 1];
            return (custom != null && custom != "") ? custom : generic_name (color);
        }
    }
}
