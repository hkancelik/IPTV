#ifndef RUNNER_MPRIS_SERVER_H_
#define RUNNER_MPRIS_SERVER_H_

#include <gio/gio.h>

#include <cstdint>
#include <functional>
#include <string>

struct MprisState {
  std::string track_id = "/dev/nailhakan/iptv/track/0";
  std::string title;
  std::string subtitle;
  std::string album;
  std::string art_url;
  std::string local_url;
  bool live = false;
  bool playing = false;
  int64_t position_ms = 0;
  int64_t duration_ms = 0;
  double rate = 1.0;
  double volume = 1.0;
  bool can_go_next = false;
  bool can_go_previous = false;
  bool can_seek = false;
};

struct MprisCallbacks {
  std::function<void()> on_play;
  std::function<void()> on_pause;
  std::function<void()> on_play_pause;
  std::function<void()> on_stop;
  std::function<void()> on_next;
  std::function<void()> on_previous;
  std::function<void(int64_t position_ms)> on_seek;
  std::function<void(int64_t offset_ms)> on_seek_by;
  std::function<void(double volume)> on_set_volume;
  std::function<void(double rate)> on_set_rate;
  std::function<void()> on_raise;
  std::function<void()> on_quit;
};

/// Native Linux MPRIS2 D-Bus server (`org.mpris.MediaPlayer2` and
/// `org.mpris.MediaPlayer2.Player`) using GIO/GDBus.
///
/// Owns `org.mpris.MediaPlayer2.iptv.instance<pid>` while playback is active
/// and releases the bus name cleanly on `Clear()`, so KDE Plasma Media
/// Controller and Dynamic Island only display the player while media is open.
class MprisServer {
 public:
  MprisServer(std::string identity,
              std::string desktop_entry,
              MprisCallbacks callbacks,
              std::string bus_name = "");
  ~MprisServer();

  MprisServer(const MprisServer&) = delete;
  MprisServer& operator=(const MprisServer&) = delete;

  void Update(const MprisState& next, bool seeked = false);
  void NotifySeeked(int64_t position_ms);
  void Clear();

  const std::string& bus_name() const { return bus_name_; }
  bool is_active() const { return active_; }
  int64_t CurrentPositionUs() const;

 private:
  struct BusCallbackContext {
    MprisServer* server;
    uint64_t generation;
  };

  static void OnBusAcquired(GDBusConnection* connection,
                            const gchar* name,
                            gpointer user_data);
  static void OnNameAcquired(GDBusConnection* connection,
                             const gchar* name,
                             gpointer user_data);
  static void OnNameLost(GDBusConnection* connection,
                         const gchar* name,
                         gpointer user_data);
  static void FreeBusContext(gpointer data);

  static void HandleRootMethodCall(GDBusConnection* connection,
                                   const gchar* sender,
                                   const gchar* object_path,
                                   const gchar* interface_name,
                                   const gchar* method_name,
                                   GVariant* parameters,
                                   GDBusMethodInvocation* invocation,
                                   gpointer user_data);
  static GVariant* HandleRootGetProperty(GDBusConnection* connection,
                                         const gchar* sender,
                                         const gchar* object_path,
                                         const gchar* interface_name,
                                         const gchar* property_name,
                                         GError** error,
                                         gpointer user_data);
  static gboolean HandleRootSetProperty(GDBusConnection* connection,
                                        const gchar* sender,
                                        const gchar* object_path,
                                        const gchar* interface_name,
                                        const gchar* property_name,
                                        GVariant* value,
                                        GError** error,
                                        gpointer user_data);

  static void HandlePlayerMethodCall(GDBusConnection* connection,
                                     const gchar* sender,
                                     const gchar* object_path,
                                     const gchar* interface_name,
                                     const gchar* method_name,
                                     GVariant* parameters,
                                     GDBusMethodInvocation* invocation,
                                     gpointer user_data);
  static GVariant* HandlePlayerGetProperty(GDBusConnection* connection,
                                           const gchar* sender,
                                           const gchar* object_path,
                                           const gchar* interface_name,
                                           const gchar* property_name,
                                           GError** error,
                                           gpointer user_data);
  static gboolean HandlePlayerSetProperty(GDBusConnection* connection,
                                          const gchar* sender,
                                          const gchar* object_path,
                                          const gchar* interface_name,
                                          const gchar* property_name,
                                          GVariant* value,
                                          GError** error,
                                          gpointer user_data);

  void StartBus();
  void StopBus();
  void RegisterObjects(GDBusConnection* connection);
  void UnregisterObjects();
  const char* PlaybackStatusString() const;
  GVariant* BuildMetadataVariant() const;
  void EmitPlayerPropertiesChanged(GVariant* changed_dict);
  void EmitSeeked(int64_t position_us);
  static std::string EnsureValidUtf8(const std::string& input);
  static std::string SanitizeTrackId(const std::string& input);
  static bool MetadataEqual(const MprisState& a, const MprisState& b);

  std::string identity_;
  std::string desktop_entry_;
  std::string bus_name_;
  MprisCallbacks callbacks_;

  GDBusNodeInfo* introspection_data_ = nullptr;
  GDBusConnection* connection_ = nullptr;
  guint owner_id_ = 0;
  guint root_reg_id_ = 0;
  guint player_reg_id_ = 0;
  uint64_t bus_generation_ = 0;

  bool active_ = false;
  MprisState state_;
  int64_t base_position_us_ = 0;
  int64_t base_monotonic_us_ = 0;
};

#endif  // RUNNER_MPRIS_SERVER_H_
