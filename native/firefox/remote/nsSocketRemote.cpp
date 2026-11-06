/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// DeskDroid: see nsSocketRemote.h. One socket per profile, in the user's
// runtime folder. The client sends a 32-bit length and the command line
// (RemoteUtils' format, as the D-Bus remote sends it); the server answers
// with nsUnixRemoteServer's status line ("200 executed command").

#include "nsSocketRemote.h"
#include "RemoteUtils.h"
#include "mozilla/HashFunctions.h"
#include "mozilla/Span.h"
#include "mozilla/UniquePtr.h"
#include "nsPrintfCString.h"

#include <gio/gunixsocketaddress.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static constexpr uint32_t kMaxCommandLine = 1 << 20;

static nsCString SocketPath(const char* aProgram, const char* aProfile) {
  const char* dir = g_get_user_runtime_dir();
  g_mkdir_with_parents(dir, 0700);
  nsAutoCString key;
  key.AppendPrintf("%s\n%s", aProgram ? aProgram : "", aProfile);
  return nsPrintfCString("%s/mozilla-remote-%08x", dir,
                         mozilla::HashString(key));
}

nsresult nsSocketRemoteServer::Startup(const char* aAppName,
                                       const char* aProfileName) {
  if (mService) {
    return NS_OK;
  }
  mPath = SocketPath(aAppName, aProfileName);
  // This instance holds the profile, so a socket left there is stale.
  unlink(mPath.get());

  GSocketAddress* address = g_unix_socket_address_new(mPath.get());
  mService = g_socket_service_new();
  GError* error = nullptr;
  bool ok = g_socket_listener_add_address(
      G_SOCKET_LISTENER(mService), address, G_SOCKET_TYPE_STREAM,
      G_SOCKET_PROTOCOL_DEFAULT, nullptr, nullptr, &error);
  g_object_unref(address);
  if (!ok) {
    g_warning("nsSocketRemoteServer: %s", error ? error->message : "failed");
    g_clear_error(&error);
    g_object_unref(mService);
    mService = nullptr;
    return NS_ERROR_FAILURE;
  }
  chmod(mPath.get(), 0600);
  g_signal_connect(mService, "incoming", G_CALLBACK(OnIncoming), this);
  g_socket_service_start(mService);
  return NS_OK;
}

void nsSocketRemoteServer::Shutdown() {
  if (!mService) {
    return;
  }
  g_socket_service_stop(mService);
  g_socket_listener_close(G_SOCKET_LISTENER(mService));
  g_signal_handlers_disconnect_by_data(mService, this);
  g_object_unref(mService);
  mService = nullptr;
  unlink(mPath.get());
}

gboolean nsSocketRemoteServer::OnIncoming(GSocketService* aService,
                                          GSocketConnection* aConnection,
                                          GObject* aSource, gpointer aSelf) {
  auto* self = static_cast<nsSocketRemoteServer*>(aSelf);
  g_socket_set_timeout(g_socket_connection_get_socket(aConnection), 5);
  GInputStream* in = g_io_stream_get_input_stream(G_IO_STREAM(aConnection));
  GOutputStream* out = g_io_stream_get_output_stream(G_IO_STREAM(aConnection));

  uint32_t length = 0;
  gsize got = 0;
  if (!g_input_stream_read_all(in, &length, sizeof(length), &got, nullptr,
                               nullptr) ||
      got != sizeof(length) || length == 0 || length > kMaxCommandLine) {
    return TRUE;
  }
  mozilla::UniquePtr<char[]> buffer(new char[length]);
  if (!g_input_stream_read_all(in, buffer.get(), length, &got, nullptr,
                               nullptr) ||
      got != length) {
    return TRUE;
  }
  const char* response =
      self->HandleCommandLine(mozilla::Span(buffer.get(), length), 0);
  if (!response) {
    response = "509 internal error";
  }
  g_output_stream_write_all(out, response, strlen(response), nullptr, nullptr,
                            nullptr);
  return TRUE;
}

nsresult nsSocketRemoteClient::SendCommandLine(const char* aProgram,
                                               const char* aProfile,
                                               int32_t argc, const char** argv,
                                               bool aRaise) {
  NS_ENSURE_TRUE(aProfile, NS_ERROR_INVALID_ARG);

  int length = 0;
  mozilla::UniquePtr<char[]> commandLine = ConstructCommandLine(
      argc, argv,
      mStartupToken.IsEmpty() ? nullptr
                              : PromiseFlatCString(mStartupToken).get(),
      &length);
  if (!commandLine || length <= 0 || uint32_t(length) > kMaxCommandLine) {
    return NS_ERROR_FAILURE;
  }

  nsCString path = SocketPath(aProgram, aProfile);
  GSocketAddress* address = g_unix_socket_address_new(path.get());
  GSocketClient* client = g_socket_client_new();
  g_socket_client_set_timeout(client, 10);
  GSocketConnection* connection = g_socket_client_connect(
      client, G_SOCKET_CONNECTABLE(address), nullptr, nullptr);
  g_object_unref(address);
  g_object_unref(client);
  if (!connection) {
    // Nothing is listening: no browser is running with this profile.
    return NS_ERROR_NOT_AVAILABLE;
  }

  GOutputStream* out = g_io_stream_get_output_stream(G_IO_STREAM(connection));
  GInputStream* in = g_io_stream_get_input_stream(G_IO_STREAM(connection));
  uint32_t length32 = uint32_t(length);
  char response[64] = {};
  gsize got = 0;
  bool ok = g_output_stream_write_all(out, &length32, sizeof(length32),
                                      nullptr, nullptr, nullptr) &&
            g_output_stream_write_all(out, commandLine.get(), length32,
                                      nullptr, nullptr, nullptr) &&
            g_input_stream_read_all(in, response, sizeof(response) - 1, &got,
                                    nullptr, nullptr);
  g_io_stream_close(G_IO_STREAM(connection), nullptr, nullptr);
  g_object_unref(connection);
  return ok && got > 0 && response[0] == '2' ? NS_OK : NS_ERROR_FAILURE;
}
