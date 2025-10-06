/* multi-stream-server-unified.c */

#include <gst/gst.h>
#include <gst/rtsp-server/rtsp-server.h>
#include <string.h>
#include <stdlib.h>

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
    g_print("Press Ctrl+C to stop the server\n\n");

    g_main_loop_run(loop);

    return 0;
}
