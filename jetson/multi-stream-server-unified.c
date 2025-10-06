/* multi-stream-server-unified.c */

#include <gst/gst.h>
#include <gst/rtsp-server/rtsp-server.h>
#include <gst/rtsp/rtsp.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <stdio.h>

// Global variables for connection tracking
static gint connection_count = 0;

// Function to get current timestamp
static gchar* get_timestamp() {
    time_t now = time(0);
    struct tm *tm_info = localtime(&now);
    static gchar timestamp[64];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", tm_info);
    return timestamp;
}

// Function to log new connections
static void on_new_connection(GstRTSPServer *server __attribute__((unused)), GstRTSPClient *client, gpointer user_data __attribute__((unused))) {
    GstRTSPConnection *conn = gst_rtsp_client_get_connection(client);
    if (conn) {
        const gchar *remote_ip = gst_rtsp_connection_get_ip(conn);
        connection_count++;
        
        printf("\n[%s] NEW CONNECTION #%d\n", get_timestamp(), connection_count);
        printf("  Client IP: %s\n", remote_ip ? remote_ip : "unknown");
        printf("  Connection established\n");
        printf("----------------------------------------\n");
    }
}


int main(int argc, char *argv[])
{
    GMainLoop *loop;
    GstRTSPServer *server;
    GstRTSPMountPoints *mounts;
    gint i;
    gchar *port = "8554";  // Default port
    gint start_arg = 1;    // Default start argument index

    gst_init(&argc, &argv);

    // Check for --port flag
    if (argc >= 3 && strcmp(argv[1], "--port") == 0) {
        if (argc < 5 || argc % 2 != 1) {
            g_printerr("Usage: %s --port <port> [mount_point pipeline_description]...\n", argv[0]);
            g_printerr("Example: %s --port 8555 /cam1 \"( v4l2src device=/dev/video0 ! ... )\"\n", argv[0]);
            return -1;
        }
        port = argv[2];
        start_arg = 3;
    } else if (argc < 3 || argc % 2 != 1) {
        g_printerr("Usage: %s [--port <port>] [mount_point pipeline_description]...\n", argv[0]);
        g_printerr("Example: %s /cam1 \"( v4l2src device=/dev/video0 ! ... )\"\n", argv[0]);
        g_printerr("Example: %s --port 8555 /cam1 \"( v4l2src device=/dev/video0 ! ... )\"\n", argv[0]);
        return -1;
    }

    loop = g_main_loop_new(NULL, FALSE);

    server = gst_rtsp_server_new();
    g_object_set(server, "service", port, NULL);

    // Connect signal handler for connection monitoring
    g_signal_connect(server, "client-connected", G_CALLBACK(on_new_connection), NULL);

    mounts = gst_rtsp_server_get_mount_points(server);

    for (i = start_arg; i < argc; i += 2) {
        gchar *mount_point = argv[i];
        gchar *pipeline_desc = argv[i + 1];
        GstRTSPMediaFactory *factory;

        factory = gst_rtsp_media_factory_new();
        gst_rtsp_media_factory_set_launch(factory, pipeline_desc);
        gst_rtsp_media_factory_set_shared(factory, TRUE);
        gst_rtsp_mount_points_add_factory(mounts, mount_point, factory);

        g_print("Added stream: %s\n", mount_point);
    }

    g_object_unref(mounts);

    if (gst_rtsp_server_attach(server, NULL) == 0) {
        g_printerr("Failed to attach the server\n");
        return -1;
    }

    g_print("\nRTSP server is listening on rtsp://0.0.0.0:%s/\n", port);
    g_print("Connection monitoring enabled - will show client connections\n");
    g_print("Press Ctrl+C to stop the server\n\n");

    g_main_loop_run(loop);

    return 0;
}
