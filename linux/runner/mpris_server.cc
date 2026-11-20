#include "mpris_server.h"

#include <unistd.h>

#include <algorithm>
#include <cmath>
#include <utility>

namespace {

constexpr const char* kMprisObjectPath = "/org/mpris/MediaPlayer2";
constexpr const char* kMprisRootInterface = "org.mpris.MediaPlayer2";
constexpr const char* kMprisPlayerInterface = "org.mpris.MediaPlayer2.Player";
constexpr const char* kPropertiesInterface = "org.freedesktop.DBus.Properties";
constexpr const char* kFallbackTrackId = "/dev/nailhakan/iptv/track/0";

constexpr const char* kMprisIntrospectionXml = R"XML(
<node>
  <interface name='org.mpris.MediaPlayer2'>
    <method name='Raise'/>
    <method name='Quit'/>
    <property name='CanQuit' type='b' access='read'/>
    <property name='Fullscreen' type='b' access='readwrite'/>
    <property name='CanSetFullscreen' type='b' access='read'/>
    <property name='CanRaise' type='b' access='read'/>
    <property name='HasTrackList' type='b' access='read'/>
    <property name='Identity' type='s' access='read'/>
    <property name='DesktopEntry' type='s' access='read'/>
    <property name='SupportedUriSchemes' type='as' access='read'/>
    <property name='SupportedMimeTypes' type='as' access='read'/>
  </interface>
  <interface name='org.mpris.MediaPlayer2.Player'>
    <method name='Next'/>
    <method name='Previous'/>
    <method name='Pause'/>
    <method name='PlayPause'/>
    <method name='Stop'/>
    <method name='Play'/>
    <method name='Seek'>
      <arg direction='in' name='Offset' type='x'/>
    </method>
    <method name='SetPosition'>
      <arg direction='in' name='TrackId' type='o'/>
      <arg direction='in' name='Position' type='x'/>
    </method>
    <method name='OpenUri'>
      <arg direction='in' name='Uri' type='s'/>
    </method>
    <signal name='Seeked'>
      <arg name='Position' type='x'/>
    </signal>
    <property name='PlaybackStatus' type='s' access='read'/>
    <property name='LoopStatus' type='s' access='readwrite'/>
    <property name='Rate' type='d' access='readwrite'/>
    <property name='Shuffle' type='b' access='readwrite'/>
    <property name='Metadata' type='a{sv}' access='read'/>
    <property name='Volume' type='d' access='readwrite'/>
    <property name='Position' type='x' access='read'/>
    <property name='MinimumRate' type='d' access='read'/>
    <property name='MaximumRate' type='d' access='read'/>
    <property name='CanGoNext' type='b' access='read'/>
    <property name='CanGoPrevious' type='b' access='read'/>
    <property name='CanPlay' type='b' access='read'/>
    <property name='CanPause' type='b' access='read'/>
    <property name='CanSeek' type='b' access='read'/>
    <property name='CanControl' type='b' access='read'/>
  </interface>
</node>
)XML";

}  // namespace

MprisServer::MprisServer(std::string identity,
                         std::string desktop_entry,
                         MprisCallbacks callbacks,
                         std::string bus_name)
    : identity_(EnsureValidUtf8(identity)),
      desktop_entry_(EnsureValidUtf8(desktop_entry)),
      bus_name_(bus_name.empty()
                    ? ("org.mpris.MediaPlayer2.iptv.instance" +
                       std::to_string(static_cast<long>(getpid())))
                    : std::move(bus_name)),
      callbacks_(std::move(callbacks)) {
  g_autoptr(GError) error = nullptr;
  introspection_data_ =
      g_dbus_node_info_new_for_xml(kMprisIntrospectionXml, &error);
  if (error != nullptr) {
    g_warning("MPRIS2 introspection XML parse failed: %s", error->message);
  }
}

MprisServer::~MprisServer() {
  Clear();
  if (introspection_data_ != nullptr) {
    g_dbus_node_info_unref(introspection_data_);
    introspection_data_ = nullptr;
  }
}

std::string MprisServer::EnsureValidUtf8(const std::string& input) {
  if (input.empty()) return input;
  if (g_utf8_validate(input.c_str(), static_cast<gssize>(input.size()),
                      nullptr)) {
    return input;
  }
  gchar* valid =
      g_utf8_make_valid(input.c_str(), static_cast<gssize>(input.size()));
  std::string out(valid != nullptr ? valid : "");
  g_free(valid);
  return out;
}

std::string MprisServer::SanitizeTrackId(const std::string& input) {
  if (!input.empty() && g_variant_is_object_path(input.c_str())) {
    return input;
  }
  return kFallbackTrackId;
}

bool MprisServer::MetadataEqual(const MprisState& a, const MprisState& b) {
  return a.track_id == b.track_id && a.title == b.title &&
         a.subtitle == b.subtitle && a.album == b.album &&
         a.art_url == b.art_url && a.local_url == b.local_url &&
         a.duration_ms == b.duration_ms;
}

int64_t MprisServer::CurrentPositionUs() const {
  if (!active_) return 0;
  int64_t pos = base_position_us_;
  if (state_.playing && state_.rate > 0.0 && base_monotonic_us_ > 0) {
    const int64_t elapsed = g_get_monotonic_time() - base_monotonic_us_;
    if (elapsed > 0) {
      pos += static_cast<int64_t>(static_cast<double>(elapsed) * state_.rate);
    }
  }
  if (pos < 0) pos = 0;
  const int64_t duration_us =
      state_.duration_ms > 0 ? state_.duration_ms * 1000 : 0;
  if (duration_us > 0 && pos > duration_us) {
    pos = duration_us;
  }
  return pos;
}

const char* MprisServer::PlaybackStatusString() const {
  if (!active_) return "Stopped";
  return state_.playing ? "Playing" : "Paused";
}

void MprisServer::Update(const MprisState& incoming, bool seeked) {
  MprisState next;
  next.track_id = SanitizeTrackId(incoming.track_id);
  next.title = EnsureValidUtf8(incoming.title);
  next.subtitle = EnsureValidUtf8(incoming.subtitle);
  next.album = EnsureValidUtf8(incoming.album);
  next.art_url = EnsureValidUtf8(incoming.art_url);
  next.local_url = EnsureValidUtf8(incoming.local_url);
  next.live = incoming.live;
  next.playing = incoming.playing;
  next.duration_ms = std::max<int64_t>(0, incoming.duration_ms);
  next.position_ms = std::max<int64_t>(0, incoming.position_ms);
  if (next.duration_ms > 0 && next.position_ms > next.duration_ms) {
    next.position_ms = next.duration_ms;
  }
  next.rate =
      (incoming.rate > 0.0 && std::isfinite(incoming.rate))
          ? std::max(0.25, std::min(4.0, incoming.rate))
          : 1.0;
  next.volume =
      std::isfinite(incoming.volume)
          ? std::max(0.0, std::min(1.0, incoming.volume))
          : 1.0;
  next.can_go_next = incoming.can_go_next;
  next.can_go_previous = incoming.can_go_previous;
  next.can_seek = incoming.can_seek && !incoming.live && next.duration_ms > 0;

  const bool was_active = active_;
  const MprisState prev = state_;

  active_ = true;
  state_ = next;
  base_position_us_ = state_.position_ms * 1000;
  base_monotonic_us_ = g_get_monotonic_time();

  if (!was_active) {
    StartBus();
    return;
  }

  if (connection_ == nullptr || player_reg_id_ == 0) {
    return;
  }

  GVariantBuilder changed;
  g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
  bool has_changes = false;

  if (prev.playing != state_.playing) {
    g_variant_builder_add(&changed, "{sv}", "PlaybackStatus",
                          g_variant_new_string(PlaybackStatusString()));
    has_changes = true;
  }
  if (!MetadataEqual(prev, state_)) {
    g_variant_builder_add(&changed, "{sv}", "Metadata", BuildMetadataVariant());
    has_changes = true;
  }
  if (prev.can_go_next != state_.can_go_next) {
    g_variant_builder_add(&changed, "{sv}", "CanGoNext",
                          g_variant_new_boolean(state_.can_go_next));
    has_changes = true;
  }
  if (prev.can_go_previous != state_.can_go_previous) {
    g_variant_builder_add(&changed, "{sv}", "CanGoPrevious",
                          g_variant_new_boolean(state_.can_go_previous));
    has_changes = true;
  }
  if (prev.can_seek != state_.can_seek) {
    g_variant_builder_add(&changed, "{sv}", "CanSeek",
                          g_variant_new_boolean(state_.can_seek));
    has_changes = true;
  }
  if (std::fabs(prev.rate - state_.rate) > 1e-4) {
    g_variant_builder_add(&changed, "{sv}", "Rate",
                          g_variant_new_double(state_.rate));
    has_changes = true;
  }
  if (std::fabs(prev.volume - state_.volume) > 1e-3) {
    g_variant_builder_add(&changed, "{sv}", "Volume",
                          g_variant_new_double(state_.volume));
    has_changes = true;
  }

  if (has_changes) {
    EmitPlayerPropertiesChanged(g_variant_builder_end(&changed));
  } else {
    g_variant_builder_clear(&changed);
  }

  if (seeked) {
    EmitSeeked(base_position_us_);
  }
}

void MprisServer::NotifySeeked(int64_t position_ms) {
  if (!active_) return;
  int64_t clamped = std::max<int64_t>(0, position_ms);
  if (state_.duration_ms > 0 && clamped > state_.duration_ms) {
    clamped = state_.duration_ms;
  }
  state_.position_ms = clamped;
  base_position_us_ = clamped * 1000;
  base_monotonic_us_ = g_get_monotonic_time();
  EmitSeeked(base_position_us_);
}

void MprisServer::Clear() {
  if (!active_ && owner_id_ == 0 && root_reg_id_ == 0 && player_reg_id_ == 0) {
    return;
  }
  const bool was_registered = (connection_ != nullptr && player_reg_id_ != 0);
  active_ = false;
  state_ = MprisState();
  base_position_us_ = 0;
  base_monotonic_us_ = 0;

  if (was_registered) {
    GVariantBuilder changed;
    g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&changed, "{sv}", "PlaybackStatus",
                          g_variant_new_string("Stopped"));
    g_variant_builder_add(&changed, "{sv}", "CanPlay",
                          g_variant_new_boolean(FALSE));
    g_variant_builder_add(&changed, "{sv}", "CanPause",
                          g_variant_new_boolean(FALSE));
    g_variant_builder_add(&changed, "{sv}", "CanSeek",
                          g_variant_new_boolean(FALSE));
    g_variant_builder_add(&changed, "{sv}", "CanGoNext",
                          g_variant_new_boolean(FALSE));
    g_variant_builder_add(&changed, "{sv}", "CanGoPrevious",
                          g_variant_new_boolean(FALSE));
    EmitPlayerPropertiesChanged(g_variant_builder_end(&changed));
  }

  StopBus();
}

void MprisServer::StartBus() {
  if (introspection_data_ == nullptr || owner_id_ != 0) return;
  ++bus_generation_;
  auto* ctx = new BusCallbackContext{this, bus_generation_};
  owner_id_ = g_bus_own_name(
      G_BUS_TYPE_SESSION, bus_name_.c_str(), G_BUS_NAME_OWNER_FLAGS_NONE,
      &MprisServer::OnBusAcquired, &MprisServer::OnNameAcquired,
      &MprisServer::OnNameLost, ctx, &MprisServer::FreeBusContext);
}

void MprisServer::StopBus() {
  ++bus_generation_;
  UnregisterObjects();
  if (owner_id_ != 0) {
    g_bus_unown_name(owner_id_);
    owner_id_ = 0;
  }
  g_clear_object(&connection_);
}

void MprisServer::RegisterObjects(GDBusConnection* connection) {
  if (introspection_data_ == nullptr || connection == nullptr) return;
  if (root_reg_id_ != 0 || player_reg_id_ != 0) return;

  static const GDBusInterfaceVTable root_vtable = {
      &MprisServer::HandleRootMethodCall,
      &MprisServer::HandleRootGetProperty,
      &MprisServer::HandleRootSetProperty,
      {nullptr},
  };
  static const GDBusInterfaceVTable player_vtable = {
      &MprisServer::HandlePlayerMethodCall,
      &MprisServer::HandlePlayerGetProperty,
      &MprisServer::HandlePlayerSetProperty,
      {nullptr},
  };

  g_autoptr(GError) root_err = nullptr;
  root_reg_id_ = g_dbus_connection_register_object(
      connection, kMprisObjectPath, introspection_data_->interfaces[0],
      &root_vtable, this, nullptr, &root_err);
  if (root_err != nullptr) {
    g_warning("MPRIS2 root interface registration failed: %s", root_err->message);
    root_reg_id_ = 0;
    return;
  }

  g_autoptr(GError) player_err = nullptr;
  player_reg_id_ = g_dbus_connection_register_object(
      connection, kMprisObjectPath, introspection_data_->interfaces[1],
      &player_vtable, this, nullptr, &player_err);
  if (player_err != nullptr) {
    g_warning("MPRIS2 player interface registration failed: %s",
              player_err->message);
    g_dbus_connection_unregister_object(connection, root_reg_id_);
    root_reg_id_ = 0;
    player_reg_id_ = 0;
    return;
  }
}

void MprisServer::UnregisterObjects() {
  if (connection_ != nullptr) {
    if (player_reg_id_ != 0) {
      g_dbus_connection_unregister_object(connection_, player_reg_id_);
      player_reg_id_ = 0;
    }
    if (root_reg_id_ != 0) {
      g_dbus_connection_unregister_object(connection_, root_reg_id_);
      root_reg_id_ = 0;
    }
  } else {
    player_reg_id_ = 0;
    root_reg_id_ = 0;
  }
}

void MprisServer::FreeBusContext(gpointer data) {
  delete static_cast<BusCallbackContext*>(data);
}

void MprisServer::OnBusAcquired(GDBusConnection* connection,
                                const gchar* /*name*/,
                                gpointer user_data) {
  auto* ctx = static_cast<BusCallbackContext*>(user_data);
  MprisServer* self = ctx->server;
  if (!self->active_ || ctx->generation != self->bus_generation_) return;

  g_clear_object(&self->connection_);
  self->connection_ = G_DBUS_CONNECTION(g_object_ref(connection));
  self->RegisterObjects(self->connection_);
}

void MprisServer::OnNameAcquired(GDBusConnection* /*connection*/,
                                 const gchar* /*name*/,
                                 gpointer user_data) {
  auto* ctx = static_cast<BusCallbackContext*>(user_data);
  MprisServer* self = ctx->server;
  if (!self->active_ || ctx->generation != self->bus_generation_) return;

  if (self->connection_ != nullptr && self->player_reg_id_ != 0) {
    GVariantBuilder changed;
    g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&changed, "{sv}", "PlaybackStatus",
                          g_variant_new_string(self->PlaybackStatusString()));
    g_variant_builder_add(&changed, "{sv}", "Metadata",
                          self->BuildMetadataVariant());
    g_variant_builder_add(&changed, "{sv}", "CanPlay",
                          g_variant_new_boolean(TRUE));
    g_variant_builder_add(&changed, "{sv}", "CanPause",
                          g_variant_new_boolean(TRUE));
    g_variant_builder_add(&changed, "{sv}", "CanGoNext",
                          g_variant_new_boolean(self->state_.can_go_next));
    g_variant_builder_add(&changed, "{sv}", "CanGoPrevious",
                          g_variant_new_boolean(self->state_.can_go_previous));
    g_variant_builder_add(&changed, "{sv}", "CanSeek",
                          g_variant_new_boolean(self->state_.can_seek));
    self->EmitPlayerPropertiesChanged(g_variant_builder_end(&changed));
  }
}

void MprisServer::OnNameLost(GDBusConnection* /*connection*/,
                             const gchar* /*name*/,
                             gpointer user_data) {
  auto* ctx = static_cast<BusCallbackContext*>(user_data);
  MprisServer* self = ctx->server;
  if (ctx->generation != self->bus_generation_) return;
  self->UnregisterObjects();
  g_clear_object(&self->connection_);
}

GVariant* MprisServer::BuildMetadataVariant() const {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));

  const std::string track_id = SanitizeTrackId(state_.track_id);
  g_variant_builder_add(&builder, "{sv}", "mpris:trackid",
                        g_variant_new_object_path(track_id.c_str()));

  if (!state_.title.empty()) {
    g_variant_builder_add(&builder, "{sv}", "xesam:title",
                          g_variant_new_string(state_.title.c_str()));
  }

  if (!state_.subtitle.empty()) {
    GVariantBuilder artists;
    g_variant_builder_init(&artists, G_VARIANT_TYPE("as"));
    g_variant_builder_add(&artists, "s", state_.subtitle.c_str());
    g_variant_builder_add(&builder, "{sv}", "xesam:artist",
                          g_variant_builder_end(&artists));
  }

  if (!state_.album.empty()) {
    g_variant_builder_add(&builder, "{sv}", "xesam:album",
                          g_variant_new_string(state_.album.c_str()));
  }

  if (!state_.art_url.empty()) {
    g_variant_builder_add(&builder, "{sv}", "mpris:artUrl",
                          g_variant_new_string(state_.art_url.c_str()));
  }

  if (!state_.local_url.empty()) {
    g_variant_builder_add(&builder, "{sv}", "xesam:url",
                          g_variant_new_string(state_.local_url.c_str()));
  }

  if (state_.duration_ms > 0) {
    g_variant_builder_add(&builder, "{sv}", "mpris:length",
                          g_variant_new_int64(state_.duration_ms * 1000));
  }

  return g_variant_builder_end(&builder);
}

void MprisServer::EmitPlayerPropertiesChanged(GVariant* changed_dict) {
  if (connection_ == nullptr || player_reg_id_ == 0) {
    if (changed_dict != nullptr) {
      g_variant_unref(g_variant_ref_sink(changed_dict));
    }
    return;
  }

  GVariantBuilder invalidated;
  g_variant_builder_init(&invalidated, G_VARIANT_TYPE("as"));

  GVariant* params =
      g_variant_new("(s@a{sv}@as)", kMprisPlayerInterface, changed_dict,
                    g_variant_builder_end(&invalidated));

  g_autoptr(GError) error = nullptr;
  g_dbus_connection_emit_signal(connection_, nullptr, kMprisObjectPath,
                                kPropertiesInterface, "PropertiesChanged",
                                params, &error);
  if (error != nullptr) {
    g_warning("MPRIS2 PropertiesChanged emit failed: %s", error->message);
  }
}

void MprisServer::EmitSeeked(int64_t position_us) {
  if (connection_ == nullptr || player_reg_id_ == 0) return;

  g_autoptr(GError) error = nullptr;
  g_dbus_connection_emit_signal(
      connection_, nullptr, kMprisObjectPath, kMprisPlayerInterface, "Seeked",
      g_variant_new("(x)", static_cast<gint64>(position_us)), &error);
  if (error != nullptr) {
    g_warning("MPRIS2 Seeked emit failed: %s", error->message);
  }
}

// MARK: - org.mpris.MediaPlayer2 (Root)

void MprisServer::HandleRootMethodCall(GDBusConnection* /*connection*/,
                                       const gchar* /*sender*/,
                                       const gchar* /*object_path*/,
                                       const gchar* /*interface_name*/,
                                       const gchar* method_name,
                                       GVariant* /*parameters*/,
                                       GDBusMethodInvocation* invocation,
                                       gpointer user_data) {
  auto* self = static_cast<MprisServer*>(user_data);
  if (g_strcmp0(method_name, "Raise") == 0) {
    if (self->callbacks_.on_raise) self->callbacks_.on_raise();
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else if (g_strcmp0(method_name, "Quit") == 0) {
    g_dbus_method_invocation_return_value(invocation, nullptr);
    if (self->callbacks_.on_quit) self->callbacks_.on_quit();
  } else {
    g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR,
                                          G_DBUS_ERROR_UNKNOWN_METHOD,
                                          "Unknown method: %s", method_name);
  }
}

GVariant* MprisServer::HandleRootGetProperty(GDBusConnection* /*connection*/,
                                             const gchar* /*sender*/,
                                             const gchar* /*object_path*/,
                                             const gchar* /*interface_name*/,
                                             const gchar* property_name,
                                             GError** error,
                                             gpointer user_data) {
  auto* self = static_cast<MprisServer*>(user_data);
  if (g_strcmp0(property_name, "CanQuit") == 0) {
    return g_variant_new_boolean(TRUE);
  }
  if (g_strcmp0(property_name, "Fullscreen") == 0) {
    return g_variant_new_boolean(FALSE);
  }
  if (g_strcmp0(property_name, "CanSetFullscreen") == 0) {
    return g_variant_new_boolean(FALSE);
  }
  if (g_strcmp0(property_name, "CanRaise") == 0) {
    return g_variant_new_boolean(TRUE);
  }
  if (g_strcmp0(property_name, "HasTrackList") == 0) {
    return g_variant_new_boolean(FALSE);
  }
  if (g_strcmp0(property_name, "Identity") == 0) {
    return g_variant_new_string(self->identity_.c_str());
  }
  if (g_strcmp0(property_name, "DesktopEntry") == 0) {
    return g_variant_new_string(self->desktop_entry_.c_str());
  }
  if (g_strcmp0(property_name, "SupportedUriSchemes") == 0 ||
      g_strcmp0(property_name, "SupportedMimeTypes") == 0) {
    GVariantBuilder empty;
    g_variant_builder_init(&empty, G_VARIANT_TYPE("as"));
    return g_variant_builder_end(&empty);
  }
  g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_PROPERTY,
              "Unknown property on %s: %s", kMprisRootInterface, property_name);
  return nullptr;
}

gboolean MprisServer::HandleRootSetProperty(GDBusConnection* /*connection*/,
                                            const gchar* /*sender*/,
                                            const gchar* /*object_path*/,
                                            const gchar* /*interface_name*/,
                                            const gchar* property_name,
                                            GVariant* /*value*/,
                                            GError** error,
                                            gpointer /*user_data*/) {
  if (g_strcmp0(property_name, "Fullscreen") == 0) {
    return TRUE;
  }
  g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_PROPERTY_READ_ONLY,
              "Property %s is not writable", property_name);
  return FALSE;
}

// MARK: - org.mpris.MediaPlayer2.Player

void MprisServer::HandlePlayerMethodCall(GDBusConnection* /*connection*/,
                                         const gchar* /*sender*/,
                                         const gchar* /*object_path*/,
                                         const gchar* /*interface_name*/,
                                         const gchar* method_name,
                                         GVariant* parameters,
                                         GDBusMethodInvocation* invocation,
                                         gpointer user_data) {
  auto* self = static_cast<MprisServer*>(user_data);

  if (g_strcmp0(method_name, "Play") == 0) {
    if (self->active_ && self->callbacks_.on_play) self->callbacks_.on_play();
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else if (g_strcmp0(method_name, "Pause") == 0) {
    if (self->active_ && self->callbacks_.on_pause) self->callbacks_.on_pause();
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else if (g_strcmp0(method_name, "PlayPause") == 0) {
    if (self->active_ && self->callbacks_.on_play_pause) {
      self->callbacks_.on_play_pause();
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else if (g_strcmp0(method_name, "Stop") == 0) {
    g_dbus_method_invocation_return_value(invocation, nullptr);
    if (self->active_ && self->callbacks_.on_stop) self->callbacks_.on_stop();
  } else if (g_strcmp0(method_name, "Next") == 0) {
    if (self->active_ && self->state_.can_go_next && self->callbacks_.on_next) {
      self->callbacks_.on_next();
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else if (g_strcmp0(method_name, "Previous") == 0) {
    if (self->active_ && self->state_.can_go_previous &&
        self->callbacks_.on_previous) {
      self->callbacks_.on_previous();
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else if (g_strcmp0(method_name, "Seek") == 0) {
    gint64 offset_us = 0;
    g_variant_get(parameters, "(x)", &offset_us);
    if (self->active_ && self->state_.can_seek && self->callbacks_.on_seek_by) {
      self->callbacks_.on_seek_by(static_cast<int64_t>(offset_us) / 1000);
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else if (g_strcmp0(method_name, "SetPosition") == 0) {
    const gchar* track_id = nullptr;
    gint64 pos_us = 0;
    g_variant_get(parameters, "(&ox)", &track_id, &pos_us);
    if (self->active_ && self->state_.can_seek && track_id != nullptr &&
        self->state_.track_id == track_id) {
      int64_t target_us = std::max<int64_t>(0, static_cast<int64_t>(pos_us));
      const int64_t duration_us = self->state_.duration_ms * 1000;
      if (duration_us > 0 && target_us > duration_us) {
        target_us = duration_us;
      }
      self->base_position_us_ = target_us;
      self->base_monotonic_us_ = g_get_monotonic_time();
      self->state_.position_ms = target_us / 1000;
      self->EmitSeeked(target_us);
      if (self->callbacks_.on_seek) {
        self->callbacks_.on_seek(target_us / 1000);
      }
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else if (g_strcmp0(method_name, "OpenUri") == 0) {
    g_dbus_method_invocation_return_value(invocation, nullptr);
  } else {
    g_dbus_method_invocation_return_error(invocation, G_DBUS_ERROR,
                                          G_DBUS_ERROR_UNKNOWN_METHOD,
                                          "Unknown method: %s", method_name);
  }
}

GVariant* MprisServer::HandlePlayerGetProperty(GDBusConnection* /*connection*/,
                                               const gchar* /*sender*/,
                                               const gchar* /*object_path*/,
                                               const gchar* /*interface_name*/,
                                               const gchar* property_name,
                                               GError** error,
                                               gpointer user_data) {
  auto* self = static_cast<MprisServer*>(user_data);

  if (g_strcmp0(property_name, "PlaybackStatus") == 0) {
    return g_variant_new_string(self->PlaybackStatusString());
  }
  if (g_strcmp0(property_name, "LoopStatus") == 0) {
    return g_variant_new_string("None");
  }
  if (g_strcmp0(property_name, "Rate") == 0) {
    return g_variant_new_double(self->state_.rate);
  }
  if (g_strcmp0(property_name, "Shuffle") == 0) {
    return g_variant_new_boolean(FALSE);
  }
  if (g_strcmp0(property_name, "Metadata") == 0) {
    return self->BuildMetadataVariant();
  }
  if (g_strcmp0(property_name, "Volume") == 0) {
    return g_variant_new_double(self->state_.volume);
  }
  if (g_strcmp0(property_name, "Position") == 0) {
    return g_variant_new_int64(static_cast<gint64>(self->CurrentPositionUs()));
  }
  if (g_strcmp0(property_name, "MinimumRate") == 0) {
    return g_variant_new_double(0.25);
  }
  if (g_strcmp0(property_name, "MaximumRate") == 0) {
    return g_variant_new_double(4.0);
  }
  if (g_strcmp0(property_name, "CanGoNext") == 0) {
    return g_variant_new_boolean(self->active_ && self->state_.can_go_next);
  }
  if (g_strcmp0(property_name, "CanGoPrevious") == 0) {
    return g_variant_new_boolean(self->active_ && self->state_.can_go_previous);
  }
  if (g_strcmp0(property_name, "CanPlay") == 0) {
    return g_variant_new_boolean(self->active_);
  }
  if (g_strcmp0(property_name, "CanPause") == 0) {
    return g_variant_new_boolean(self->active_);
  }
  if (g_strcmp0(property_name, "CanSeek") == 0) {
    return g_variant_new_boolean(self->active_ && self->state_.can_seek);
  }
  if (g_strcmp0(property_name, "CanControl") == 0) {
    return g_variant_new_boolean(TRUE);
  }

  g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_PROPERTY,
              "Unknown property on %s: %s", kMprisPlayerInterface,
              property_name);
  return nullptr;
}

gboolean MprisServer::HandlePlayerSetProperty(GDBusConnection* /*connection*/,
                                              const gchar* /*sender*/,
                                              const gchar* /*object_path*/,
                                              const gchar* /*interface_name*/,
                                              const gchar* property_name,
                                              GVariant* value,
                                              GError** error,
                                              gpointer user_data) {
  auto* self = static_cast<MprisServer*>(user_data);

  if (g_strcmp0(property_name, "Volume") == 0) {
    if (!g_variant_is_of_type(value, G_VARIANT_TYPE_DOUBLE)) {
      g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS,
                  "Volume expects a double");
      return FALSE;
    }
    const double raw = g_variant_get_double(value);
    const double vol =
        std::isfinite(raw) ? std::max(0.0, std::min(1.0, raw)) : 1.0;
    self->state_.volume = vol;
    GVariantBuilder changed;
    g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&changed, "{sv}", "Volume",
                          g_variant_new_double(vol));
    self->EmitPlayerPropertiesChanged(g_variant_builder_end(&changed));
    if (self->active_ && self->callbacks_.on_set_volume) {
      self->callbacks_.on_set_volume(vol);
    }
    return TRUE;
  }

  if (g_strcmp0(property_name, "Rate") == 0) {
    if (!g_variant_is_of_type(value, G_VARIANT_TYPE_DOUBLE)) {
      g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_INVALID_ARGS,
                  "Rate expects a double");
      return FALSE;
    }
    const double raw = g_variant_get_double(value);
    if (!std::isfinite(raw)) return TRUE;
    if (raw <= 0.0) {
      if (self->active_ && self->callbacks_.on_pause) {
        self->callbacks_.on_pause();
      }
      return TRUE;
    }
    if (self->active_ && !self->state_.live) {
      const double clamped = std::max(0.25, std::min(4.0, raw));
      self->state_.rate = clamped;
      GVariantBuilder changed;
      g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
      g_variant_builder_add(&changed, "{sv}", "Rate",
                            g_variant_new_double(clamped));
      self->EmitPlayerPropertiesChanged(g_variant_builder_end(&changed));
      if (self->callbacks_.on_set_rate) {
        self->callbacks_.on_set_rate(clamped);
      }
    }
    return TRUE;
  }

  if (g_strcmp0(property_name, "LoopStatus") == 0 ||
      g_strcmp0(property_name, "Shuffle") == 0) {
    return TRUE;
  }

  g_set_error(error, G_DBUS_ERROR, G_DBUS_ERROR_PROPERTY_READ_ONLY,
              "Property %s is not writable", property_name);
  return FALSE;
}
