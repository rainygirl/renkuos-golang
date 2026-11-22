// Copyright 2026 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package net

// Haiku has no /etc/hosts: libnetwork reads the hosts file from the
// network settings directory, next to resolv.conf (see dnsclient_unix.go).
// Without this, the pure Go resolver cannot resolve "localhost".
func init() {
	hostsFilePath = "/boot/system/settings/network/hosts"
}
