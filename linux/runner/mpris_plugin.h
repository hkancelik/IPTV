#ifndef RUNNER_MPRIS_PLUGIN_H_
#define RUNNER_MPRIS_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

typedef struct _MprisPlugin MprisPlugin;

/// Registers the Linux MPRIS2 D-Bus system media controls plugin on
/// `iptv/system_media_controls` and returns an owned handle.
MprisPlugin* mpris_plugin_register(FlPluginRegistry* registry,
                                   GtkApplication* application,
                                   GtkWindow* window);

/// Releases D-Bus resources, disconnects window signals, and frees the plugin.
void mpris_plugin_dispose(MprisPlugin* plugin);

#endif  // RUNNER_MPRIS_PLUGIN_H_
