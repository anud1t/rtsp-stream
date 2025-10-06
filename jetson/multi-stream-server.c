/* multi-stream-server.c */

#include <gst/gst.h>
#include <gst/rtsp-server/rtsp-server.h>

int main(int argc, char *argv[])
{
    GMainLoop *loop;
    GstRTSPServer *server;
    GstRTSPMountPoints *mounts;
    GError *error = NULL;
    gint i;

    gst_init(&argc, &argv);

    if (argc < 3 || argc % 2 != 1) {
        g_printerr("Usage: %s [mount_point pipeline_description]...\n", argv[0]);
        g_printerr("Example: %s /cam1 \"( v4l2src device=/dev/video0 ! ... )\" /video1 \"( filesrc location=video.mp4 ! ... )\"\n", argv[0]);
        return -1;
    }

    loop = g_main_loop_new(NULL, FALSE);

    server = gst_rtsp_server_new();
    g_object_set(server, "service", "8554", NULL);

    mounts = gst_rtsp_server_get_mount_points(server);

    for (i = 1; i < argc; i += 2) {
        gchar *mount_point = argv[i];
        gchar *pipeline_desc = argv[i + 1];
        GstRTSPMediaFactory *factory;

        factory = gst_rtsp_media_factory_new();
        gst_rtsp_media_factory_set_launch(factory, pipeline_desc);
        gst_rtsp_media_factory_set_shared(factory, TRUE);
        gst_rtsp_mount_points_add_factory(mounts, mount_point, factory);

        g_print("Added stream %s\n", mount_point);
    }

    g_object_unref(mounts);

    if (gst_rtsp_server_attach(server, NULL) == 0) {
        g_printerr("Failed to attach the server\n");
        return -1;
    }

    /*g_print("RTSP server is listening on rtsp://0.0.0.0:8554/\n");*/

    g_main_loop_run(loop);

    return 0;
}
