/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// DeskDroid: Gecko's "remote" (a second start hands its command line to the
// running browser, which opens a new window or tab) over a Unix socket.
// Upstream does this over D-Bus or X11; DeskDroid's build has neither.

#ifndef nsSocketRemote_h_
#define nsSocketRemote_h_

#include <gio/gio.h>
#include "nsRemoteClient.h"
#include "nsRemoteServer.h"
#include "nsUnixRemoteServer.h"
#include "nsString.h"

class nsSocketRemoteServer final : public nsRemoteServer,
                                   public nsUnixRemoteServer {
 public:
  ~nsSocketRemoteServer() override { Shutdown(); }

  nsresult Startup(const char* aAppName, const char* aProfileName) override;
  void Shutdown() override;

 private:
  static gboolean OnIncoming(GSocketService* aService,
                             GSocketConnection* aConnection,
                             GObject* aSource, gpointer aSelf);

  GSocketService* mService = nullptr;
  nsCString mPath;
};

class nsSocketRemoteClient final : public nsRemoteClient {
 public:
  explicit nsSocketRemoteClient(nsACString& aStartupToken)
      : mStartupToken(aStartupToken) {}

  nsresult Init() override { return NS_OK; }
  nsresult SendCommandLine(const char* aProgram, const char* aProfile,
                           int32_t argc, const char** argv,
                           bool aRaise) override;

 private:
  nsCString mStartupToken;
};

#endif  // nsSocketRemote_h_
