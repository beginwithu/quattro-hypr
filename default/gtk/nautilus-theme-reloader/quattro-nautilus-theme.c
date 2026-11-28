/*
 * Quattro Nautilus live theme CSS reloader.
 *
 * GTK4 / Libadwaita loads ~/.config/gtk-4.0/gtk.css only once at process
 * startup and never reloads it when theme files or GSettings change. This
 * lightweight Nautilus 4 extension watches Quattro's current theme directory
 * and ~/.config/gtk-4.0/ via GFileMonitor and reloads a high-priority
 * GtkCssProvider in-process so open Nautilus windows and background
 * --gapplication-service instances update live without restarting.
 */

#include <gio/gio.h>
#include <gtk/gtk.h>
#include <nautilus-extension.h>
#include <string.h>

static GtkCssProvider *theme_provider = NULL;
static GFileMonitor *state_monitor = NULL;
static GFileMonitor *gtk_config_monitor = NULL;
static gulong display_opened_handler = 0;
static guint reload_source_id = 0;
static guint retry_count = 0;
static gboolean initialized = FALSE;

static gchar *user_gtk_css_path = NULL;
static gchar *theme_gtk_css_path = NULL;

static const guint RELOAD_DEBOUNCE_MS = 50;
static const guint MAX_SWAP_RETRIES = 6;

static gboolean
load_active_css(void)
{
    if (theme_provider == NULL) {
        return FALSE;
    }

    const gchar *target = NULL;
    if (user_gtk_css_path != NULL && g_file_test(user_gtk_css_path, G_FILE_TEST_IS_REGULAR)) {
        /* If gtk-4.0/gtk.css imports current/theme/gtk.css while a swap is in
         * flight, wait briefly so @import resolves cleanly. */
        if (theme_gtk_css_path != NULL &&
            !g_file_test(theme_gtk_css_path, G_FILE_TEST_IS_REGULAR) &&
            retry_count < MAX_SWAP_RETRIES) {
            return FALSE;
        }
        target = user_gtk_css_path;
    } else if (theme_gtk_css_path != NULL && g_file_test(theme_gtk_css_path, G_FILE_TEST_IS_REGULAR)) {
        target = theme_gtk_css_path;
    }

    if (target == NULL) {
        return FALSE;
    }

    gtk_css_provider_load_from_path(theme_provider, target);
    retry_count = 0;
    return TRUE;
}

static gboolean
on_reload_timeout(gpointer user_data)
{
    (void)user_data;
    reload_source_id = 0;

    if (!load_active_css() && retry_count < MAX_SWAP_RETRIES) {
        retry_count++;
        reload_source_id = g_timeout_add(RELOAD_DEBOUNCE_MS, on_reload_timeout, NULL);
    }

    return G_SOURCE_REMOVE;
}

static void
schedule_reload(void)
{
    retry_count = 0;
    if (reload_source_id != 0) {
        g_source_remove(reload_source_id);
    }
    reload_source_id = g_timeout_add(RELOAD_DEBOUNCE_MS, on_reload_timeout, NULL);
}

static gboolean
is_relevant_event(GFileMonitorEvent event_type)
{
    switch (event_type) {
    case G_FILE_MONITOR_EVENT_CHANGED:
    case G_FILE_MONITOR_EVENT_CHANGES_DONE_HINT:
    case G_FILE_MONITOR_EVENT_CREATED:
    case G_FILE_MONITOR_EVENT_MOVED_IN:
    case G_FILE_MONITOR_EVENT_RENAMED:
    case G_FILE_MONITOR_EVENT_ATTRIBUTE_CHANGED:
        return TRUE;
    default:
        return FALSE;
    }
}

static void
on_state_dir_changed(GFileMonitor      *monitor,
                     GFile             *file,
                     GFile             *other_file,
                     GFileMonitorEvent  event_type,
                     gpointer           user_data)
{
    (void)monitor;
    (void)user_data;

    if (!is_relevant_event(event_type)) {
        return;
    }

    GFile *candidates[2] = { file, other_file };
    for (int i = 0; i < 2; i++) {
        if (candidates[i] == NULL) {
            continue;
        }
        gchar *name = g_file_get_basename(candidates[i]);
        gboolean match = (name != NULL) && (
            g_strcmp0(name, "theme") == 0 ||
            g_strcmp0(name, "theme.generation") == 0 ||
            g_strcmp0(name, "theme.name") == 0
        );
        g_free(name);
        if (match) {
            schedule_reload();
            return;
        }
    }
}

static void
on_gtk_config_dir_changed(GFileMonitor      *monitor,
                          GFile             *file,
                          GFile             *other_file,
                          GFileMonitorEvent  event_type,
                          gpointer           user_data)
{
    (void)monitor;
    (void)user_data;

    if (!is_relevant_event(event_type)) {
        return;
    }

    GFile *candidates[2] = { file, other_file };
    for (int i = 0; i < 2; i++) {
        if (candidates[i] == NULL) {
            continue;
        }
        gchar *name = g_file_get_basename(candidates[i]);
        gboolean match = (name != NULL && g_strcmp0(name, "gtk.css") == 0);
        g_free(name);
        if (match) {
            schedule_reload();
            return;
        }
    }
}

static void
attach_to_display(GdkDisplay *display)
{
    if (display == NULL || theme_provider != NULL) {
        return;
    }

    theme_provider = gtk_css_provider_new();
    gtk_style_context_add_provider_for_display(
        display,
        GTK_STYLE_PROVIDER(theme_provider),
        GTK_STYLE_PROVIDER_PRIORITY_USER + 1
    );
    load_active_css();
}

static void
on_display_opened(GdkDisplayManager *manager,
                  GdkDisplay        *display,
                  gpointer           user_data)
{
    (void)manager;
    (void)user_data;

    attach_to_display(display);
    if (display_opened_handler != 0 && manager != NULL) {
        g_signal_handler_disconnect(manager, display_opened_handler);
        display_opened_handler = 0;
    }
}

static void
setup_monitors(void)
{
    const gchar *state_home = g_get_user_state_dir();
    const gchar *config_home = g_get_user_config_dir();

    gchar *state_dir_path = g_build_filename(state_home, "quattro", "current", NULL);
    gchar *gtk_dir_path = g_build_filename(config_home, "gtk-4.0", NULL);

    user_gtk_css_path = g_build_filename(gtk_dir_path, "gtk.css", NULL);
    theme_gtk_css_path = g_build_filename(state_dir_path, "theme", "gtk.css", NULL);

    GFile *state_dir = g_file_new_for_path(state_dir_path);
    state_monitor = g_file_monitor_directory(state_dir, G_FILE_MONITOR_WATCH_MOVES, NULL, NULL);
    if (state_monitor != NULL) {
        g_signal_connect(state_monitor, "changed", G_CALLBACK(on_state_dir_changed), NULL);
    }
    g_object_unref(state_dir);

    GFile *gtk_dir = g_file_new_for_path(gtk_dir_path);
    gtk_config_monitor = g_file_monitor_directory(gtk_dir, G_FILE_MONITOR_WATCH_MOVES, NULL, NULL);
    if (gtk_config_monitor != NULL) {
        g_signal_connect(gtk_config_monitor, "changed", G_CALLBACK(on_gtk_config_dir_changed), NULL);
    }
    g_object_unref(gtk_dir);

    g_free(state_dir_path);
    g_free(gtk_dir_path);
}

void
nautilus_module_initialize(GTypeModule *module)
{
    if (initialized) {
        return;
    }
    initialized = TRUE;

    /* Keep this module resident even though it registers no GTypes. */
    if (module != NULL) {
        g_type_module_use(module);
    }

    setup_monitors();

    GdkDisplay *display = gdk_display_get_default();
    if (display != NULL) {
        attach_to_display(display);
    } else {
        GdkDisplayManager *manager = gdk_display_manager_get();
        if (manager != NULL) {
            display_opened_handler = g_signal_connect(
                manager,
                "display-opened",
                G_CALLBACK(on_display_opened),
                NULL
            );
        }
    }
}

void
nautilus_module_shutdown(void)
{
    if (reload_source_id != 0) {
        g_source_remove(reload_source_id);
        reload_source_id = 0;
    }

    if (display_opened_handler != 0) {
        GdkDisplayManager *manager = gdk_display_manager_get();
        if (manager != NULL) {
            g_signal_handler_disconnect(manager, display_opened_handler);
        }
        display_opened_handler = 0;
    }

    g_clear_object(&state_monitor);
    g_clear_object(&gtk_config_monitor);

    if (theme_provider != NULL) {
        GdkDisplay *display = gdk_display_get_default();
        if (display != NULL) {
            gtk_style_context_remove_provider_for_display(display, GTK_STYLE_PROVIDER(theme_provider));
        }
        g_clear_object(&theme_provider);
    }

    g_clear_pointer(&user_gtk_css_path, g_free);
    g_clear_pointer(&theme_gtk_css_path, g_free);
    initialized = FALSE;
}

void
nautilus_module_list_types(const GType **types,
                           int          *num_types)
{
    if (types != NULL) {
        *types = NULL;
    }
    if (num_types != NULL) {
        *num_types = 0;
    }
}
