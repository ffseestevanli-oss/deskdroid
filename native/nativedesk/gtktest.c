/*
 * DeskDroid: a first GTK 3 window on the native desktop (stage 6, towards
 * Floorp). A plain program shipped as libdd_gtktest.so and started as
 * bin/gtktest from Plasma's menu; GTK talks Wayland to KWin like the KDE apps.
 */
#include <gtk/gtk.h>

static void clicked(GtkButton *button, gpointer entry)
{
    char *text = g_strdup_printf("Hello, %s!", gtk_entry_get_text(GTK_ENTRY(entry)));
    gtk_button_set_label(button, text);
    g_free(text);
}

static void activate(GtkApplication *app, gpointer unused)
{
    (void)unused;
    GtkWidget *win = gtk_application_window_new(app);
    gtk_window_set_title(GTK_WINDOW(win), "GTK on DeskDroid");
    gtk_window_set_default_size(GTK_WINDOW(win), 420, 220);
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
    gtk_container_set_border_width(GTK_CONTAINER(box), 24);
    char *about = g_strdup_printf("GTK %d.%d.%d, natively on Android", gtk_get_major_version(),
                                  gtk_get_minor_version(), gtk_get_micro_version());
    gtk_box_pack_start(GTK_BOX(box), gtk_label_new(about), FALSE, FALSE, 0);
    g_free(about);
    GtkWidget *entry = gtk_entry_new();
    gtk_entry_set_placeholder_text(GTK_ENTRY(entry), "Your name");
    gtk_box_pack_start(GTK_BOX(box), entry, FALSE, FALSE, 0);
    GtkWidget *button = gtk_button_new_with_label("Say hello");
    g_signal_connect(button, "clicked", G_CALLBACK(clicked), entry);
    gtk_box_pack_start(GTK_BOX(box), button, FALSE, FALSE, 0);
    gtk_container_add(GTK_CONTAINER(win), box);
    gtk_widget_show_all(win);
}

int main(int argc, char **argv)
{
    GtkApplication *app = gtk_application_new("org.deskdroid.GtkTest", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
