#include "mpris_plugin.h"

#include <cstdint>
#include <memory>
#include <string>

#include "mpris_server.h"

namespace {

constexpr const char* kChannelName = "iptv/system_media_controls";

std::string ReadString(FlValue* map, const char* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) return "";
  FlValue* val = fl_value_lookup_string(map, key);
  if (val != nullptr && fl_value_get_type(val) == FL_VALUE_TYPE_STRING) {
    return fl_value_get_string(val);
  }
  return "";
}

bool ReadBool(FlValue* map, const char* key, bool fallback = false) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* val = fl_value_lookup_string(map, key);
  if (val != nullptr && fl_value_get_type(val) == FL_VALUE_TYPE_BOOL) {
    return fl_value_get_bool(val);
  }
  return fallback;
}

int64_t ReadInt64(FlValue* map, const char* key, int64_t fallback = 0) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* val = fl_value_lookup_string(map, key);
  if (val == nullptr) return fallback;
  const FlValueType type = fl_value_get_type(val);
  if (type == FL_VALUE_TYPE_INT) {
    return fl_value_get_int(val);
  }
  if (type == FL_VALUE_TYPE_FLOAT) {
    return static_cast<int64_t>(fl_value_get_float(val));
  }
  return fallback;
}

double ReadDouble(FlValue* map, const char* key, double fallback = 0.0) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return fallback;
  }
  FlValue* val = fl_value_lookup_string(map, key);
  if (val == nullptr) return fallback;
  const FlValueType type = fl_value_get_type(val);
  if (type == FL_VALUE_TYPE_FLOAT) {
    return fl_value_get_float(val);
  }
  if (type == FL_VALUE_TYPE_INT) {
    return static_cast<double>(fl_value_get_int(val));
  }
  return fallback;
}

}  // namespace

struct _MprisPlugin {
  FlMethodChannel* channel = nullptr;
  GtkApplication* application = nullptr;
  GtkWindow* window = nullptr;
  gulong window_destroy_handler = 0;
  std::unique_ptr<MprisServer> server;
};

namespace {

void InvokeFlutter(MprisPlugin* plugin, const char* method, FlValue* args) {
  if (plugin == nullptr || plugin->channel == nullptr) {
    if (args != nullptr) fl_value_unref(args);
    return;
  }
  fl_method_channel_invoke_method(plugin->channel, method, args, nullptr,
                                  nullptr, nullptr);
  if (args != nullptr) {
    fl_value_unref(args);
  }
}

void OnWindowDestroyed(GtkWidget* /*widget*/, gpointer user_data) {
  auto* plugin = static_cast<MprisPlugin*>(user_data);
  plugin->window = nullptr;
  plugin->window_destroy_handler = 0;
}

void HandleMethodCall(FlMethodChannel* /*channel*/,
                      FlMethodCall* method_call,
                      gpointer user_data) {
  auto* plugin = static_cast<MprisPlugin*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "update") == 0) {
    MprisState state;
    state.track_id = ReadString(args, "trackId");
    state.title = ReadString(args, "title");
    state.subtitle = ReadString(args, "subtitle");
    state.album = ReadString(args, "album");
    state.art_url = ReadString(args, "artUrl");
    state.local_url = ReadString(args, "localUrl");
    state.live = ReadBool(args, "live", false);
    state.playing = ReadBool(args, "playing", false);
    state.position_ms = ReadInt64(args, "positionMs", 0);
    state.duration_ms = ReadInt64(args, "durationMs", 0);
    state.rate = ReadDouble(args, "rate", 1.0);
    state.volume = ReadDouble(args, "volume", 1.0);
    state.can_go_next = ReadBool(args, "canGoNext", false);
    state.can_go_previous = ReadBool(args, "canGoPrevious", false);
    state.can_seek = ReadBool(args, "canSeek", false);
    const bool seeked = ReadBool(args, "seeked", false);
    plugin->server->Update(state, seeked);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "seeked") == 0) {
    const int64_t pos_ms = ReadInt64(args, "positionMs", 0);
    plugin->server->NotifySeeked(pos_ms);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "clear") == 0) {
    plugin->server->Clear();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send MPRIS plugin response: %s", error->message);
  }
}

}  // namespace

MprisPlugin* mpris_plugin_register(FlPluginRegistry* registry,
                                   GtkApplication* application,
                                   GtkWindow* window) {
  auto* plugin = new MprisPlugin();
  plugin->application = application;
  plugin->window = window;

  if (window != nullptr) {
    plugin->window_destroy_handler = g_signal_connect(
        G_OBJECT(window), "destroy", G_CALLBACK(OnWindowDestroyed), plugin);
  }

  MprisCallbacks callbacks;
  callbacks.on_play = [plugin]() { InvokeFlutter(plugin, "play", nullptr); };
  callbacks.on_pause = [plugin]() { InvokeFlutter(plugin, "pause", nullptr); };
  callbacks.on_play_pause = [plugin]() {
    InvokeFlutter(plugin, "playPause", nullptr);
  };
  callbacks.on_stop = [plugin]() { InvokeFlutter(plugin, "stop", nullptr); };
  callbacks.on_next = [plugin]() { InvokeFlutter(plugin, "next", nullptr); };
  callbacks.on_previous = [plugin]() {
    InvokeFlutter(plugin, "previous", nullptr);
  };
  callbacks.on_seek = [plugin](int64_t pos_ms) {
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "positionMs", fl_value_new_int(pos_ms));
    InvokeFlutter(plugin, "seek", map);
  };
  callbacks.on_seek_by = [plugin](int64_t offset_ms) {
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "offsetMs", fl_value_new_int(offset_ms));
    InvokeFlutter(plugin, "seekBy", map);
  };
  callbacks.on_set_volume = [plugin](double vol) {
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "volume", fl_value_new_float(vol));
    InvokeFlutter(plugin, "setVolume", map);
  };
  callbacks.on_set_rate = [plugin](double rate) {
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "rate", fl_value_new_float(rate));
    InvokeFlutter(plugin, "setRate", map);
  };
  callbacks.on_raise = [plugin]() {
    if (plugin->window != nullptr) {
      gtk_window_deiconify(plugin->window);
      gtk_window_present(plugin->window);
    }
  };
  callbacks.on_quit = [plugin]() {
    if (plugin->application != nullptr) {
      g_application_quit(G_APPLICATION(plugin->application));
    }
  };

  plugin->server = std::unique_ptr<MprisServer>(
      new MprisServer("IPTV", APPLICATION_ID, std::move(callbacks)));

  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "MprisPlugin");
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(plugin->channel, HandleMethodCall,
                                            plugin, nullptr);

  return plugin;
}

void mpris_plugin_dispose(MprisPlugin* plugin) {
  if (plugin == nullptr) return;
  if (plugin->window != nullptr && plugin->window_destroy_handler != 0) {
    g_signal_handler_disconnect(G_OBJECT(plugin->window),
                                plugin->window_destroy_handler);
    plugin->window_destroy_handler = 0;
  }
  plugin->window = nullptr;
  plugin->application = nullptr;
  if (plugin->channel != nullptr) {
    fl_method_channel_set_method_call_handler(plugin->channel, nullptr, nullptr,
                                              nullptr);
    g_clear_object(&plugin->channel);
  }
  if (plugin->server) {
    plugin->server->Clear();
    plugin->server.reset();
  }
  delete plugin;
}
